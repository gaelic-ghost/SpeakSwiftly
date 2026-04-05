import Foundation
import TextForSpeech

// MARK: - Worker Runtime

public extension SpeakSwiftly {
    actor Runtime {
    private enum Environment {
        static let profileRootOverride = "SPEAKSWIFTLY_PROFILE_ROOT"
    }

    private enum TextProfilePersistence {
        static func url(in rootURL: URL) -> URL {
            rootURL.appending(path: ProfileStore.textProfilesFileName)
        }
    }

    enum PlaybackConfiguration {
        // Shorter chunk cadence gives playback a second chunk in reserve before
        // the first one drains, which reduces audible shudder from one-chunk starts.
        static let residentStreamingInterval = 0.18
    }

    enum ResidentState: Sendable {
        case warming
        case ready(AnySpeechModel)
        case failed(WorkerError)
    }

    struct ActiveRequest: Sendable {
        let token: UUID
        let request: WorkerRequest
        let task: Task<Void, Never>
    }

    struct WorkerSuccessPayload: Sendable {
        let id: String
        let profileName: String?
        let profilePath: String?
        let profiles: [ProfileSummary]?
        let activeRequest: ActiveWorkerRequestSummary?
        let queue: [QueuedWorkerRequestSummary]?
        let playbackState: PlaybackStateSummary?
        let clearedCount: Int?
        let cancelledRequestID: String?

        init(
            id: String,
            profileName: String? = nil,
            profilePath: String? = nil,
            profiles: [ProfileSummary]? = nil,
            activeRequest: ActiveWorkerRequestSummary? = nil,
            queue: [QueuedWorkerRequestSummary]? = nil,
            playbackState: PlaybackStateSummary? = nil,
            clearedCount: Int? = nil,
            cancelledRequestID: String? = nil
        ) {
            self.id = id
            self.profileName = profileName
            self.profilePath = profilePath
            self.profiles = profiles
            self.activeRequest = activeRequest
            self.queue = queue
            self.playbackState = playbackState
            self.clearedCount = clearedCount
            self.cancelledRequestID = cancelledRequestID
        }
    }

    enum GenerationCompletionDisposition: Sendable {
        case requestCompleted(Result<WorkerSuccessPayload, WorkerError>)
        case requestStillPendingPlayback(String)
    }

    struct OutgoingWorkerRequest: Encodable {
        let id: String
        let op: String
        let text: String?
        let profileName: String?
        let textProfileName: String?
        let cwd: String?
        let repoRoot: String?
        let textFormat: TextForSpeech.Format?
        let requestID: String?
        let voiceDescription: String?
        let outputPath: String?
        let referenceAudioPath: String?
        let transcript: String?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case text
            case profileName = "profile_name"
            case textProfileName = "text_profile_name"
            case cwd
            case repoRoot = "repo_root"
            case textFormat = "text_format"
            case requestID = "request_id"
            case voiceDescription = "voice_description"
            case outputPath = "output_path"
            case referenceAudioPath = "reference_audio_path"
            case transcript
        }
    }

    enum LogLevel: String, Encodable {
        case info
        case error
    }

    enum LogValue: Encodable, Sendable {
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

    struct LogEvent: Encodable {
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

    let dependencies: WorkerDependencies
    let encoder = JSONEncoder()
    let logEncoder = JSONEncoder()
    let profileStore: ProfileStore
    let textRuntime: TextForSpeechRuntime
    let playbackController: PlaybackController
    let generationController = GenerationController()
    let logTimestampFormatter = ISO8601DateFormatter()
    private let maxAcceptedSpeechJobs = 8

    var residentState: ResidentState = .warming
    var isShuttingDown = false
    var preloadTask: Task<Void, Never>?
    var requestAcceptedAt = [String: Date]()
    var statusContinuations = [UUID: AsyncStream<WorkerStatusEvent>.Continuation]()
    var requestContinuations = [String: AsyncThrowingStream<WorkerRequestStreamEvent, any Swift.Error>.Continuation]()
    var activeGeneration: ActiveRequest?
    // MARK: - Lifecycle

    init(
        dependencies: WorkerDependencies,
        profileStore: ProfileStore,
        textRuntime: TextForSpeechRuntime,
        playbackController: PlaybackController
    ) {
        self.dependencies = dependencies
        self.profileStore = profileStore
        self.textRuntime = textRuntime
        self.playbackController = playbackController
        encoder.outputFormatting = [.sortedKeys]
        logEncoder.outputFormatting = [.sortedKeys]
    }

    public static func live() async -> Runtime {
        let dependencies = WorkerDependencies.live()
        let environment = ProcessInfo.processInfo.environment
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                overridePath: environment[Environment.profileRootOverride]
            ),
            fileManager: dependencies.fileManager
        )
        let textRuntime = TextForSpeechRuntime(
            persistenceURL: TextProfilePersistence.url(in: profileStore.rootURL)
        )
        do {
            try textRuntime.load()
        } catch {
            let message = "SpeakSwiftly could not load persisted text profiles from '\(textRuntime.persistenceURL?.path ?? "unknown path")'. \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        let playbackController = PlaybackController(driver: await dependencies.makePlaybackController())

        let runtime = Runtime(
            dependencies: dependencies,
            profileStore: profileStore,
            textRuntime: textRuntime,
            playbackController: playbackController
        )
        await runtime.installPlaybackHooks()
        return runtime
    }

    func installPlaybackHooks() async {
        await playbackController.bind(
            PlaybackHooks(
                handleEvent: { event, job in
                    await self.handlePlaybackEvent(event, for: job)
                },
                logFinished: { job, playbackSummary, sampleRate in
                    await self.emitProgress(id: job.requestID, stage: .playbackFinished)
                    await self.logPlaybackFinished(for: job, playbackSummary: playbackSummary, sampleRate: sampleRate)
                },
                completeJob: { job, result in
                    await self.completePlaybackJob(job, result: result)
                }
            )
        )
    }

    public func statusEvents() -> AsyncStream<StatusEvent> {
        let subscriptionID = UUID()
        return AsyncStream { continuation in
            statusContinuations[subscriptionID] = continuation
            if let status = currentStatusSnapshot() {
                continuation.yield(status)
            }
            continuation.onTermination = { _ in
                Task {
                    await self.removeStatusContinuation(subscriptionID)
                }
            }
        }
    }

    func submit(_ request: WorkerRequest) async -> WorkerRequestHandle {
        let handle = makeRequestHandle(for: request)
        await submitRequest(request)
        return handle
    }

    public func start() {
        guard preloadTask == nil else { return }

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
                try await startNextGenerationIfPossible()
                await playbackController.startNextIfPossible()
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

    public func accept(line: String) async {
        let request: WorkerRequest

        do {
            request = try WorkerRequest.decode(from: line)
        } catch let workerError as WorkerError {
            let id = bestEffortID(from: line)
            failRequestStream(for: id, error: workerError)
            requestAcceptedAt.removeValue(forKey: id)
            await emitFailure(id: id, error: workerError)
            return
        } catch {
            let id = bestEffortID(from: line)
            let workerError = WorkerError(
                code: .internalError,
                message: "The request could not be decoded due to an unexpected internal error. \(error.localizedDescription)"
            )
            failRequestStream(for: id, error: workerError)
            requestAcceptedAt.removeValue(forKey: id)
            await emitFailure(
                id: id,
                error: workerError
            )
            return
        }

        if isShuttingDown {
            let workerError = WorkerError(
                code: .workerShuttingDown,
                message: "Request '\(request.id)' was rejected because the SpeakSwiftly worker is shutting down."
            )
            failRequestStream(for: request.id, error: workerError)
            requestAcceptedAt.removeValue(forKey: request.id)
            await emitFailure(
                id: request.id,
                error: workerError
            )
            return
        }

        if request.isImmediateControlOperation {
            requestAcceptedAt[request.id] = dependencies.now()
            await logRequestEvent(
                "request_accepted",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: await generationQueueDepth()
            )
            await emitStarted(for: request)
            yieldRequestEvent(.started(WorkerStartedEvent(id: request.id, op: request.opName)), for: request.id)
            await logRequestEvent(
                "request_started",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: await generationQueueDepth()
            )
            Task {
                await self.processImmediateControlRequest(request)
            }
            return
        }

        if case .failed(let error) = residentState {
            failRequestStream(for: request.id, error: error)
            requestAcceptedAt.removeValue(forKey: request.id)
            await emitFailure(id: request.id, error: error)
            return
        }

        if request.isSpeechRequest, await playbackController.jobCount() >= maxAcceptedSpeechJobs {
            let workerError = WorkerError(
                code: .invalidRequest,
                message: "Request '\(request.id)' was rejected because the live speech queue is already holding \(maxAcceptedSpeechJobs) accepted jobs. Wait for playback to drain or clear queued work before adding more."
            )
            failRequestStream(for: request.id, error: workerError)
            requestAcceptedAt.removeValue(forKey: request.id)
            await emitFailure(id: request.id, error: workerError)
            return
        }

        let job = await generationController.enqueue(request)
        requestAcceptedAt[request.id] = dependencies.now()
        await logRequestEvent(
            "request_accepted",
            requestID: request.id,
            op: request.opName,
            profileName: request.profileName,
            queueDepth: await generationQueueDepth()
        )
        if request.isSpeechRequest {
            let speechJob = makeSpeechJobState(for: request)
            await playbackController.enqueue(speechJob)
        }
        if let queuedEvent = await makeQueuedEvent(for: job) {
            await emit(queuedEvent)
            yieldRequestEvent(.queued(queuedEvent), for: request.id)
            await logRequestEvent(
                "request_queued",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: await generationQueueDepth()
            )
        }
        if request.acknowledgesEnqueueImmediately {
            let acknowledgement = WorkerSuccessResponse(id: request.id)
            yieldRequestEvent(.acknowledged(acknowledgement), for: request.id)
            await logRequestEvent(
                "request_enqueue_acknowledged",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: await generationQueueDepth()
            )
            await emit(acknowledgement)
        }
        try? await startNextGenerationIfPossible()
        await playbackController.startNextIfPossible()
    }

    // MARK: - Processing

    func startNextGenerationIfPossible() async throws {
        guard !isShuttingDown else { return }

        switch residentState {
        case .warming:
            return
        case .failed(let error):
            await failQueuedRequests(with: error)
            return
        case .ready:
            break
        }

        guard let job = await generationController.beginNextIfPossible(residentReady: true) else { return }

        await emitStarted(for: job.request)
        yieldRequestEvent(.started(WorkerStartedEvent(id: job.request.id, op: job.request.opName)), for: job.request.id)
        await logRequestEvent(
            "request_started",
            requestID: job.request.id,
            op: job.request.opName,
            profileName: job.request.profileName,
            queueDepth: await generationQueueDepth()
        )

        let task = Task {
            await self.processGeneration(job.request, token: job.token)
        }
        activeGeneration = ActiveRequest(token: job.token, request: job.request, task: task)
        if case .queueSpeech(let id, _, _, _, _, _) = job.request {
            await playbackController.setGenerationTask(task, for: id)
        }
    }

    private func processGeneration(_ request: WorkerRequest, token: UUID) async {
        let disposition: GenerationCompletionDisposition

        do {
            switch request {
            case .queueSpeech(let id, let text, let profileName, _, .live, _):
                try await handleQueueSpeechLiveGeneration(id: id, op: request.opName, text: text, profileName: profileName)
                disposition = .requestStillPendingPlayback(id)

            case .createProfile(let id, let profileName, let text, let voiceDescription, let outputPath):
                let storedProfile = try await handleCreateProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath
                )
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        profileName: storedProfile.manifest.profileName,
                        profilePath: storedProfile.directoryURL.path
                    )
                ))

            case .createClone(let id, let profileName, let referenceAudioPath, let transcript):
                let storedProfile = try await handleCreateClone(
                    id: id,
                    profileName: profileName,
                    referenceAudioPath: referenceAudioPath,
                    transcript: transcript
                )
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        profileName: storedProfile.manifest.profileName,
                        profilePath: storedProfile.directoryURL.path
                    )
                ))

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
                disposition = .requestCompleted(.success(WorkerSuccessPayload(id: id, profiles: profiles)))

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
                disposition = .requestCompleted(.success(WorkerSuccessPayload(id: id, profileName: profileName)))

            case .listQueue, .playback, .clearQueue, .cancelRequest:
                disposition = .requestCompleted(.failure(
                    WorkerError(
                        code: .internalError,
                        message: "Control request '\(request.id)' was routed through the serialized work queue unexpectedly. This indicates a runtime bug in SpeakSwiftly."
                    )
                ))
            }
        } catch is CancellationError {
            disposition = .requestCompleted(.failure(cancellationError(for: request.id)))
        } catch let workerError as WorkerError {
            disposition = .requestCompleted(.failure(workerError))
        } catch {
            disposition = .requestCompleted(.failure(WorkerError(
                    code: .internalError,
                    message: "Request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)"
                )))
        }

        await finishActiveGeneration(token: token, request: request, disposition: disposition)
    }

    private func processImmediateControlRequest(_ request: WorkerRequest) async {
        let result: Result<WorkerSuccessPayload, WorkerError>

        do {
            switch request {
            case .listQueue(let id, let queueType):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        activeRequest: await queueSummaryActiveRequest(for: queueType),
                        queue: await queuedRequestSummaries(for: queueType)
                    )
                )

            case .playback(let id, let action):
                _ = await playbackController.handle(action)
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        playbackState: await playbackController.stateSnapshot()
                    )
                )

            case .clearQueue(let id):
                let clearedCount = await clearQueuedRequests(
                    cancelledByRequestID: id,
                    reason: "queued work was cleared from the SpeakSwiftly queue"
                )
                result = .success(WorkerSuccessPayload(id: id, clearedCount: clearedCount))

            case .cancelRequest(let id, let targetRequestID):
                let cancelledRequestID = try await cancelRequestNow(
                    targetRequestID,
                    cancelledByRequestID: id
                )
                result = .success(WorkerSuccessPayload(id: id, cancelledRequestID: cancelledRequestID))

            case .queueSpeech,
                 .createProfile,
                 .createClone,
                 .listProfiles,
                 .removeProfile:
                result = .failure(
                    WorkerError(
                        code: .internalError,
                        message: "Non-control request '\(request.id)' was routed through the immediate control path unexpectedly. This indicates a runtime bug in SpeakSwiftly."
                    )
                )
            }
        } catch is CancellationError {
            result = .failure(cancellationError(for: request.id))
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .internalError,
                    message: "Control request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)"
                )
            )
        }

        await finishImmediateRequest(request: request, result: result)
    }

    private func handleQueueSpeechLiveGeneration(id: String, op: String, text: String, profileName: String) async throws {
        let residentModel = try residentModelOrThrow()
        guard let speechJob = await playbackController.job(for: id) else {
            throw WorkerError(
                code: .internalError,
                message: "Request '\(id)' started generation without a matching live speech job state. This indicates a SpeakSwiftly runtime bug."
            )
        }
        speechJob.sampleRate = Double(residentModel.sampleRate)

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
            text: speechJob.normalizedText,
            voice: nil,
            refAudio: refAudio,
            refText: profile.manifest.sourceText,
            language: "English",
            generationParameters: GenerationPolicy.residentParameters(for: speechJob.normalizedText),
            streamingInterval: PlaybackConfiguration.residentStreamingInterval
        )

        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                speechJob.continuation.yield(chunk)
            }
            speechJob.continuation.finish()
        } catch {
            speechJob.continuation.finish(throwing: error)
            if let workerError = error as? WorkerError {
                throw workerError
            }
            if error is CancellationError {
                throw CancellationError()
            }
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Live speech generation failed while streaming audio for request '\(id)'. \(error.localizedDescription)"
            )
        }
    }

    func textFeatureDetails(_ features: SpeechTextForensicFeatures) -> [String: LogValue] {
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
            "url_count": .int(features.urlCount),
            "file_path_count": .int(features.filePathCount),
            "dotted_identifier_count": .int(features.dottedIdentifierCount),
            "camel_case_token_count": .int(features.camelCaseTokenCount),
            "snake_case_token_count": .int(features.snakeCaseTokenCount),
            "objc_symbol_count": .int(features.objcSymbolCount),
            "repeated_letter_run_count": .int(features.repeatedLetterRunCount),
        ]
    }

    func textSectionDetails(_ section: SpeechTextForensicSection) -> [String: LogValue] {
        [
            "section_index": .int(section.index),
            "section_title": .string(section.title),
            "section_kind": .string(section.kind.rawValue),
            "original_character_count": .int(section.originalCharacterCount),
            "normalized_character_count": .int(section.normalizedCharacterCount),
            "normalized_character_share": .double(section.normalizedCharacterShare),
        ]
    }

    func textSectionWindowDetails(_ window: SpeechTextForensicSectionWindow) -> [String: LogValue] {
        textSectionDetails(window.section).merging(
            [
                "estimated_start_ms": .int(window.estimatedStartMS),
                "estimated_end_ms": .int(window.estimatedEndMS),
                "estimated_duration_ms": .int(window.estimatedDurationMS),
                "estimated_start_chunk": .int(window.estimatedStartChunk),
                "estimated_end_chunk": .int(window.estimatedEndChunk),
            ],
            uniquingKeysWith: { _, new in new }
        )
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

    func failQueuedRequests(with error: WorkerError) async {
        let queuedJobs = await generationController.clearQueued()

        for job in queuedJobs {
            if job.request.isSpeechRequest {
                _ = await playbackController.discard(requestID: job.request.id)
            }
            failRequestStream(for: job.request.id, error: error)
            requestAcceptedAt.removeValue(forKey: job.request.id)
            await emitFailure(id: job.request.id, error: error)
        }
    }

    private func finishActiveGeneration(token: UUID, request: WorkerRequest, disposition: GenerationCompletionDisposition) async {
        guard activeGeneration?.token == token else { return }

        activeGeneration = nil
        await generationController.finishActive(token: token)
        defer { requestAcceptedAt.removeValue(forKey: request.id) }
        switch disposition {
        case .requestCompleted(let result):
            await completeRequest(request: request, result: result)
        case .requestStillPendingPlayback:
            break
        }

        guard !isShuttingDown else { return }
        try? await startNextGenerationIfPossible()
        await playbackController.startNextIfPossible()
    }

    private func finishImmediateRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        defer { requestAcceptedAt.removeValue(forKey: request.id) }
        await completeRequest(request: request, result: result)
    }

    private func makeSpeechJobState(for request: WorkerRequest) -> PlaybackJob {
        let requestID = request.id
        let op = request.opName
        let text = switch request {
        case .queueSpeech(_, let text, _, _, _, _):
            text
        default:
            ""
        }
        let profileName = request.profileName ?? "unknown-profile"
        let textProfileName = request.textProfileName
        let textContext = request.textContext
        let textProfile = textRuntime.snapshot(named: textProfileName)
        let normalizedText = TextForSpeech.normalize(
            text,
            context: textContext,
            profile: textProfile
        )
        let textFeatures = TextForSpeech.forensicFeatures(originalText: text, normalizedText: normalizedText)
        let textSections = TextForSpeech.sections(originalText: text)
        var continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation?
        let stream = AsyncThrowingStream<[Float], any Swift.Error> { continuation = $0 }

        return PlaybackJob(
            requestID: requestID,
            op: op,
            text: text,
            normalizedText: normalizedText,
            profileName: profileName,
            textProfileName: textProfileName,
            textContext: textContext,
            textFeatures: textFeatures,
            textSections: textSections,
            stream: stream,
            continuation: continuation!
        )
    }

    }
}
