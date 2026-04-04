import Foundation
import TextForSpeechCore

// MARK: - Worker Runtime

public actor WorkerRuntime {
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

    private struct WorkerSuccessPayload: Sendable {
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

    private enum GenerationCompletionDisposition: Sendable {
        case requestCompleted(Result<WorkerSuccessPayload, WorkerError>)
        case requestStillPendingPlayback(String)
    }

    private final class SpeechJobState: @unchecked Sendable {
        let requestID: String
        let op: String
        let text: String
        let normalizedText: String
        let profileName: String
        let normalizationContext: SpeechNormalizationContext?
        let textFeatures: SpeechTextForensicFeatures
        let textSections: [SpeechTextForensicSection]
        let stream: AsyncThrowingStream<[Float], Error>
        let continuation: AsyncThrowingStream<[Float], Error>.Continuation
        var sampleRate: Double?
        var generationTask: Task<Void, Never>?
        var playbackTask: Task<Void, Never>?

        init(
            requestID: String,
            op: String,
            text: String,
            normalizedText: String,
            profileName: String,
            normalizationContext: SpeechNormalizationContext?,
            textFeatures: SpeechTextForensicFeatures,
            textSections: [SpeechTextForensicSection],
            stream: AsyncThrowingStream<[Float], Error>,
            continuation: AsyncThrowingStream<[Float], Error>.Continuation
        ) {
            self.requestID = requestID
            self.op = op
            self.text = text
            self.normalizedText = normalizedText
            self.profileName = profileName
            self.normalizationContext = normalizationContext
            self.textFeatures = textFeatures
            self.textSections = textSections
            self.stream = stream
            self.continuation = continuation
        }
    }

    private struct ActivePlayback: Sendable {
        let requestID: String
        let task: Task<Void, Never>
    }

    private struct OutgoingWorkerRequest: Encodable {
        let id: String
        let op: String
        let text: String?
        let profileName: String?
        let cwd: String?
        let repoRoot: String?
        let requestID: String?
        let voiceDescription: String?
        let outputPath: String?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case text
            case profileName = "profile_name"
            case cwd
            case repoRoot = "repo_root"
            case requestID = "request_id"
            case voiceDescription = "voice_description"
            case outputPath = "output_path"
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
    private let generationController = GenerationController()
    private let logTimestampFormatter = ISO8601DateFormatter()
    private let maxAcceptedSpeechJobs = 8

    private var residentState: ResidentState = .warming
    private var isShuttingDown = false
    private var preloadTask: Task<Void, Never>?
    private var requestAcceptedAt = [String: Date]()
    private var statusContinuations = [UUID: AsyncStream<WorkerStatusEvent>.Continuation]()
    private var requestContinuations = [String: AsyncThrowingStream<WorkerRequestStreamEvent, Error>.Continuation]()
    private var activeGeneration: ActiveRequest?
    private var activePlayback: ActivePlayback?
    private var speechJobs = [String: SpeechJobState]()
    private var playbackQueue = [String]()

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

    public static func live() async -> WorkerRuntime {
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

    public func statusEvents() -> AsyncStream<WorkerStatusEvent> {
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
                await startNextPlaybackIfPossible()
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

        if request.isSpeechRequest, speechJobs.count >= maxAcceptedSpeechJobs {
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
            speechJobs[request.id] = speechJob
            playbackQueue.append(request.id)
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
        await startNextPlaybackIfPossible()
    }

    public func speak(
        text: String,
        with profileName: String,
        as job: SpeechJobType,
        context normalizationContext: SpeechNormalizationContext? = nil,
        id: String = UUID().uuidString
    ) async -> WorkerRequestHandle {
        await submit(
            .queueSpeech(
                id: id,
                text: text,
                profileName: profileName,
                jobType: job,
                normalizationContext: normalizationContext
            )
        )
    }

    public func createProfile(
        named profileName: String,
        from text: String,
        voice voiceDescription: String,
        outputPath: String? = nil,
        id: String = UUID().uuidString
    ) async -> WorkerRequestHandle {
        await submit(
            .createProfile(
                id: id,
                profileName: profileName,
                text: text,
                voiceDescription: voiceDescription,
                outputPath: outputPath
            )
        )
    }

    public func profiles(id: String = UUID().uuidString) async -> WorkerRequestHandle {
        await submit(.listProfiles(id: id))
    }

    public func removeProfile(
        named profileName: String,
        id: String = UUID().uuidString
    ) async -> WorkerRequestHandle {
        await submit(.removeProfile(id: id, profileName: profileName))
    }

    public func queue(
        _ queueType: WorkerQueueType,
        id requestID: String = UUID().uuidString
    ) async -> WorkerRequestHandle {
        await submit(.listQueue(id: requestID, queueType: queueType))
    }

    public func playback(_ action: PlaybackAction, id requestID: String = UUID().uuidString) async -> WorkerRequestHandle {
        await submit(.playback(id: requestID, action: action))
    }

    public func clearQueue(id requestID: String = UUID().uuidString) async -> WorkerRequestHandle {
        await submit(.clearQueue(id: requestID))
    }

    public func cancelRequest(
        _ id: String,
        requestID: String = UUID().uuidString
    ) async -> WorkerRequestHandle {
        await submit(.cancelRequest(id: requestID, requestID: id))
    }

    public func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down."
        )

        if let activeGeneration {
            self.activeGeneration = nil
            activeGeneration.task.cancel()
            failRequestStream(for: activeGeneration.request.id, error: cancellationError)
            requestAcceptedAt.removeValue(forKey: activeGeneration.request.id)
            await emitFailure(id: activeGeneration.request.id, error: cancellationError)
        }

        if let activePlayback {
            self.activePlayback = nil
            activePlayback.task.cancel()
        }

        await failQueuedRequests(with: cancellationError)
        await failWaitingPlaybackRequests(with: cancellationError)
        await playbackController.stop()
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(await generationQueueDepth())])
    }

    // MARK: - Processing

    private func startNextGenerationIfPossible() async throws {
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
        if case .queueSpeech(let id, _, _, _, _) = job.request {
            speechJobs[id]?.generationTask = task
        }
    }

    private func processGeneration(_ request: WorkerRequest, token: UUID) async {
        let disposition: GenerationCompletionDisposition

        do {
            switch request {
            case .queueSpeech(let id, let text, let profileName, .live, _):
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
                let playbackState = await handlePlaybackControl(action)
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        playbackState: PlaybackStateSummary(
                            state: playbackState,
                            activeRequest: playbackActiveRequestSummary()
                        )
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
        guard let speechJob = speechJobs[id] else {
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
            language: "English",
            generationParameters: GenerationPolicy.profileParameters(for: text)
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
            "url_count": .int(features.urlCount),
            "file_path_count": .int(features.filePathCount),
            "dotted_identifier_count": .int(features.dottedIdentifierCount),
            "camel_case_token_count": .int(features.camelCaseTokenCount),
            "snake_case_token_count": .int(features.snakeCaseTokenCount),
            "objc_symbol_count": .int(features.objcSymbolCount),
            "repeated_letter_run_count": .int(features.repeatedLetterRunCount),
        ]
    }

    private func textSectionDetails(_ section: SpeechTextForensicSection) -> [String: LogValue] {
        [
            "section_index": .int(section.index),
            "section_title": .string(section.title),
            "section_kind": .string(section.kind.rawValue),
            "original_character_count": .int(section.originalCharacterCount),
            "normalized_character_count": .int(section.normalizedCharacterCount),
            "normalized_character_share": .double(section.normalizedCharacterShare),
        ]
    }

    private func textSectionWindowDetails(_ window: SpeechTextForensicSectionWindow) -> [String: LogValue] {
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

    private func failQueuedRequests(with error: WorkerError) async {
        let queuedJobs = await generationController.clearQueued()

        for job in queuedJobs {
            if job.request.isSpeechRequest {
                _ = removeSpeechJob(requestID: job.request.id)
                removePlaybackJob(requestID: job.request.id)
            }
            failRequestStream(for: job.request.id, error: error)
            requestAcceptedAt.removeValue(forKey: job.request.id)
            await emitFailure(id: job.request.id, error: error)
        }
    }

    private func clearQueuedRequests(cancelledByRequestID: String, reason: String) async -> Int {
        let queuedJobs = await generationController.clearQueued()
        let protectedRequestIDs = Set([activeGeneration?.request.id, activePlayback?.requestID].compactMap { $0 })
        let waitingPlaybackRequestIDs = playbackQueue.filter { !protectedRequestIDs.contains($0) }

        let cancellation = WorkerError(
            code: .requestCancelled,
            message: "Request '\(cancelledByRequestID)' cancelled this work because \(reason)."
        )

        for job in queuedJobs {
            if job.request.isSpeechRequest {
                _ = removeSpeechJob(requestID: job.request.id)
                removePlaybackJob(requestID: job.request.id)
            }
            failRequestStream(for: job.request.id, error: cancellation)
            requestAcceptedAt.removeValue(forKey: job.request.id)
            await logError(
                cancellation.message,
                requestID: job.request.id,
                details: ["failure_code": .string(cancellation.code.rawValue)]
            )
            await emitFailure(id: job.request.id, error: cancellation)
        }

        for requestID in waitingPlaybackRequestIDs {
            guard let speechJob = removeSpeechJob(requestID: requestID) else { continue }
            speechJob.generationTask?.cancel()
            speechJob.playbackTask?.cancel()
            speechJob.continuation.finish(throwing: cancellation)
            removePlaybackJob(requestID: requestID)
            requestAcceptedAt.removeValue(forKey: requestID)
            let request = WorkerRequest.queueSpeech(
                id: requestID,
                text: speechJob.text,
                profileName: speechJob.profileName,
                jobType: .live,
                normalizationContext: speechJob.normalizationContext
            )
            await logError(
                cancellation.message,
                requestID: requestID,
                details: ["failure_code": .string(cancellation.code.rawValue)]
            )
            await completeRequest(request: request, result: .failure(cancellation))
        }

        return queuedJobs.count + waitingPlaybackRequestIDs.count
    }

    private func failWaitingPlaybackRequests(with error: WorkerError) async {
        let protectedRequestIDs = Set([activeGeneration?.request.id, activePlayback?.requestID].compactMap { $0 })
        let waitingPlaybackRequestIDs = playbackQueue.filter { !protectedRequestIDs.contains($0) }

        for requestID in waitingPlaybackRequestIDs {
            guard let speechJob = removeSpeechJob(requestID: requestID) else { continue }
            speechJob.generationTask?.cancel()
            speechJob.playbackTask?.cancel()
            speechJob.continuation.finish(throwing: error)
            removePlaybackJob(requestID: requestID)
            requestAcceptedAt.removeValue(forKey: requestID)
            let request = WorkerRequest.queueSpeech(
                id: requestID,
                text: speechJob.text,
                profileName: speechJob.profileName,
                jobType: .live,
                normalizationContext: speechJob.normalizationContext
            )
            await completeRequest(request: request, result: .failure(error))
        }
    }

    private func cancelRequestNow(_ targetRequestID: String, cancelledByRequestID: String) async throws -> String {
        let cancellation = WorkerError(
            code: .requestCancelled,
            message: "Request '\(targetRequestID)' was cancelled by control request '\(cancelledByRequestID)'."
        )

        let cancelledGenerationTarget = await generationController.cancel(requestID: targetRequestID)
        if let cancelledGenerationTarget {
            switch cancelledGenerationTarget {
            case .active:
                activeGeneration?.task.cancel()
                activeGeneration = nil
            case .queued:
                break
            }
        }

        if let speechJob = speechJobs[targetRequestID] {
            speechJob.generationTask?.cancel()
            speechJob.playbackTask?.cancel()
            speechJob.continuation.finish(throwing: cancellation)
            if activePlayback?.requestID == targetRequestID {
                activePlayback = nil
                await playbackController.stop()
            } else {
                removePlaybackJob(requestID: targetRequestID)
            }
            await completeSpeechRequestIfNeeded(id: targetRequestID, result: .failure(cancellation))
            try? await startNextGenerationIfPossible()
            await startNextPlaybackIfPossible()
            return targetRequestID
        }

        switch cancelledGenerationTarget {
        case .active:
            activeGeneration?.task.cancel()
            activeGeneration = nil
            requestAcceptedAt.removeValue(forKey: targetRequestID)
            failRequestStream(for: targetRequestID, error: cancellation)
            await logError(
                cancellation.message,
                requestID: targetRequestID,
                details: ["failure_code": .string(cancellation.code.rawValue)]
            )
            await emitFailure(id: targetRequestID, error: cancellation)
            try? await startNextGenerationIfPossible()
            return targetRequestID
        case .queued(let job):
            requestAcceptedAt.removeValue(forKey: targetRequestID)
            failRequestStream(for: targetRequestID, error: cancellation)
            await logError(
                cancellation.message,
                requestID: targetRequestID,
                details: ["failure_code": .string(cancellation.code.rawValue)]
            )
            await emitFailure(id: job.request.id, error: cancellation)
            return targetRequestID
        case nil:
            break
        }

        throw WorkerError(
            code: .requestNotFound,
            message: "Control request '\(cancelledByRequestID)' could not find request '\(targetRequestID)' in the active or queued SpeakSwiftly work set."
        )
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
        await startNextPlaybackIfPossible()
    }

    private func finishImmediateRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        defer { requestAcceptedAt.removeValue(forKey: request.id) }
        await completeRequest(request: request, result: result)
    }

    private func completeRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        switch result {
        case .success(let payload):
            await logRequestEvent(
                "request_succeeded",
                requestID: payload.id,
                op: nil,
                profileName: payload.profileName
            )
            let success = WorkerSuccessResponse(
                id: payload.id,
                profileName: payload.profileName,
                profilePath: payload.profilePath,
                profiles: payload.profiles,
                activeRequest: payload.activeRequest,
                queue: payload.queue,
                playbackState: payload.playbackState,
                clearedCount: payload.clearedCount,
                cancelledRequestID: payload.cancelledRequestID
            )
            yieldRequestEvent(.completed(success), for: request.id)
            finishRequestStream(for: request.id)
            if !request.acknowledgesEnqueueImmediately {
                await emit(success)
            }

        case .failure(let error):
            failRequestStream(for: request.id, error: error)
            await logError(error.message, requestID: request.id, details: ["failure_code": .string(error.code.rawValue)])
            await emitFailure(id: request.id, error: error)
        }
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

    private func makeQueuedEvent(for job: GenerationController.Job) async -> WorkerQueuedEvent? {
        let reason: WorkerQueuedReason
        switch residentState {
        case .warming:
            reason = .waitingForResidentModel
        case .failed:
            return nil
        case .ready:
            guard await generationController.activeJob() != nil else { return nil }
            reason = .waitingForActiveRequest
        }

        let queuePosition = await generationController.waitingPosition(
            for: job.token,
            residentReady: isResidentReady
        ) ?? 1
        return WorkerQueuedEvent(id: job.request.id, reason: reason, queuePosition: queuePosition)
    }

    private var isResidentReady: Bool {
        if case .ready = residentState {
            return true
        }
        return false
    }

    private func generationActiveRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let activeGeneration else { return nil }
        return ActiveWorkerRequestSummary(
            id: activeGeneration.request.id,
            op: activeGeneration.request.opName,
            profileName: activeGeneration.request.profileName
        )
    }

    private func playbackActiveRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let requestID = activePlayback?.requestID, let speechJob = speechJobs[requestID] else { return nil }
        return ActiveWorkerRequestSummary(id: requestID, op: speechJob.op, profileName: speechJob.profileName)
    }

    private func queuedRequestSummaries(for queueType: WorkerQueueType) async -> [QueuedWorkerRequestSummary] {
        switch queueType {
        case .generation:
            let jobs = await generationController.queuedJobsOrdered()
            return jobs.enumerated().map { offset, job in
                QueuedWorkerRequestSummary(
                    id: job.request.id,
                    op: job.request.opName,
                    profileName: job.request.profileName,
                    queuePosition: offset + 1
                )
            }
        case .playback:
            let waitingPlaybackQueue = playbackQueue.filter { $0 != activePlayback?.requestID }
            return waitingPlaybackQueue.enumerated().compactMap { offset, requestID in
                guard let speechJob = speechJobs[requestID] else { return nil }
                return QueuedWorkerRequestSummary(
                    id: requestID,
                    op: speechJob.op,
                    profileName: speechJob.profileName,
                    queuePosition: offset + 1
                )
            }
        }
    }

    private func queueSummaryActiveRequest(for queueType: WorkerQueueType) async -> ActiveWorkerRequestSummary? {
        switch queueType {
        case .generation:
            return generationActiveRequestSummary()
        case .playback:
            return playbackActiveRequestSummary()
        }
    }

    private func generationQueueDepth() async -> Int {
        (await generationController.queuedJobsOrdered()).count
    }

    private func emitStarted(for request: WorkerRequest) async {
        await emit(WorkerStartedEvent(id: request.id, op: request.opName))
    }

    private func emitProgress(id: String, stage: WorkerProgressStage) async {
        let progress = WorkerProgressEvent(id: id, stage: stage)
        await emit(progress)
        yieldRequestEvent(.progress(progress), for: id)
    }

    private func emitStatus(_ stage: WorkerStatusStage) async {
        let status = WorkerStatusEvent(stage: stage)
        await emit(status)
        broadcastStatus(status)
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

    private func submitRequest(
        id: String,
        op: String,
        text: String? = nil,
        profileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        requestID: String? = nil,
        voiceDescription: String? = nil,
        outputPath: String? = nil
    ) async {
        let request = OutgoingWorkerRequest(
            id: id,
            op: op,
            text: text,
            profileName: profileName,
            cwd: normalizationContext?.cwd,
            repoRoot: normalizationContext?.repoRoot,
            requestID: requestID,
            voiceDescription: voiceDescription,
            outputPath: outputPath
        )

        do {
            let data = try encoder.encode(request)
            let line = String(decoding: data, as: UTF8.self)
            await accept(line: line)
        } catch {
            await emitFailure(
                id: id,
                error: WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly could not encode the outgoing '\(op)' request before queueing it. \(error.localizedDescription)"
                )
            )
        }
    }

    private func submitRequest(_ request: WorkerRequest) async {
        switch request {
        case .queueSpeech(let id, let text, let profileName, _, let normalizationContext):
            await submitRequest(
                id: id,
                op: request.opName,
                text: text,
                profileName: profileName,
                normalizationContext: normalizationContext
            )
        case .createProfile(let id, let profileName, let text, let voiceDescription, let outputPath):
            await submitRequest(
                id: id,
                op: request.opName,
                text: text,
                profileName: profileName,
                voiceDescription: voiceDescription,
                outputPath: outputPath
            )
        case .listProfiles(let id):
            await submitRequest(id: id, op: request.opName)
        case .removeProfile(let id, let profileName):
            await submitRequest(id: id, op: request.opName, profileName: profileName)
        case .listQueue(let id, _):
            await submitRequest(id: id, op: request.opName)
        case .playback(let id, _):
            await submitRequest(id: id, op: request.opName)
        case .clearQueue(let id):
            await submitRequest(id: id, op: request.opName)
        case .cancelRequest(let id, let requestID):
            await submitRequest(id: id, op: request.opName, requestID: requestID)
        }
    }

    private func makeSpeechJobState(for request: WorkerRequest) -> SpeechJobState {
        let requestID = request.id
        let op = request.opName
        let text = switch request {
        case .queueSpeech(_, let text, _, _, _):
            text
        default:
            ""
        }
        let profileName = request.profileName ?? "unknown-profile"
        let normalizationContext = request.normalizationContext
        let normalizedText = SpeechTextNormalizer.normalize(text, context: normalizationContext)
        let textFeatures = SpeechTextNormalizer.forensicFeatures(originalText: text, normalizedText: normalizedText)
        let textSections = SpeechTextNormalizer.forensicSections(originalText: text)
        var continuation: AsyncThrowingStream<[Float], Error>.Continuation?
        let stream = AsyncThrowingStream<[Float], Error> { continuation = $0 }

        return SpeechJobState(
            requestID: requestID,
            op: op,
            text: text,
            normalizedText: normalizedText,
            profileName: profileName,
            normalizationContext: normalizationContext,
            textFeatures: textFeatures,
            textSections: textSections,
            stream: stream,
            continuation: continuation!
        )
    }

    private func removeSpeechJob(requestID: String) -> SpeechJobState? {
        speechJobs.removeValue(forKey: requestID)
    }

    private func removePlaybackJob(requestID: String) {
        playbackQueue.removeAll { $0 == requestID }
    }

    private func handlePlaybackControl(_ action: PlaybackAction) async -> PlaybackState {
        switch action {
        case .pause:
            return await playbackController.pause()
        case .resume:
            return await playbackController.resume()
        case .state:
            return await playbackController.state()
        }
    }

    private func startNextPlaybackIfPossible() async {
        guard !isShuttingDown else { return }
        guard activePlayback == nil else { return }
        guard let requestID = playbackQueue.first, let speechJob = speechJobs[requestID] else { return }
        guard let sampleRate = speechJob.sampleRate else { return }

        let task = Task {
            await self.processPlayback(for: speechJob, sampleRate: sampleRate)
        }
        activePlayback = ActivePlayback(requestID: requestID, task: task)
        speechJob.playbackTask = task
    }

    private func processPlayback(for speechJob: SpeechJobState, sampleRate: Double) async {
        let requestID = speechJob.requestID
        let result: Result<WorkerSuccessPayload, WorkerError>

        do {
            let playbackSummary = try await playbackController.play(
                sampleRate: sampleRate,
                text: speechJob.normalizedText,
                stream: speechJob.stream
            ) { event in
                await self.handlePlaybackEvent(event, for: speechJob)
            }
            await emitProgress(id: requestID, stage: .playbackFinished)
            await logPlaybackFinished(for: speechJob, playbackSummary: playbackSummary, sampleRate: sampleRate)
            result = .success(WorkerSuccessPayload(id: requestID))
        } catch is CancellationError {
            result = .failure(cancellationError(for: requestID))
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Live playback failed for request '\(requestID)' due to an unexpected internal error. \(error.localizedDescription)"
                )
            )
        }

        await finishPlayback(requestID: requestID, result: result)
    }

    private func finishPlayback(requestID: String, result: Result<WorkerSuccessPayload, WorkerError>) async {
        guard activePlayback?.requestID == requestID else { return }
        activePlayback = nil
        removePlaybackJob(requestID: requestID)
        if let speechJob = speechJobs[requestID] {
            speechJob.playbackTask = nil
        }
        await completeSpeechRequestIfNeeded(id: requestID, result: result)
        await startNextPlaybackIfPossible()
    }

    private func completeSpeechRequestIfNeeded(id: String, result: Result<WorkerSuccessPayload, WorkerError>) async {
        guard let speechJob = removeSpeechJob(requestID: id) else { return }
        speechJob.generationTask = nil
        speechJob.playbackTask = nil
        requestAcceptedAt.removeValue(forKey: id)
        let request = WorkerRequest.queueSpeech(
            id: id,
            text: speechJob.text,
            profileName: speechJob.profileName,
            jobType: .live,
            normalizationContext: speechJob.normalizationContext
        )
        await completeRequest(request: request, result: result)
    }

    private func handlePlaybackEvent(_ event: PlaybackEvent, for speechJob: SpeechJobState) async {
        let id = speechJob.requestID
        let op = speechJob.op
        let profileName = speechJob.profileName

        switch event {
        case .firstChunk:
            await emitProgress(id: id, stage: .bufferingAudio)
            await logRequestEvent("playback_first_chunk", requestID: id, op: op, profileName: profileName)
        case .prerollReady(let startupBufferedAudioMS, let thresholds):
            await emitProgress(id: id, stage: .prerollReady)
            await logRequestEvent(
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
            await logRequestEvent(
                "playback_started",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "text_complexity_class": .string(thresholds.complexityClass.rawValue),
                    "startup_buffer_target_ms": .int(thresholds.startupBufferTargetMS),
                    "startup_buffered_audio_ms": .int(startupBufferedAudioMS),
                ]
                .merging(textFeatureDetails(speechJob.textFeatures), uniquingKeysWith: { _, new in new })
                .merging(["section_count": .int(speechJob.textSections.count)], uniquingKeysWith: { _, new in new })
                .merging(memoryDetails(), uniquingKeysWith: { _, new in new })
            )
            for section in speechJob.textSections {
                await logRequestEvent(
                    "playback_section_detected",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: textSectionDetails(section)
                )
            }
        case .queueDepthLow(let queuedAudioMS):
            await logRequestEvent("playback_queue_depth_low", requestID: id, op: op, profileName: profileName, details: ["queued_audio_ms": .int(queuedAudioMS)])
        case .chunkGapWarning(let gapMS, let chunkIndex):
            await logRequestEvent(
                "playback_chunk_gap_warning",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["gap_ms": .int(gapMS), "chunk_index": .int(chunkIndex)]
            )
        case .scheduleGapWarning(let gapMS, let bufferIndex, let queuedAudioMS):
            await logRequestEvent(
                "playback_schedule_gap_warning",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["gap_ms": .int(gapMS), "buffer_index": .int(bufferIndex), "queued_audio_ms": .int(queuedAudioMS)]
            )
        case .starved:
            await logRequestEvent("playback_starved", requestID: id, op: op, profileName: profileName)
        case .rebufferThrashWarning(let rebufferEventCount, let windowMS):
            await logRequestEvent(
                "playback_rebuffer_thrash_warning",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["rebuffer_event_count": .int(rebufferEventCount), "window_ms": .int(windowMS)]
            )
        case .outputDeviceChanged(let previousDevice, let currentDevice):
            var details = [String: LogValue]()
            if let previousDevice {
                details["previous_device"] = .string(previousDevice)
            }
            if let currentDevice {
                details["current_device"] = .string(currentDevice)
            }
            await logRequestEvent("playback_output_device_changed", requestID: id, op: op, profileName: profileName, details: details)
        case .engineConfigurationChanged(let engineIsRunning):
            await logRequestEvent(
                "playback_engine_configuration_changed",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["engine_is_running": .bool(engineIsRunning)]
            )
        case .rebufferStarted(let queuedAudioMS, let thresholds):
            await logRequestEvent(
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
            await logRequestEvent(
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
        case .bufferShapeSummary(let maxBoundaryDiscontinuity, let maxLeadingAbsAmplitude, let maxTrailingAbsAmplitude, let fadeInChunkCount):
            await logRequestEvent(
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
            if let chunkIndex = trace.chunkIndex { details["chunk_index"] = .int(chunkIndex) }
            if let bufferIndex = trace.bufferIndex { details["buffer_index"] = .int(bufferIndex) }
            if let sampleCount = trace.sampleCount { details["sample_count"] = .int(sampleCount) }
            if let durationMS = trace.durationMS { details["duration_ms"] = .int(durationMS) }
            if let queuedAudioBeforeMS = trace.queuedAudioBeforeMS { details["queued_audio_before_ms"] = .int(queuedAudioBeforeMS) }
            if let queuedAudioAfterMS = trace.queuedAudioAfterMS { details["queued_audio_after_ms"] = .int(queuedAudioAfterMS) }
            if let gapMS = trace.gapMS { details["gap_ms"] = .int(gapMS) }
            if let isRebuffering = trace.isRebuffering { details["is_rebuffering"] = .bool(isRebuffering) }
            if let fadeInApplied = trace.fadeInApplied { details["fade_in_applied"] = .bool(fadeInApplied) }
            await logRequestEvent("playback_trace_\(trace.name)", requestID: id, op: op, profileName: profileName, details: details)
        }
    }

    private func logPlaybackFinished(
        for speechJob: SpeechJobState,
        playbackSummary: PlaybackSummary,
        sampleRate: Double
    ) async {
        let id = speechJob.requestID
        let op = speechJob.op
        let profileName = speechJob.profileName

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

        if let startupBufferedAudioMS = playbackSummary.startupBufferedAudioMS { details["startup_buffered_audio_ms"] = .int(startupBufferedAudioMS) }
        if let timeToFirstChunkMS = playbackSummary.timeToFirstChunkMS { details["time_to_first_chunk_ms"] = .int(timeToFirstChunkMS) }
        if let timeToPrerollReadyMS = playbackSummary.timeToPrerollReadyMS { details["time_to_preroll_ready_ms"] = .int(timeToPrerollReadyMS) }
        if let timeFromPrerollReadyToDrainMS = playbackSummary.timeFromPrerollReadyToDrainMS { details["time_from_preroll_ready_to_drain_ms"] = .int(timeFromPrerollReadyToDrainMS) }
        if let minQueuedAudioMS = playbackSummary.minQueuedAudioMS { details["min_queued_audio_ms"] = .int(minQueuedAudioMS) }
        if let maxQueuedAudioMS = playbackSummary.maxQueuedAudioMS { details["max_queued_audio_ms"] = .int(maxQueuedAudioMS) }
        if let avgQueuedAudioMS = playbackSummary.avgQueuedAudioMS { details["avg_queued_audio_ms"] = .int(avgQueuedAudioMS) }
        if let maxInterChunkGapMS = playbackSummary.maxInterChunkGapMS { details["max_inter_chunk_gap_ms"] = .int(maxInterChunkGapMS) }
        if let avgInterChunkGapMS = playbackSummary.avgInterChunkGapMS { details["avg_inter_chunk_gap_ms"] = .int(avgInterChunkGapMS) }
        if let maxScheduleGapMS = playbackSummary.maxScheduleGapMS { details["max_schedule_gap_ms"] = .int(maxScheduleGapMS) }
        if let avgScheduleGapMS = playbackSummary.avgScheduleGapMS { details["avg_schedule_gap_ms"] = .int(avgScheduleGapMS) }
        if let maxBoundaryDiscontinuity = playbackSummary.maxBoundaryDiscontinuity { details["max_boundary_discontinuity"] = .double(maxBoundaryDiscontinuity) }
        if let maxLeadingAbsAmplitude = playbackSummary.maxLeadingAbsAmplitude { details["max_leading_abs_amplitude"] = .double(maxLeadingAbsAmplitude) }
        if let maxTrailingAbsAmplitude = playbackSummary.maxTrailingAbsAmplitude { details["max_trailing_abs_amplitude"] = .double(maxTrailingAbsAmplitude) }
        details.merge(textFeatureDetails(speechJob.textFeatures), uniquingKeysWith: { _, new in new })
        details["section_count"] = .int(speechJob.textSections.count)
        details.merge(memoryDetails(), uniquingKeysWith: { _, new in new })
        await logRequestEvent("playback_finished", requestID: id, op: op, profileName: profileName, details: details)

        let totalDurationMS = Int((Double(playbackSummary.sampleCount) / sampleRate * 1_000).rounded())
        let sectionWindows = SpeechTextNormalizer.forensicSectionWindows(
            originalText: speechJob.text,
            totalDurationMS: totalDurationMS,
            totalChunkCount: playbackSummary.chunkCount
        )
        for window in sectionWindows {
            await logRequestEvent(
                "playback_section_window",
                requestID: id,
                op: op,
                profileName: profileName,
                details: textSectionWindowDetails(window)
            )
        }
    }

    private func makeRequestHandle(for request: WorkerRequest) -> WorkerRequestHandle {
        let requestID = request.id
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            requestContinuations[requestID] = continuation
            continuation.onTermination = { _ in
                Task {
                    await self.removeRequestContinuation(for: requestID)
                }
            }
        }

        return WorkerRequestHandle(
            id: requestID,
            operationName: request.opName,
            profileName: request.profileName,
            events: events
        )
    }

    private func yieldRequestEvent(_ event: WorkerRequestStreamEvent, for requestID: String) {
        requestContinuations[requestID]?.yield(event)
    }

    private func finishRequestStream(for requestID: String) {
        requestContinuations[requestID]?.finish()
        requestContinuations.removeValue(forKey: requestID)
    }

    private func failRequestStream(for requestID: String, error: WorkerError) {
        requestContinuations[requestID]?.finish(
            throwing: WorkerError(code: error.code, message: error.message)
        )
        requestContinuations.removeValue(forKey: requestID)
    }

    private func broadcastStatus(_ status: WorkerStatusEvent) {
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }

    private func currentStatusSnapshot() -> WorkerStatusEvent? {
        switch residentState {
        case .warming:
            guard preloadTask != nil else { return nil }
            return WorkerStatusEvent(stage: .warmingResidentModel)
        case .ready:
            return WorkerStatusEvent(stage: .residentModelReady)
        case .failed:
            return WorkerStatusEvent(stage: .residentModelFailed)
        }
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }

    private func removeRequestContinuation(for requestID: String) {
        requestContinuations.removeValue(forKey: requestID)
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
