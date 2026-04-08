import Foundation
import TextForSpeech

// MARK: - Worker Runtime

public extension SpeakSwiftly {
    actor Runtime {
    private enum Environment {
        static let profileRootOverride = "SPEAKSWIFTLY_PROFILE_ROOT"
    }

    enum PlaybackConfiguration {
        // Shorter chunk cadence gives playback a second chunk in reserve before
        // the first one drains, which reduces audible shudder from one-chunk starts.
        static let residentStreamingInterval = 0.18
    }

    enum ResidentState: Sendable {
        case warming
        case ready(ResidentSpeechModels)
        case unloaded
        case failed(WorkerError)
    }

    struct ActiveRequest: Sendable {
        let token: UUID
        let request: WorkerRequest
        let task: Task<Void, Never>
    }

    struct WorkerSuccessPayload: Sendable {
        let id: String
        let generatedFile: SpeakSwiftly.GeneratedFile?
        let generatedFiles: [SpeakSwiftly.GeneratedFile]?
        let generatedBatch: SpeakSwiftly.GeneratedBatch?
        let generatedBatches: [SpeakSwiftly.GeneratedBatch]?
        let generationJob: SpeakSwiftly.GenerationJob?
        let generationJobs: [SpeakSwiftly.GenerationJob]?
        let profileName: String?
        let profilePath: String?
        let profiles: [ProfileSummary]?
        let textProfile: TextForSpeech.Profile?
        let textProfiles: [TextForSpeech.Profile]?
        let textProfilePath: String?
        let activeRequest: ActiveWorkerRequestSummary?
        let queue: [QueuedWorkerRequestSummary]?
        let playbackState: PlaybackStateSummary?
        let status: WorkerStatusEvent?
        let speechBackend: SpeakSwiftly.SpeechBackend?
        let clearedCount: Int?
        let cancelledRequestID: String?

        init(
            id: String,
            generatedFile: SpeakSwiftly.GeneratedFile? = nil,
            generatedFiles: [SpeakSwiftly.GeneratedFile]? = nil,
            generatedBatch: SpeakSwiftly.GeneratedBatch? = nil,
            generatedBatches: [SpeakSwiftly.GeneratedBatch]? = nil,
            generationJob: SpeakSwiftly.GenerationJob? = nil,
            generationJobs: [SpeakSwiftly.GenerationJob]? = nil,
            profileName: String? = nil,
            profilePath: String? = nil,
            profiles: [ProfileSummary]? = nil,
            textProfile: TextForSpeech.Profile? = nil,
            textProfiles: [TextForSpeech.Profile]? = nil,
            textProfilePath: String? = nil,
            activeRequest: ActiveWorkerRequestSummary? = nil,
            queue: [QueuedWorkerRequestSummary]? = nil,
            playbackState: PlaybackStateSummary? = nil,
            status: WorkerStatusEvent? = nil,
            speechBackend: SpeakSwiftly.SpeechBackend? = nil,
            clearedCount: Int? = nil,
            cancelledRequestID: String? = nil
        ) {
            self.id = id
            self.generatedFile = generatedFile
            self.generatedFiles = generatedFiles
            self.generatedBatch = generatedBatch
            self.generatedBatches = generatedBatches
            self.generationJob = generationJob
            self.generationJobs = generationJobs
            self.profileName = profileName
            self.profilePath = profilePath
            self.profiles = profiles
            self.textProfile = textProfile
            self.textProfiles = textProfiles
            self.textProfilePath = textProfilePath
            self.activeRequest = activeRequest
            self.queue = queue
            self.playbackState = playbackState
            self.status = status
            self.speechBackend = speechBackend
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
        let artifactID: String?
        let batchID: String?
        let jobID: String?
        let items: [SpeakSwiftly.GenerationJobItem]?
        let text: String?
        let profileName: String?
        let textProfileName: String?
        let textProfileID: String?
        let textProfileDisplayName: String?
        let textProfile: TextForSpeech.Profile?
        let replacements: [TextForSpeech.Replacement]?
        let replacement: TextForSpeech.Replacement?
        let replacementID: String?
        let cwd: String?
        let repoRoot: String?
        let textFormat: TextForSpeech.TextFormat?
        let nestedSourceFormat: TextForSpeech.SourceFormat?
        let sourceFormat: TextForSpeech.SourceFormat?
        let requestID: String?
        let speechBackend: SpeakSwiftly.SpeechBackend?
        let vibe: SpeakSwiftly.Vibe?
        let voiceDescription: String?
        let outputPath: String?
        let referenceAudioPath: String?
        let transcript: String?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case artifactID = "artifact_id"
            case batchID = "batch_id"
            case jobID = "job_id"
            case items
            case text
            case profileName = "profile_name"
            case textProfileName = "text_profile_name"
            case textProfileID = "text_profile_id"
            case textProfileDisplayName = "text_profile_display_name"
            case textProfile = "text_profile"
            case replacements
            case replacement
            case replacementID = "replacement_id"
            case cwd
            case repoRoot = "repo_root"
            case textFormat = "text_format"
            case nestedSourceFormat = "nested_source_format"
            case sourceFormat = "source_format"
            case requestID = "request_id"
            case speechBackend = "speech_backend"
            case vibe
            case voiceDescription = "voice_description"
            case outputPath = "output_path"
            case referenceAudioPath = "reference_audio_path"
            case transcript
        }
    }

    typealias LogLevel = WorkerLogLevel
    typealias LogValue = WorkerLogValue
    typealias LogEvent = WorkerLogEvent

    let dependencies: WorkerDependencies
    var speechBackend: SpeakSwiftly.SpeechBackend
    let encoder = JSONEncoder()
    let profileStore: ProfileStore
    let generatedFileStore: GeneratedFileStore
    let generationJobStore: GenerationJobStore
    let normalizerRef: SpeakSwiftly.Normalizer
    let playbackController: PlaybackController
    let generationController = GenerationController()
    let logTimestampFormatter = ISO8601DateFormatter()
    private let maxAcceptedSpeechJobs = 8

    var residentState: ResidentState = .warming
    var isShuttingDown = false
    var preloadTask: Task<Void, Never>?
    var residentPreloadToken: UUID?
    var requestAcceptedAt = [String: Date]()
    var statusContinuations = [UUID: AsyncStream<WorkerStatusEvent>.Continuation]()
    var requestContinuations = [String: AsyncThrowingStream<WorkerRequestStreamEvent, any Swift.Error>.Continuation]()
    var activeGeneration: ActiveRequest?
    // MARK: - Lifecycle

    init(
        dependencies: WorkerDependencies,
        speechBackend: SpeakSwiftly.SpeechBackend,
        profileStore: ProfileStore,
        generatedFileStore: GeneratedFileStore,
        generationJobStore: GenerationJobStore,
        normalizer: SpeakSwiftly.Normalizer,
        playbackController: PlaybackController
    ) {
        self.dependencies = dependencies
        self.speechBackend = speechBackend
        self.profileStore = profileStore
        self.generatedFileStore = generatedFileStore
        self.generationJobStore = generationJobStore
        normalizerRef = normalizer
        self.playbackController = playbackController
        encoder.outputFormatting = [.sortedKeys]
    }

    public static func live(
        normalizer: SpeakSwiftly.Normalizer? = nil,
        configuration: SpeakSwiftly.Configuration? = nil,
        speechBackend: SpeakSwiftly.SpeechBackend? = nil
    ) async -> Runtime {
        let dependencies = WorkerDependencies.live()
        let environment = ProcessInfo.processInfo.environment
        let configuredSpeechBackend = resolvedSpeechBackend(
            dependencies: dependencies,
            environment: environment,
            configuration: configuration,
            explicitSpeechBackend: speechBackend
        )
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                overridePath: environment[Environment.profileRootOverride]
            ),
            fileManager: dependencies.fileManager
        )
        let normalizer = normalizer ?? SpeakSwiftly.Normalizer(
            persistenceURL: profileStore.rootURL.appending(path: ProfileStore.textProfilesFileName)
        )
        let generatedFileStore = GeneratedFileStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true)
        )
        let generationJobStore = GenerationJobStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true)
        )
        do {
            try await normalizer.loadProfiles()
        } catch {
            let path = await normalizer.persistenceURL()?.path ?? "unknown path"
            let message = "SpeakSwiftly could not load persisted text profiles from '\(path)'. \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        let playbackController = PlaybackController(driver: await dependencies.makePlaybackController())

        let runtime = Runtime(
            dependencies: dependencies,
            speechBackend: configuredSpeechBackend,
            profileStore: profileStore,
            generatedFileStore: generatedFileStore,
            generationJobStore: generationJobStore,
            normalizer: normalizer,
            playbackController: playbackController
        )
        await runtime.installPlaybackHooks()
        return runtime
    }

    static func resolvedSpeechBackend(
        dependencies: WorkerDependencies,
        environment: [String: String],
        configuration: SpeakSwiftly.Configuration?,
        explicitSpeechBackend: SpeakSwiftly.SpeechBackend?
    ) -> SpeakSwiftly.SpeechBackend {
        if let explicitSpeechBackend {
            return explicitSpeechBackend
        }

        if let configuration {
            return configuration.speechBackend
        }

        if let environmentBackend = SpeakSwiftly.SpeechBackend.configured(in: environment) {
            return environmentBackend
        }

        do {
            if let persistedConfiguration = try SpeakSwiftly.Configuration.loadDefault(
                fileManager: dependencies.fileManager,
                profileRootOverride: environment[Environment.profileRootOverride]
            ) {
                return persistedConfiguration.speechBackend
            }
        } catch {
            let configurationPath = SpeakSwiftly.Configuration.defaultPersistenceURL(
                fileManager: dependencies.fileManager,
                profileRootOverride: environment[Environment.profileRootOverride]
            ).path
            let message = "SpeakSwiftly could not load persisted runtime configuration from '\(configurationPath)'. Falling back to the default speech backend. \(error.localizedDescription)\n"
            dependencies.writeStderr(message)
        }

        return .qwen3
    }

    func installPlaybackHooks() async {
        await playbackController.bind(
            PlaybackHooks(
                handleEvent: { [weak self] event, job in
                    await self?.handlePlaybackEvent(event, for: job)
                },
                logFinished: { [weak self] job, playbackSummary, sampleRate in
                    await self?.emitProgress(id: job.requestID, stage: .playbackFinished)
                    await self?.logPlaybackFinished(for: job, playbackSummary: playbackSummary, sampleRate: sampleRate)
                },
                completeJob: { [weak self] job, result in
                    await self?.completePlaybackJob(job, result: result)
                },
                resumeQueue: { [weak self] in
                    guard let self else { return }
                    try? await self.startNextGenerationIfPossible()
                    await self.playbackController.startNextIfPossible()
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
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeStatusContinuation(subscriptionID)
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
        startResidentPreload()
    }

    private func startResidentPreload() {
        let preloadToken = UUID()
        residentPreloadToken = preloadToken
        let targetSpeechBackend = speechBackend

        preloadTask = Task {
            let preloadStartedAt = dependencies.now()
            let preloadModelRepos = preloadModelRepos(for: targetSpeechBackend)
            await emitStatus(.warmingResidentModel)
            await logEvent(
                "resident_model_preload_started",
                details: [
                    "speech_backend": .string(targetSpeechBackend.rawValue),
                    "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                    "profile_root": .string(profileStore.rootURL.path),
                ]
            )

            do {
                try profileStore.ensureRootExists()
                let residentModels = try await dependencies.loadResidentModels(targetSpeechBackend)
                let playbackEngineWasPrepared = try await playbackController.prepare(
                    sampleRate: Double(primaryResidentSampleRate(for: residentModels))
                )
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }
                residentState = .ready(residentModels)
                await emitStatus(.residentModelReady)
                await logEvent(
                    "resident_model_preload_ready",
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
                )
                if playbackEngineWasPrepared {
                    await logEvent(
                        "playback_engine_ready",
                        details: [
                            "sample_rate": .int(primaryResidentSampleRate(for: residentModels)),
                            "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                        ].merging(memoryDetails(), uniquingKeysWith: { _, new in new })
                    )
                }
                try await startNextGenerationIfPossible()
                await playbackController.startNextIfPossible()
            } catch is CancellationError {
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }
                guard !isShuttingDown else { return }

                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload was cancelled before \(preloadModelRepos.joined(separator: ", ")) finished loading for the '\(targetSpeechBackend.rawValue)' backend."
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch let workerError as WorkerError {
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }
                residentState = .failed(workerError)
                await logError(
                    "Resident model preload failed while loading \(preloadModelRepos.joined(separator: ", ")) for the '\(targetSpeechBackend.rawValue)' backend. \(workerError.message)",
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                        "failure_code": .string(workerError.code.rawValue),
                    ]
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch {
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }
                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload failed while loading \(preloadModelRepos.joined(separator: ", ")) for the '\(targetSpeechBackend.rawValue)' backend. \(error.localizedDescription)"
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
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

        if case .failed(let error) = residentState, request.requiresResidentModels {
            let workerError = WorkerError(
                code: error.code,
                message: "Request '\(request.id)' cannot start because the resident model state is failed. Queue `reload_models` or `set_speech_backend` first, then retry the generation request."
            )
            failRequestStream(for: request.id, error: workerError)
            requestAcceptedAt.removeValue(forKey: request.id)
            await emitFailure(id: request.id, error: workerError)
            return
        }

        if request.requiresPlayback, await playbackController.jobCount() >= maxAcceptedSpeechJobs {
            let workerError = WorkerError(
                code: .invalidRequest,
                message: "Request '\(request.id)' was rejected because the live speech queue is already holding \(maxAcceptedSpeechJobs) accepted jobs. Wait for playback to drain or clear queued work before adding more."
            )
            failRequestStream(for: request.id, error: workerError)
            requestAcceptedAt.removeValue(forKey: request.id)
            await emitFailure(id: request.id, error: workerError)
            return
        }

        let queuedGenerationJob: SpeakSwiftly.GenerationJob?
        do {
            queuedGenerationJob = try createQueuedGenerationJobIfNeeded(for: request)
        } catch let workerError as WorkerError {
            failRequestStream(for: request.id, error: workerError)
            requestAcceptedAt.removeValue(forKey: request.id)
            await emitFailure(id: request.id, error: workerError)
            return
        } catch {
            let workerError = WorkerError(
                code: .filesystemError,
                message: "Request '\(request.id)' could not create a persisted generation job record before queueing generation work. \(error.localizedDescription)"
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
        if request.requiresPlayback {
            let speechJob = await makeSpeechJobState(for: request)
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
            let acknowledgement = WorkerSuccessResponse(
                id: request.id,
                generationJob: queuedGenerationJob
            )
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
        let hasActivePlayback = await playbackController.hasActivePlayback()
        let residentState = self.residentState
        let queueDisposition: @Sendable (GenerationController.Job) -> GenerationController.RunDisposition = { job in
            let request = job.request
            if request.requiresPlaybackDrainBeforeStart && hasActivePlayback {
                return .park
            }

            switch residentState {
            case .warming:
                return .park
            case .ready:
                return .run
            case .unloaded:
                return request.requiresResidentModels ? .park : .run
            case .failed:
                if request.mutatesResidentState {
                    return .run
                }
                return request.requiresResidentModels ? .park : .run
            }
        }

        guard let nextJob = await generationController.nextQueuedJob(queueDisposition) else { return }
        guard let job = await generationController.beginNextIfPossible(queueDisposition) else { return }
        guard nextJob.token == job.token else { return }

        try? markGenerationJobRunningIfNeeded(for: job.request)

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
        if case .queueSpeech(id: let id, text: _, profileName: _, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _) = job.request {
            await playbackController.setGenerationTask(task, for: id)
        }
    }

    private func processGeneration(_ request: WorkerRequest, token: UUID) async {
        let disposition: GenerationCompletionDisposition

        do {
            switch request {
            case .queueSpeech(id: let id, text: let text, profileName: let profileName, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
                try await handleQueueSpeechLiveGeneration(id: id, op: request.opName, text: text, profileName: profileName)
                disposition = .requestStillPendingPlayback(id)

            case .queueSpeech(
                id: let id,
                text: let text,
                profileName: let profileName,
                textProfileName: let textProfileName,
                jobType: .file,
                textContext: let textContext,
                sourceFormat: let sourceFormat
            ):
                let generatedFile = try await handleQueueSpeechFileGeneration(
                    requestID: id,
                    op: request.opName,
                    artifactID: fileArtifactID(for: request),
                    text: text,
                    profileName: profileName,
                    textProfileName: textProfileName,
                    textContext: textContext,
                    sourceFormat: sourceFormat
                )
                let completedJob = try generationJobStore.markCompleted(
                    id: id,
                    artifacts: [
                        SpeakSwiftly.GenerationArtifact(
                            artifactID: generatedFile.artifactID,
                            kind: .audioWAV,
                            createdAt: generatedFile.createdAt,
                            filePath: generatedFile.filePath,
                            sampleRate: generatedFile.sampleRate,
                            profileName: generatedFile.profileName,
                            textProfileName: generatedFile.textProfileName
                        )
                    ],
                    completedAt: dependencies.now()
                )
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        generatedFile: generatedFile,
                        generationJob: completedJob
                    )
                ))

            case .queueBatch(
                id: let id,
                profileName: let profileName,
                items: let items
            ):
                let generatedFiles = try await handleQueueSpeechBatchGeneration(
                    requestID: id,
                    op: request.opName,
                    profileName: profileName,
                    items: items
                )
                let completedJob = try generationJobStore.markCompleted(
                    id: id,
                    artifacts: generatedFiles.map { generatedFile in
                        SpeakSwiftly.GenerationArtifact(
                            artifactID: generatedFile.artifactID,
                            kind: .audioWAV,
                            createdAt: generatedFile.createdAt,
                            filePath: generatedFile.filePath,
                            sampleRate: generatedFile.sampleRate,
                            profileName: generatedFile.profileName,
                            textProfileName: generatedFile.textProfileName
                        )
                    },
                    completedAt: dependencies.now()
                )
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        generatedBatch: try loadGeneratedBatch(from: completedJob),
                        generationJob: completedJob
                    )
                ))

            case .switchSpeechBackend(id: let id, speechBackend: let requestedSpeechBackend):
                let status = try await performOrderedSpeechBackendSwitch(to: requestedSpeechBackend)
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        status: status,
                        speechBackend: speechBackend
                    )
                ))

            case .reloadModels(id: let id):
                let status = try await performOrderedModelReload()
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        status: status,
                        speechBackend: speechBackend
                    )
                ))

            case .unloadModels(id: let id):
                let status = await performOrderedModelUnload()
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        status: status,
                        speechBackend: speechBackend
                    )
                ))

            case .createProfile(let id, let profileName, let text, let vibe, let voiceDescription, let outputPath, let cwd):
                let storedProfile = try await handleCreateProfile(
                    id: id,
                    profileName: profileName,
                    text: text,
                    vibe: vibe,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath,
                    cwd: cwd
                )
                disposition = .requestCompleted(.success(
                    WorkerSuccessPayload(
                        id: id,
                        profileName: storedProfile.manifest.profileName,
                        profilePath: storedProfile.directoryURL.path
                    )
                ))

            case .createClone(let id, let profileName, let referenceAudioPath, let vibe, let transcript, let cwd):
                let storedProfile = try await handleCreateClone(
                    id: id,
                    profileName: profileName,
                    referenceAudioPath: referenceAudioPath,
                    vibe: vibe,
                    transcript: transcript,
                    cwd: cwd
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

            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .textProfileActive,
                 .textProfileBase,
                 .textProfile,
                 .textProfiles,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .createTextProfile,
                 .storeTextProfile,
                 .useTextProfile,
                 .removeTextProfile,
                 .resetTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .listQueue,
                 .status,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
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
        let textProfilePath = await normalizerRef.persistenceURL()?.path

        do {
            switch request {
            case .generatedFile(let id, let artifactID):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generatedFile: try generatedFileStore.loadGeneratedFile(id: artifactID).summary
                    )
                )

            case .generatedFiles(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generatedFiles: try generatedFileStore.listGeneratedFiles()
                    )
                )

            case .generatedBatch(let id, let batchID):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generatedBatch: try loadGeneratedBatch(id: batchID)
                    )
                )

            case .generatedBatches(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generatedBatches: try listGeneratedBatches()
                    )
                )

            case .expireGenerationJob(let id, let jobID):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generationJob: try expireGenerationJob(id: jobID)
                    )
                )

            case .generationJob(let id, let jobID):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generationJob: try generationJobStore.loadGenerationJob(id: jobID)
                    )
                )

            case .generationJobs(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        generationJobs: try generationJobStore.listGenerationJobs()
                    )
                )

            case .textProfileActive(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: await normalizerRef.activeProfile(),
                        textProfilePath: textProfilePath
                    )
                )

            case .textProfileBase(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: await normalizerRef.baseProfile(),
                        textProfilePath: textProfilePath
                    )
                )

            case .textProfile(let id, let name):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: await normalizerRef.profile(named: name),
                        textProfilePath: textProfilePath
                    )
                )

            case .textProfiles(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfiles: await normalizerRef.profiles(),
                        textProfilePath: textProfilePath
                    )
                )

            case .textProfileEffective(let id, let name):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: await normalizerRef.effectiveProfile(named: name),
                        textProfilePath: textProfilePath
                    )
                )

            case .textProfilePersistence(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfilePath: textProfilePath
                    )
                )

            case .loadTextProfiles(let id):
                try await normalizerRef.loadProfiles()
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: await normalizerRef.activeProfile(),
                        textProfiles: await normalizerRef.profiles(),
                        textProfilePath: textProfilePath
                    )
                )

            case .saveTextProfiles(let id):
                try await normalizerRef.saveProfiles()
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfilePath: textProfilePath
                    )
                )

            case .createTextProfile(let id, let profileID, let profileName, let replacements):
                let profile = try await normalizerRef.createProfile(
                    id: profileID,
                    named: profileName,
                    replacements: replacements
                )
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: profile,
                        textProfilePath: textProfilePath
                    )
                )

            case .storeTextProfile(let id, let profile):
                try await normalizerRef.storeProfile(profile)
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: profile,
                        textProfilePath: textProfilePath
                    )
                )

            case .useTextProfile(let id, let profile):
                try await normalizerRef.useProfile(profile)
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: profile,
                        textProfilePath: textProfilePath
                    )
                )

            case .removeTextProfile(let id, let profileName):
                try await normalizerRef.removeProfile(named: profileName)
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfilePath: textProfilePath
                    )
                )

            case .resetTextProfile(let id):
                try await normalizerRef.reset()
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: await normalizerRef.activeProfile(),
                        textProfilePath: textProfilePath
                    )
                )

            case .addTextReplacement(let id, let replacement, let profileName):
                let profile = if let profileName {
                    try await normalizerRef.addReplacement(
                        replacement,
                        toStoredProfileNamed: profileName
                    )
                } else {
                    try await normalizerRef.addReplacement(replacement)
                }
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: profile,
                        textProfilePath: textProfilePath
                    )
                )

            case .replaceTextReplacement(let id, let replacement, let profileName):
                let profile = if let profileName {
                    try await normalizerRef.replaceReplacement(
                        replacement,
                        inStoredProfileNamed: profileName
                    )
                } else {
                    try await normalizerRef.replaceReplacement(replacement)
                }
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: profile,
                        textProfilePath: textProfilePath
                    )
                )

            case .removeTextReplacement(let id, let replacementID, let profileName):
                let profile = if let profileName {
                    try await normalizerRef.removeReplacement(
                        id: replacementID,
                        fromStoredProfileNamed: profileName
                    )
                } else {
                    try await normalizerRef.removeReplacement(id: replacementID)
                }
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        textProfile: profile,
                        textProfilePath: textProfilePath
                    )
                )

            case .listQueue(let id, let queueType):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        activeRequest: await queueSummaryActiveRequest(for: queueType),
                        queue: await queuedRequestSummaries(for: queueType)
                    )
                )

            case .status(let id):
                result = .success(
                    WorkerSuccessPayload(
                        id: id,
                        status: currentStatusSnapshot(),
                        speechBackend: speechBackend
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
                 .queueBatch,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
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
        guard let speechJob = await playbackController.job(for: id) else {
            throw WorkerError(
                code: .internalError,
                message: "Request '\(id)' started generation without a matching live speech job state. This indicates a SpeakSwiftly runtime bug."
            )
        }
        let residentInputs = try await loadResidentSpeechInputs(
            requestID: id,
            op: op,
            profileName: profileName
        )
        let residentModel = residentInputs.model
        speechJob.sampleRate = Double(residentModel.sampleRate)

        await emitProgress(id: id, stage: .startingPlayback)
        let stream = residentGenerationStream(
            text: speechJob.normalizedText,
            inputs: residentInputs,
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

    private func handleQueueSpeechBatchGeneration(
        requestID id: String,
        op: String,
        profileName: String,
        items: [SpeakSwiftly.GenerationJobItem]
    ) async throws -> [SpeakSwiftly.GeneratedFile] {
        var generatedFiles = [SpeakSwiftly.GeneratedFile]()
        generatedFiles.reserveCapacity(items.count)

        for item in items {
            try Task.checkCancellation()
            generatedFiles.append(
                try await handleQueueSpeechFileGeneration(
                    requestID: id,
                    op: op,
                    artifactID: item.artifactID,
                    text: item.text,
                    profileName: profileName,
                    textProfileName: item.textProfileName,
                    textContext: item.textContext,
                    sourceFormat: item.sourceFormat
                )
            )
        }

        return generatedFiles
    }

    private func fileArtifactID(for request: WorkerRequest) -> String {
        switch request {
        case .queueSpeech(id: let id, text: _, profileName: _, textProfileName: _, jobType: .file, textContext: _, sourceFormat: _):
            return "\(id)-artifact-1"
        default:
            return request.id
        }
    }

    private func loadGeneratedBatch(id batchID: String) throws -> SpeakSwiftly.GeneratedBatch {
        try loadGeneratedBatch(from: generationJobStore.loadGenerationJob(id: batchID))
    }

    private func listGeneratedBatches() throws -> [SpeakSwiftly.GeneratedBatch] {
        try generationJobStore.listGenerationJobs()
            .filter { $0.jobKind == .batch }
            .map(loadGeneratedBatch(from:))
    }

    private func loadGeneratedBatch(
        from job: SpeakSwiftly.GenerationJob
    ) throws -> SpeakSwiftly.GeneratedBatch {
        guard job.jobKind == .batch else {
            throw WorkerError(
                code: .generatedBatchNotFound,
                message: "Generated batch '\(job.jobID)' was requested, but that id belongs to a file job rather than a batch job."
            )
        }

        let artifacts: [SpeakSwiftly.GeneratedFile] = if job.state == .expired {
            []
        } else {
            try job.artifacts.map { artifact in
                try generatedFileStore.loadGeneratedFile(id: artifact.artifactID).summary
            }
        }

        return SpeakSwiftly.GeneratedBatch(
            batchID: job.jobID,
            profileName: job.profileName,
            textProfileName: job.textProfileName,
            speechBackend: job.speechBackend,
            state: job.state,
            items: job.items,
            artifacts: artifacts,
            failure: job.failure,
            createdAt: job.createdAt,
            updatedAt: job.updatedAt,
            startedAt: job.startedAt,
            completedAt: job.completedAt,
            failedAt: job.failedAt,
            expiresAt: job.expiresAt,
            retentionPolicy: job.retentionPolicy
        )
    }

    private func expireGenerationJob(
        id jobID: String
    ) throws -> SpeakSwiftly.GenerationJob {
        let job = try generationJobStore.loadGenerationJob(id: jobID)
        guard job.state != .queued, job.state != .running else {
            throw WorkerError(
                code: .generationJobNotExpirable,
                message: "Generation job '\(jobID)' is still \(job.state.rawValue) and cannot be expired until its generation work has finished."
            )
        }

        for artifact in job.artifacts {
            _ = try generatedFileStore.removeGeneratedFile(id: artifact.artifactID)
        }

        return try generationJobStore.markExpired(id: jobID, expiredAt: dependencies.now())
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

    func preloadModelRepos(for speechBackend: SpeakSwiftly.SpeechBackend) -> [String] {
        switch speechBackend {
        case .qwen3:
            [ModelFactory.qwenResidentModelRepo]
        case .marvis:
            [ModelFactory.marvisResidentModelRepo, ModelFactory.marvisResidentModelRepo]
        }
    }

    func shouldApplyResidentPreloadResult(
        token: UUID,
        backend: SpeakSwiftly.SpeechBackend
    ) -> Bool {
        residentPreloadToken == token && speechBackend == backend
    }

    func performOrderedSpeechBackendSwitch(
        to requestedSpeechBackend: SpeakSwiftly.SpeechBackend
    ) async throws -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        speechBackend = requestedSpeechBackend
        residentState = .warming
        startResidentPreload()
        await preloadTask?.value

        switch residentState {
        case .ready, .warming:
            return currentStatusSnapshot()
        case .unloaded:
            return currentStatusSnapshot()
        case .failed(let error):
            throw error
        }
    }

    func performOrderedModelReload() async throws -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        residentState = .warming
        startResidentPreload()
        await preloadTask?.value

        switch residentState {
        case .ready, .warming, .unloaded:
            return currentStatusSnapshot()
        case .failed(let error):
            throw error
        }
    }

    func performOrderedModelUnload() async -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        residentPreloadToken = nil
        residentState = .unloaded
        await emitStatus(.residentModelsUnloaded)
        return currentStatusSnapshot()
    }

    func primaryResidentSampleRate(for models: ResidentSpeechModels) -> Int {
        switch models {
        case .qwen3(let model):
            model.sampleRate
        case .marvis(let models):
            models.conversationalA.sampleRate
        }
    }

    func residentQwenModelOrThrow() throws -> AnySpeechModel {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down."
            )
        }

        switch residentState {
        case .ready(.qwen3(let model)):
            return model
        case .ready(.marvis):
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly attempted to use the resident Qwen model while the runtime is configured for the 'marvis' backend. This indicates a backend-routing bug."
            )
        case .warming:
            throw WorkerError(code: .modelLoading, message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.")
        case .unloaded:
            throw WorkerError(
                code: .modelLoading,
                message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready."
            )
        case .failed(let error):
            throw error
        }
    }

    func residentMarvisModelOrThrow(
        for vibe: SpeakSwiftly.Vibe
    ) throws -> (model: AnySpeechModel, voice: MarvisResidentVoice) {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down."
            )
        }

        switch residentState {
        case .ready(.marvis(let models)):
            return models.model(for: vibe)
        case .ready(.qwen3):
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly attempted to use the resident Marvis model bundle while the runtime is configured for the 'qwen3' backend. This indicates a backend-routing bug."
            )
        case .warming:
            throw WorkerError(code: .modelLoading, message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.")
        case .unloaded:
            throw WorkerError(
                code: .modelLoading,
                message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready."
            )
        case .failed(let error):
            throw error
        }
    }

    func failQueuedRequests(with error: WorkerError) async {
        let queuedJobs = await generationController.clearQueued()

        for job in queuedJobs {
            if job.request.requiresPlayback {
                _ = await playbackController.discard(requestID: job.request.id)
            }
            markGenerationJobFailedIfNeeded(for: job.request, error: error)
            failRequestStream(for: job.request.id, error: error)
            requestAcceptedAt.removeValue(forKey: job.request.id)
            await emitFailure(id: job.request.id, error: error)
        }
    }

    private func finishActiveGeneration(token: UUID, request: WorkerRequest, disposition: GenerationCompletionDisposition) async {
        guard activeGeneration?.token == token else { return }

        activeGeneration = nil
        await generationController.finishActive(token: token)
        recordGenerationDispositionIfNeeded(for: request, disposition: disposition)
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

    private func createQueuedGenerationJobIfNeeded(
        for request: WorkerRequest
    ) throws -> SpeakSwiftly.GenerationJob? {
        switch request {
        case .queueSpeech(
            id: let id,
            text: let text,
            profileName: let profileName,
            textProfileName: let textProfileName,
            jobType: .file,
            textContext: let textContext,
            sourceFormat: let sourceFormat
        ):
            return try generationJobStore.createFileJob(
                jobID: id,
                profileName: profileName,
                textProfileName: textProfileName,
                speechBackend: speechBackend,
                item: SpeakSwiftly.GenerationJobItem(
                    artifactID: fileArtifactID(for: request),
                    text: text,
                    textProfileName: textProfileName,
                    textContext: textContext,
                    sourceFormat: sourceFormat
                ),
                createdAt: dependencies.now()
            )
        case .queueBatch(
            id: let id,
            profileName: let profileName,
            items: let items
        ):
            return try generationJobStore.createBatchJob(
                jobID: id,
                profileName: profileName,
                textProfileName: request.textProfileName,
                speechBackend: speechBackend,
                items: items,
                createdAt: dependencies.now()
            )
        default:
            return nil
        }
    }

    private func markGenerationJobRunningIfNeeded(for request: WorkerRequest) throws {
        switch request {
        case .queueSpeech(
            id: let id,
            text: _,
            profileName: _,
            textProfileName: _,
            jobType: .file,
            textContext: _,
            sourceFormat: _
        ),
        .queueBatch(id: let id, profileName: _, items: _):
            _ = try generationJobStore.markRunning(
                id: id,
                speechBackend: speechBackend,
                startedAt: dependencies.now()
            )
        default:
            return
        }
    }

    private func recordGenerationDispositionIfNeeded(
        for request: WorkerRequest,
        disposition: GenerationCompletionDisposition
    ) {
        switch disposition {
        case .requestStillPendingPlayback:
            return
        case .requestCompleted(.success(let payload)):
            switch request {
            case .queueSpeech(
                id: let id,
                text: _,
                profileName: _,
                textProfileName: _,
                jobType: .file,
                textContext: _,
                sourceFormat: _
            ):
                if payload.generationJob != nil {
                    return
                }
                if let generatedFile = payload.generatedFile {
                    let artifact = SpeakSwiftly.GenerationArtifact(
                        artifactID: generatedFile.artifactID,
                        kind: .audioWAV,
                        createdAt: generatedFile.createdAt,
                        filePath: generatedFile.filePath,
                        sampleRate: generatedFile.sampleRate,
                        profileName: generatedFile.profileName,
                        textProfileName: generatedFile.textProfileName
                    )
                    _ = try? generationJobStore.markCompleted(
                        id: id,
                        artifacts: [artifact],
                        completedAt: dependencies.now()
                    )
                }
            case .queueBatch(id: let id, profileName: _, items: _):
                if payload.generationJob != nil {
                    return
                }
                if let generatedBatch = payload.generatedBatch {
                    let artifacts = generatedBatch.artifacts.map { generatedFile in
                        SpeakSwiftly.GenerationArtifact(
                            artifactID: generatedFile.artifactID,
                            kind: .audioWAV,
                            createdAt: generatedFile.createdAt,
                            filePath: generatedFile.filePath,
                            sampleRate: generatedFile.sampleRate,
                            profileName: generatedFile.profileName,
                            textProfileName: generatedFile.textProfileName
                        )
                    }
                    _ = try? generationJobStore.markCompleted(
                        id: id,
                        artifacts: artifacts,
                        completedAt: dependencies.now()
                    )
                }
            default:
                return
            }
        case .requestCompleted(.failure(let error)):
            markGenerationJobFailedIfNeeded(for: request, error: error)
        }
    }

    func markGenerationJobFailedIfNeeded(
        for request: WorkerRequest,
        error: WorkerError
    ) {
        switch request {
        case .queueSpeech(
            id: let id,
            text: _,
            profileName: _,
            textProfileName: _,
            jobType: .file,
            textContext: _,
            sourceFormat: _
        ),
        .queueBatch(id: let id, profileName: _, items: _):
            _ = try? generationJobStore.markFailed(
                id: id,
                error: error,
                failedAt: dependencies.now()
            )
        default:
            return
        }
    }

    private func makeSpeechJobState(for request: WorkerRequest) async -> PlaybackJob {
        let requestID = request.id
        let op = request.opName
        let text = switch request {
        case .queueSpeech(id: _, text: let text, profileName: _, textProfileName: _, jobType: _, textContext: _, sourceFormat: _):
            text
        default:
            ""
        }
        let profileName = request.profileName ?? "unknown-profile"
        let textProfileName = request.textProfileName
        let textContext = request.textContext
        let sourceFormat = request.sourceFormat
        let textProfile = await normalizerRef.effectiveProfile(named: textProfileName)
        let normalizedText = if let sourceFormat {
            TextForSpeech.normalizeSource(
                text,
                as: sourceFormat,
                context: textContext,
                profile: textProfile
            )
        } else {
            TextForSpeech.normalizeText(
                text,
                context: textContext,
                profile: textProfile
            )
        }
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
            sourceFormat: sourceFormat,
            textFeatures: textFeatures,
            textSections: textSections,
            stream: stream,
            continuation: continuation!
        )
    }

    }
}
