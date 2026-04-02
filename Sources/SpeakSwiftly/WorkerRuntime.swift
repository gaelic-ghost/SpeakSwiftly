import Foundation

// MARK: - Worker Runtime

actor WorkerRuntime {
    private enum Environment {
        static let profileRootOverride = "SPEAKSWIFTLY_PROFILE_ROOT"
    }

    private enum PlaybackConfiguration {
        // Shorter chunk cadence gives playback a second chunk in reserve before
        // the first one drains, which reduces audible shudder from one-chunk starts.
        static let residentStreamingInterval = 0.18
    }

    private enum ResidentState: Sendable {
        case warming
        case ready(AnySpeechModel)
        case failed(WorkerError)
    }

    private struct ActiveRequest: Sendable {
        let token: UUID
        let request: WorkerRequest
        let task: Task<Void, Never>
    }

    private struct QueueEntry: Sendable, Equatable {
        let token = UUID()
        let request: WorkerRequest
    }

    private struct WorkerSuccessPayload: Sendable {
        let id: String
        let profileName: String?
        let profilePath: String?
        let profiles: [ProfileSummary]?

        init(id: String, profileName: String? = nil, profilePath: String? = nil, profiles: [ProfileSummary]? = nil) {
            self.id = id
            self.profileName = profileName
            self.profilePath = profilePath
            self.profiles = profiles
        }
    }

    private enum LogLevel: String, Encodable {
        case info
        case error
    }

    private enum LogValue: Encodable, Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            }
        }
    }

    private struct LogEvent: Encodable {
        let event: String
        let level: LogLevel
        let ts: String
        let requestID: String?
        let op: String?
        let profileName: String?
        let queueDepth: Int?
        let elapsedMS: Int?
        let details: [String: LogValue]?

        enum CodingKeys: String, CodingKey {
            case event
            case level
            case ts
            case requestID = "request_id"
            case op
            case profileName = "profile_name"
            case queueDepth = "queue_depth"
            case elapsedMS = "elapsed_ms"
            case details
        }
    }

    private let dependencies: WorkerDependencies
    private let encoder = JSONEncoder()
    private let logEncoder = JSONEncoder()
    private let profileStore: ProfileStore
    private let playbackController: AnyPlaybackController
    private let logTimestampFormatter = ISO8601DateFormatter()

    private var residentState: ResidentState = .warming
    private var queue = [QueueEntry]()
    private var activeRequest: ActiveRequest?
    private var isShuttingDown = false
    private var preloadTask: Task<Void, Never>?
    private var requestAcceptedAt = [String: Date]()

    init(
        dependencies: WorkerDependencies,
        profileStore: ProfileStore,
        playbackController: AnyPlaybackController
    ) {
        self.dependencies = dependencies
        self.profileStore = profileStore
        self.playbackController = playbackController
        encoder.outputFormatting = [.sortedKeys]
        logEncoder.outputFormatting = [.sortedKeys]
    }

    static func live() async -> WorkerRuntime {
        let dependencies = WorkerDependencies.live()
        let environment = ProcessInfo.processInfo.environment
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                overridePath: environment[Environment.profileRootOverride]
            ),
            fileManager: dependencies.fileManager
        )
        let playbackController = await dependencies.makePlaybackController()

        return WorkerRuntime(
            dependencies: dependencies,
            profileStore: profileStore,
            playbackController: playbackController
        )
    }

    func start() {
        preloadTask = Task {
            let preloadStartedAt = dependencies.now()
            await emitStatus(.warmingResidentModel)
            await logEvent(
                "resident_model_preload_started",
                details: [
                    "model_repo": .string(ModelFactory.residentModelRepo),
                    "profile_root": .string(profileStore.rootURL.path),
                ]
            )

            do {
                try profileStore.ensureRootExists()
                let model = try await dependencies.loadResidentModel()
                let playbackEngineWasPrepared = try await playbackController.prepare(sampleRate: Double(model.sampleRate))
                residentState = .ready(model)
                await emitStatus(.residentModelReady)
                await logEvent(
                    "resident_model_preload_ready",
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
                )
                if playbackEngineWasPrepared {
                    await logEvent(
                        "playback_engine_ready",
                        details: [
                            "sample_rate": .int(model.sampleRate),
                            "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                        ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
                    )
                }
                try await startNextRequestIfPossible()
            } catch is CancellationError {
                guard !isShuttingDown else { return }

                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload was cancelled before \(ModelFactory.residentModelRepo) finished loading."
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch let workerError as WorkerError {
                residentState = .failed(workerError)
                await logError(
                    "Resident model preload failed while loading \(ModelFactory.residentModelRepo). \(workerError.message)",
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                        "failure_code": .string(workerError.code.rawValue),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch {
                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload failed while loading \(ModelFactory.residentModelRepo). \(error.localizedDescription)"
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "model_repo": .string(ModelFactory.residentModelRepo),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            }
        }
    }

    func accept(line: String) async {
        let request: WorkerRequest

        do {
            request = try WorkerRequest.decode(from: line)
        } catch let workerError as WorkerError {
            let id = bestEffortID(from: line)
            await emitFailure(id: id, error: workerError)
            return
        } catch {
            await emitFailure(
                id: bestEffortID(from: line),
                error: WorkerError(code: .internalError, message: "The request could not be decoded due to an unexpected internal error. \(error.localizedDescription)")
            )
            return
        }

        if isShuttingDown {
            await emitFailure(
                id: request.id,
                error: WorkerError(
                    code: .workerShuttingDown,
                    message: "Request '\(request.id)' was rejected because the SpeakSwiftly worker is shutting down."
                )
            )
            return
        }

        if case .failed(let error) = residentState {
            await emitFailure(id: request.id, error: error)
            return
        }

        let entry = QueueEntry(request: request)
        requestAcceptedAt[request.id] = dependencies.now()
        await logRequestEvent(
            "request_accepted",
            requestID: request.id,
            op: request.opName,
            profileName: request.profileName,
            queueDepth: queue.count
        )
        queue.append(entry)
        if let queuedEvent = makeQueuedEvent(for: entry) {
            await emit(queuedEvent)
            await logRequestEvent(
                "request_queued",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: queue.count
            )
        }
        try? await startNextRequestIfPossible()
    }

    func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down."
        )

        if let activeRequest {
            self.activeRequest = nil
            activeRequest.task.cancel()
            await emitFailure(id: activeRequest.request.id, error: cancellationError)
        }

        await failQueuedRequests(with: cancellationError)
        await playbackController.stop()
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(queue.count)])
    }

    // MARK: - Processing

    private func startNextRequestIfPossible() async throws {
        guard !isShuttingDown else { return }
        guard activeRequest == nil else { return }

        switch residentState {
        case .warming:
            return
        case .failed(let error):
            await failQueuedRequests(with: error)
            return
        case .ready:
            break
        }

        guard let index = nextQueueIndex() else { return }

        let entry = queue.remove(at: index)
        await emitStarted(for: entry.request)
        await logRequestEvent(
            "request_started",
            requestID: entry.request.id,
            op: entry.request.opName,
            profileName: entry.request.profileName,
            queueDepth: queue.count
        )

        let task = Task {
            await self.process(entry.request, token: entry.token)
        }
        activeRequest = ActiveRequest(token: entry.token, request: entry.request, task: task)
    }

    private func process(_ request: WorkerRequest, token: UUID) async {
        let result: Result<WorkerSuccessPayload, WorkerError>

        do {
            switch request {
            case .speakLive(let id, let text, let profileName):
                try await handleSpeakLive(id: id, text: text, profileName: profileName)
                result = .success(WorkerSuccessPayload(id: id))

            case .createProfile(let id, let profileName, let text, let voiceDescription, let outputPath):
                let storedProfile = try await handleCreateProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath
                )
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        profileName: storedProfile.manifest.profileName,
                        profilePath: storedProfile.directoryURL.path
                    )
                )

            case .listProfiles(let id):
                let listStartedAt = dependencies.now()
                let profiles = try profileStore.listProfiles()
                await logRequestEvent(
                    "profiles_listed",
                    requestID: id,
                    op: request.opName,
                    details: [
                        "profile_root": .string(profileStore.rootURL.path),
                        "count": .int(profiles.count),
                        "duration_ms": .int(elapsedMS(since: listStartedAt)),
                    ]
                )
                result = .success(WorkerSuccessPayload(id: id, profiles: profiles))

            case .removeProfile(let id, let profileName):
                await emitProgress(id: id, stage: .removingProfile)
                let removeStartedAt = dependencies.now()
                try profileStore.removeProfile(named: profileName)
                await logRequestEvent(
                    "profile_removed",
                    requestID: id,
                    op: request.opName,
                    profileName: profileName,
                    details: [
                        "path": .string(profileStore.profileDirectoryURL(for: profileName).path),
                        "duration_ms": .int(elapsedMS(since: removeStartedAt)),
                    ]
                )
                result = .success(WorkerSuccessPayload(id: id, profileName: profileName))
            }
        } catch is CancellationError {
            result = .failure(cancellationError(for: request.id))
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .internalError,
                    message: "Request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)"
                )
            )
        }

        await finishActiveRequest(token: token, requestID: request.id, result: result)
    }

    private func handleSpeakLive(id: String, text: String, profileName: String) async throws {
        let residentModel = try residentModelOrThrow()
        let op = WorkerRequest.speakLive(id: id, text: text, profileName: profileName).opName
        let normalizedText = SpeechTextNormalizer.normalize(text)
        let textFeatures = SpeechTextNormalizer.forensicFeatures(originalText: text, normalizedText: normalizedText)

        await emitProgress(id: id, stage: .loadingProfile)
        let profileLoadStartedAt = dependencies.now()
        let profile = try profileStore.loadProfile(named: profileName)
        await logRequestEvent(
            "profile_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(profile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: profileLoadStartedAt)),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )

        let refAudioLoadStartedAt = dependencies.now()
        let refAudio = try dependencies.loadAudioSamples(profile.referenceAudioURL, residentModel.sampleRate)
        await logRequestEvent(
            "reference_audio_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(profile.referenceAudioURL.path),
                "duration_ms": .int(elapsedMS(since: refAudioLoadStartedAt)),
                "sample_rate": .int(residentModel.sampleRate),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .startingPlayback)
        let stream = residentModel.generateSamplesStream(
            text: normalizedText,
            voice: nil,
            refAudio: refAudio,
            refText: profile.manifest.sourceText,
            language: "English",
            streamingInterval: PlaybackConfiguration.residentStreamingInterval
        )

        let playbackSummary = try await playbackController.play(
            sampleRate: Double(residentModel.sampleRate),
            text: normalizedText,
            stream: stream
        ) { event in
            switch event {
            case .firstChunk:
                await self.emitProgress(id: id, stage: .bufferingAudio)
                await self.logRequestEvent(
                    "playback_first_chunk",
                    requestID: id,
                    op: op,
                    profileName: profileName
                )
            case .prerollReady(let startupBufferedAudioMS, let thresholds):
                await self.emitProgress(id: id, stage: .prerollReady)
                await self.logRequestEvent(
                    "playback_preroll_ready",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "text_complexity_class": .string(thresholds.complexityClass.rawValue),
                        "startup_buffer_target_ms": .int(thresholds.startupBufferTargetMS),
                        "startup_buffered_audio_ms": .int(startupBufferedAudioMS),
                    ]
                )
                await self.logRequestEvent(
                    "playback_started",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "text_complexity_class": .string(thresholds.complexityClass.rawValue),
                        "startup_buffer_target_ms": .int(thresholds.startupBufferTargetMS),
                        "startup_buffered_audio_ms": .int(startupBufferedAudioMS),
                    ]
                    .merging(self.textFeatureDetails(textFeatures), uniquingKeysWith: { _, new in new })
                    .merging(self.memoryDetails(), uniquingKeysWith: { _, new in new })
                )
            case .queueDepthLow(let queuedAudioMS):
                await self.logRequestEvent(
                    "playback_queue_depth_low",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: ["queued_audio_ms": .int(queuedAudioMS)]
                )
            case .chunkGapWarning(let gapMS, let chunkIndex):
                await self.logRequestEvent(
                    "playback_chunk_gap_warning",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "gap_ms": .int(gapMS),
                        "chunk_index": .int(chunkIndex),
                    ]
                )
            case .scheduleGapWarning(let gapMS, let bufferIndex, let queuedAudioMS):
                await self.logRequestEvent(
                    "playback_schedule_gap_warning",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "gap_ms": .int(gapMS),
                        "buffer_index": .int(bufferIndex),
                        "queued_audio_ms": .int(queuedAudioMS),
                    ]
                )
            case .starved:
                await self.logRequestEvent(
                    "playback_starved",
                    requestID: id,
                    op: op,
                    profileName: profileName
                )
            case .rebufferThrashWarning(let rebufferEventCount, let windowMS):
                await self.logRequestEvent(
                    "playback_rebuffer_thrash_warning",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "rebuffer_event_count": .int(rebufferEventCount),
                        "window_ms": .int(windowMS),
                    ]
                )
            case .rebufferStarted(let queuedAudioMS, let thresholds):
                await self.logRequestEvent(
                    "playback_rebuffer_started",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "text_complexity_class": .string(thresholds.complexityClass.rawValue),
                        "low_water_target_ms": .int(thresholds.lowWaterTargetMS),
                        "resume_buffer_target_ms": .int(thresholds.resumeBufferTargetMS),
                        "queued_audio_ms": .int(queuedAudioMS),
                    ]
                )
            case .rebufferResumed(let bufferedAudioMS, let thresholds):
                await self.logRequestEvent(
                    "playback_rebuffer_resumed",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "text_complexity_class": .string(thresholds.complexityClass.rawValue),
                        "startup_buffer_target_ms": .int(thresholds.startupBufferTargetMS),
                        "resume_buffer_target_ms": .int(thresholds.resumeBufferTargetMS),
                        "buffered_audio_ms": .int(bufferedAudioMS),
                    ]
                )
            case .bufferShapeSummary(
                let maxBoundaryDiscontinuity,
                let maxLeadingAbsAmplitude,
                let maxTrailingAbsAmplitude,
                let fadeInChunkCount
            ):
                await self.logRequestEvent(
                    "playback_buffer_shape_summary",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "max_boundary_discontinuity": .double(maxBoundaryDiscontinuity),
                        "max_leading_abs_amplitude": .double(maxLeadingAbsAmplitude),
                        "max_trailing_abs_amplitude": .double(maxTrailingAbsAmplitude),
                        "fade_in_chunk_count": .int(fadeInChunkCount),
                    ]
                )
            case .trace(let trace):
                var details = [String: LogValue]()
                if let chunkIndex = trace.chunkIndex {
                    details["chunk_index"] = .int(chunkIndex)
                }
                if let bufferIndex = trace.bufferIndex {
                    details["buffer_index"] = .int(bufferIndex)
                }
                if let sampleCount = trace.sampleCount {
                    details["sample_count"] = .int(sampleCount)
                }
                if let durationMS = trace.durationMS {
                    details["duration_ms"] = .int(durationMS)
                }
                if let queuedAudioBeforeMS = trace.queuedAudioBeforeMS {
                    details["queued_audio_before_ms"] = .int(queuedAudioBeforeMS)
                }
                if let queuedAudioAfterMS = trace.queuedAudioAfterMS {
                    details["queued_audio_after_ms"] = .int(queuedAudioAfterMS)
                }
                if let gapMS = trace.gapMS {
                    details["gap_ms"] = .int(gapMS)
                }
                if let isRebuffering = trace.isRebuffering {
                    details["is_rebuffering"] = .bool(isRebuffering)
                }
                if let fadeInApplied = trace.fadeInApplied {
                    details["fade_in_applied"] = .bool(fadeInApplied)
                }
                await self.logRequestEvent(
                    "playback_trace_\(trace.name)",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: details
                )
            }
        }
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .playbackFinished)
        var details: [String: LogValue] = [
            "text_complexity_class": .string(playbackSummary.thresholds.complexityClass.rawValue),
            "chunk_count": .int(playbackSummary.chunkCount),
            "sample_count": .int(playbackSummary.sampleCount),
            "streaming_interval": .double(PlaybackConfiguration.residentStreamingInterval),
            "startup_buffer_target_ms": .int(playbackSummary.thresholds.startupBufferTargetMS),
            "low_water_target_ms": .int(playbackSummary.thresholds.lowWaterTargetMS),
            "resume_buffer_target_ms": .int(playbackSummary.thresholds.resumeBufferTargetMS),
            "chunk_gap_warning_threshold_ms": .int(playbackSummary.thresholds.chunkGapWarningMS),
            "schedule_gap_warning_threshold_ms": .int(playbackSummary.thresholds.scheduleGapWarningMS),
            "rebuffer_event_count": .int(playbackSummary.rebufferEventCount),
            "rebuffer_total_duration_ms": .int(playbackSummary.rebufferTotalDurationMS),
            "longest_rebuffer_duration_ms": .int(playbackSummary.longestRebufferDurationMS),
            "starvation_event_count": .int(playbackSummary.starvationEventCount),
            "queue_depth_sample_count": .int(playbackSummary.queueDepthSampleCount),
            "schedule_callback_count": .int(playbackSummary.scheduleCallbackCount),
            "played_back_callback_count": .int(playbackSummary.playedBackCallbackCount),
            "fade_in_chunk_count": .int(playbackSummary.fadeInChunkCount),
        ]
        if let startupBufferedAudioMS = playbackSummary.startupBufferedAudioMS {
            details["startup_buffered_audio_ms"] = .int(startupBufferedAudioMS)
        }
        if let timeToFirstChunkMS = playbackSummary.timeToFirstChunkMS {
            details["time_to_first_chunk_ms"] = .int(timeToFirstChunkMS)
        }
        if let timeToPrerollReadyMS = playbackSummary.timeToPrerollReadyMS {
            details["time_to_preroll_ready_ms"] = .int(timeToPrerollReadyMS)
        }
        if let timeFromPrerollReadyToDrainMS = playbackSummary.timeFromPrerollReadyToDrainMS {
            details["time_from_preroll_ready_to_drain_ms"] = .int(timeFromPrerollReadyToDrainMS)
        }
        if let minQueuedAudioMS = playbackSummary.minQueuedAudioMS {
            details["min_queued_audio_ms"] = .int(minQueuedAudioMS)
        }
        if let maxQueuedAudioMS = playbackSummary.maxQueuedAudioMS {
            details["max_queued_audio_ms"] = .int(maxQueuedAudioMS)
        }
        if let avgQueuedAudioMS = playbackSummary.avgQueuedAudioMS {
            details["avg_queued_audio_ms"] = .int(avgQueuedAudioMS)
        }
        if let maxInterChunkGapMS = playbackSummary.maxInterChunkGapMS {
            details["max_inter_chunk_gap_ms"] = .int(maxInterChunkGapMS)
        }
        if let avgInterChunkGapMS = playbackSummary.avgInterChunkGapMS {
            details["avg_inter_chunk_gap_ms"] = .int(avgInterChunkGapMS)
        }
        if let maxScheduleGapMS = playbackSummary.maxScheduleGapMS {
            details["max_schedule_gap_ms"] = .int(maxScheduleGapMS)
        }
        if let avgScheduleGapMS = playbackSummary.avgScheduleGapMS {
            details["avg_schedule_gap_ms"] = .int(avgScheduleGapMS)
        }
        if let maxBoundaryDiscontinuity = playbackSummary.maxBoundaryDiscontinuity {
            details["max_boundary_discontinuity"] = .double(maxBoundaryDiscontinuity)
        }
        if let maxLeadingAbsAmplitude = playbackSummary.maxLeadingAbsAmplitude {
            details["max_leading_abs_amplitude"] = .double(maxLeadingAbsAmplitude)
        }
        if let maxTrailingAbsAmplitude = playbackSummary.maxTrailingAbsAmplitude {
            details["max_trailing_abs_amplitude"] = .double(maxTrailingAbsAmplitude)
        }
        details.merge(textFeatureDetails(textFeatures), uniquingKeysWith: { _, new in new })
        details.merge(memoryDetails(), uniquingKeysWith: { _, new in new })
        await logRequestEvent(
            "playback_finished",
            requestID: id,
            op: op,
            profileName: profileName,
            details: details
        )
    }

    private func handleCreateProfile(
        id: String,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?
    ) async throws -> StoredProfile {
        let op = WorkerRequest.createProfile(
            id: id,
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath
        ).opName
        try profileStore.validateProfileName(profileName)
        await emitProgress(id: id, stage: .loadingProfileModel)
        let modelLoadStartedAt = dependencies.now()
        let profileModel = try await dependencies.loadProfileModel()
        await logRequestEvent(
            "profile_model_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "model_repo": .string(ModelFactory.profileModelRepo),
                "duration_ms": .int(elapsedMS(since: modelLoadStartedAt)),
            ]
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .generatingProfileAudio)
        let generationStartedAt = dependencies.now()
        let audio = try await profileModel.generate(
            text: text,
            voice: voiceDescription,
            refAudio: nil,
            refText: nil,
            language: "English"
        )
        await logRequestEvent(
            "profile_audio_generated",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
            ]
        )
        try Task.checkCancellation()

        let tempDirectory = dependencies.fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        try dependencies.writeWAV(audio, profileModel.sampleRate, tempWavURL)
        let canonicalAudioData = try Data(contentsOf: tempWavURL)
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let profileWriteStartedAt = dependencies.now()
        let storedProfile = try profileStore.createProfile(
            profileName: profileName,
            modelRepo: ModelFactory.profileModelRepo,
            voiceDescription: voiceDescription,
            sourceText: text,
            sampleRate: profileModel.sampleRate,
            canonicalAudioData: canonicalAudioData
        )
        await logRequestEvent(
            "profile_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(storedProfile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: profileWriteStartedAt)),
            ]
        )

        if let outputPath {
            await emitProgress(id: id, stage: .exportingProfileAudio)
            let exportStartedAt = dependencies.now()
            try profileStore.exportCanonicalAudio(for: storedProfile, to: outputPath)
            await logRequestEvent(
                "profile_exported",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "path": .string(profileStore.resolveOutputURL(outputPath).path),
                    "duration_ms": .int(elapsedMS(since: exportStartedAt)),
                ]
            )
        }

        return storedProfile
    }

    private func textFeatureDetails(_ features: SpeechTextForensicFeatures) -> [String: LogValue] {
        [
            "original_character_count": .int(features.originalCharacterCount),
            "normalized_character_count": .int(features.normalizedCharacterCount),
            "normalized_character_delta": .int(features.normalizedCharacterDelta),
            "original_paragraph_count": .int(features.originalParagraphCount),
            "normalized_paragraph_count": .int(features.normalizedParagraphCount),
            "markdown_header_count": .int(features.markdownHeaderCount),
            "fenced_code_block_count": .int(features.fencedCodeBlockCount),
            "inline_code_span_count": .int(features.inlineCodeSpanCount),
            "markdown_link_count": .int(features.markdownLinkCount),
            "file_path_count": .int(features.filePathCount),
            "dotted_identifier_count": .int(features.dottedIdentifierCount),
            "camel_case_token_count": .int(features.camelCaseTokenCount),
            "snake_case_token_count": .int(features.snakeCaseTokenCount),
            "objc_symbol_count": .int(features.objcSymbolCount),
            "repeated_letter_run_count": .int(features.repeatedLetterRunCount),
            "punctuation_heavy_line_count": .int(features.punctuationHeavyLineCount),
            "looks_code_heavy": .bool(features.looksCodeHeavy),
        ]
    }

    private func residentModelOrThrow() throws -> AnySpeechModel {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down."
            )
        }

        switch residentState {
        case .ready(let model):
            return model
        case .warming:
            throw WorkerError(code: .modelLoading, message: "The resident \(ModelFactory.residentModelRepo) model is still loading.")
        case .failed(let error):
            throw error
        }
    }

    private func nextQueueIndex() -> Int? {
        let prioritizedIndices = queue.indices
            .filter { queue[$0].request.isPlayback }
            + queue.indices.filter { !queue[$0].request.isPlayback }

        for index in prioritizedIndices where !isBlockedByProfileCreation(queue[index]) {
            return index
        }

        return nil
    }

    private func isBlockedByProfileCreation(_ entry: QueueEntry) -> Bool {
        guard case .speakLive(_, _, let profileName) = entry.request else {
            return false
        }

        if let activeRequest,
           case .createProfile(_, let activeProfileName, _, _, _) = activeRequest.request,
           activeProfileName == profileName
        {
            return true
        }

        for queuedEntry in queue {
            if queuedEntry.token == entry.token {
                break
            }

            if case .createProfile(_, let queuedProfileName, _, _, _) = queuedEntry.request,
               queuedProfileName == profileName
            {
                return true
            }
        }

        return false
    }

    private func failQueuedRequests(with error: WorkerError) async {
        let queuedRequests = queue
        queue.removeAll()

        for entry in queuedRequests {
            await emitFailure(id: entry.request.id, error: error)
        }
    }

    private func finishActiveRequest(token: UUID, requestID: String, result: Result<WorkerSuccessPayload, WorkerError>) async {
        guard activeRequest?.token == token else { return }

        activeRequest = nil
        defer { requestAcceptedAt.removeValue(forKey: requestID) }

        switch result {
        case .success(let payload):
            await logRequestEvent(
                "request_succeeded",
                requestID: payload.id,
                op: nil,
                profileName: payload.profileName
            )
            await emitSuccess(
                id: payload.id,
                profileName: payload.profileName,
                profilePath: payload.profilePath,
                profiles: payload.profiles
            )

        case .failure(let error):
            await logError(error.message, requestID: requestID, details: ["failure_code": .string(error.code.rawValue)])
            await emitFailure(id: requestID, error: error)
        }

        guard !isShuttingDown else { return }
        try? await startNextRequestIfPossible()
    }

    private func cancellationError(for id: String) -> WorkerError {
        if isShuttingDown {
            return WorkerError(
                code: .requestCancelled,
                message: "Request '\(id)' was cancelled because the SpeakSwiftly worker is shutting down."
            )
        }

        return WorkerError(
            code: .requestCancelled,
            message: "Request '\(id)' was cancelled before it could complete."
        )
    }

    // MARK: - Emission

    private func makeQueuedEvent(for entry: QueueEntry) -> WorkerQueuedEvent? {
        let reason: WorkerQueuedReason
        switch residentState {
        case .warming:
            reason = .waitingForResidentModel
        case .failed:
            return nil
        case .ready:
            guard activeRequest != nil else { return nil }
            reason = .waitingForActiveRequest
        }

        let queuePosition = waitingQueuePosition(for: entry)
        return WorkerQueuedEvent(id: entry.request.id, reason: reason, queuePosition: queuePosition)
    }

    private func waitingQueuePosition(for entry: QueueEntry) -> Int {
        let orderedQueue = orderedWaitingQueue()

        guard let index = orderedQueue.firstIndex(of: entry) else {
            return 1
        }

        return index + 1
    }

    private func orderedWaitingQueue() -> [QueueEntry] {
        let playbackRequests = queue.filter(\.request.isPlayback)
        let nonPlaybackRequests = queue.filter { !$0.request.isPlayback }
        return playbackRequests + nonPlaybackRequests
    }

    private func emitStarted(for request: WorkerRequest) async {
        await emit(WorkerStartedEvent(id: request.id, op: request.opName))
    }

    private func emitProgress(id: String, stage: WorkerProgressStage) async {
        await emit(WorkerProgressEvent(id: id, stage: stage))
    }

    private func emitStatus(_ stage: WorkerStatusStage) async {
        await emit(WorkerStatusEvent(stage: stage))
    }

    private func emitSuccess(id: String, profileName: String?, profilePath: String?, profiles: [ProfileSummary]?) async {
        await emit(WorkerSuccessResponse(id: id, profileName: profileName, profilePath: profilePath, profiles: profiles))
    }

    private func emitFailure(id: String, error: WorkerError) async {
        await emit(WorkerFailureResponse(id: id, code: error.code, message: error.message))
    }

    private func emit<T: Encodable>(_ value: T) async {
        do {
            let data = try encoder.encode(value) + Data("\n".utf8)
            try dependencies.writeStdout(data)
        } catch {
            await logError("SpeakSwiftly could not write a JSONL event to stdout. \(error.localizedDescription)")
        }
    }

    private func logError(
        _ message: String,
        requestID: String? = nil,
        op: String? = nil,
        profileName: String? = nil,
        details: [String: LogValue]? = nil
    ) async {
        var mergedDetails = details ?? [:]
        mergedDetails["message"] = .string(message)
        await logEvent(
            "worker_error",
            level: .error,
            requestID: requestID,
            op: op,
            profileName: profileName,
            elapsedMS: requestID.flatMap(elapsedMS(for:)),
            details: mergedDetails
        )
    }

    private func logRequestEvent(
        _ event: String,
        requestID: String,
        op: String?,
        profileName: String? = nil,
        queueDepth: Int? = nil,
        details: [String: LogValue]? = nil
    ) async {
        await logEvent(
            event,
            requestID: requestID,
            op: op,
            profileName: profileName,
            queueDepth: queueDepth,
            elapsedMS: elapsedMS(for: requestID),
            details: details
        )
    }

    private func memoryDetails() -> [String: LogValue] {
        guard let snapshot = dependencies.readRuntimeMemory() else {
            return [:]
        }

        var details = [String: LogValue]()
        if let processResidentBytes = snapshot.processResidentBytes {
            details["process_resident_bytes"] = .int(processResidentBytes)
        }
        if let processPhysFootprintBytes = snapshot.processPhysFootprintBytes {
            details["process_phys_footprint_bytes"] = .int(processPhysFootprintBytes)
        }
        if let mlxActiveMemoryBytes = snapshot.mlxActiveMemoryBytes {
            details["mlx_active_memory_bytes"] = .int(mlxActiveMemoryBytes)
        }
        if let mlxCacheMemoryBytes = snapshot.mlxCacheMemoryBytes {
            details["mlx_cache_memory_bytes"] = .int(mlxCacheMemoryBytes)
        }
        if let mlxPeakMemoryBytes = snapshot.mlxPeakMemoryBytes {
            details["mlx_peak_memory_bytes"] = .int(mlxPeakMemoryBytes)
        }
        if let mlxCacheLimitBytes = snapshot.mlxCacheLimitBytes {
            details["mlx_cache_limit_bytes"] = .int(mlxCacheLimitBytes)
        }
        if let mlxMemoryLimitBytes = snapshot.mlxMemoryLimitBytes {
            details["mlx_memory_limit_bytes"] = .int(mlxMemoryLimitBytes)
        }
        return details
    }

    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        requestID: String? = nil,
        op: String? = nil,
        profileName: String? = nil,
        queueDepth: Int? = nil,
        elapsedMS: Int? = nil,
        details: [String: LogValue]? = nil
    ) async {
        let logEvent = LogEvent(
            event: event,
            level: level,
            ts: logTimestampFormatter.string(from: dependencies.now()),
            requestID: requestID,
            op: op,
            profileName: profileName,
            queueDepth: queueDepth,
            elapsedMS: elapsedMS,
            details: details
        )

        do {
            let data = try logEncoder.encode(logEvent)
            dependencies.writeStderr(String(decoding: data, as: UTF8.self))
        } catch {
            dependencies.writeStderr(
                #"{"event":"worker_error","level":"error","ts":"\#(logTimestampFormatter.string(from: dependencies.now()))","details":{"message":"SpeakSwiftly could not encode a stderr log event.","error":"\#(error.localizedDescription)"}}"#
            )
        }
    }

    private func elapsedMS(for requestID: String) -> Int? {
        guard let startedAt = requestAcceptedAt[requestID] else { return nil }
        return elapsedMS(since: startedAt)
    }

    private func elapsedMS(since startedAt: Date) -> Int {
        Int((dependencies.now().timeIntervalSince(startedAt) * 1_000).rounded())
    }

    private func bestEffortID(from line: String) -> String {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.isEmpty
        else {
            return "unknown"
        }

        return id
    }
}
