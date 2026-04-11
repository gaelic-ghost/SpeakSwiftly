import Foundation
import TextForSpeech

// MARK: - Worker Runtime Lifecycle

extension SpeakSwiftly.Runtime {
    private static func makeDefaultNormalizer(
        persistenceURL: URL,
        dependencies: WorkerDependencies
    ) -> SpeakSwiftly.Normalizer {
        do {
            return try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
        } catch {
            let archiveURL = quarantinedTextProfileArchiveURL(for: persistenceURL)

            if dependencies.fileManager.fileExists(atPath: persistenceURL.path) {
                do {
                    try dependencies.fileManager.moveItem(at: persistenceURL, to: archiveURL)
                    dependencies.writeStderr(
                        "SpeakSwiftly could not load persisted text profiles from '\(persistenceURL.path)'. The unreadable archive was moved to '\(archiveURL.path)', and SpeakSwiftly will continue with a fresh text-profile state. \(error.localizedDescription)\n"
                    )

                    return try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
                } catch {
                    dependencies.writeStderr(
                        "SpeakSwiftly could not recover the unreadable text-profile archive at '\(persistenceURL.path)'. SpeakSwiftly will continue without that archive. \(error.localizedDescription)\n"
                    )
                }
            } else {
                dependencies.writeStderr(
                    "SpeakSwiftly could not initialize text-profile persistence at '\(persistenceURL.path)'. SpeakSwiftly will continue without that archive. \(error.localizedDescription)\n"
                )
            }

            let recoveryURL = persistenceURL
                .deletingLastPathComponent()
                .appending(path: "text-profiles.recovery.\(UUID().uuidString).json")

            return try! SpeakSwiftly.Normalizer(persistenceURL: recoveryURL)
        }
    }

    private static func quarantinedTextProfileArchiveURL(for persistenceURL: URL) -> URL {
        persistenceURL
            .deletingPathExtension()
            .appendingPathExtension("invalid-\(Int(Date().timeIntervalSince1970)).json")
    }

    // MARK: - Lifecycle

    static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil
    ) async -> SpeakSwiftly.Runtime {
        let dependencies = WorkerDependencies.live()
        let environment = ProcessInfo.processInfo.environment
        let persistedConfiguration = resolvedPersistedConfiguration(
            dependencies: dependencies,
            environment: environment
        )
        let configuredSpeechBackend = resolvedSpeechBackend(
            environment: environment,
            configuration: configuration
                ?? persistedConfiguration
        )
        let configuredQwenConditioningStrategy = resolvedQwenConditioningStrategy(
            configuration: configuration
                ?? persistedConfiguration
        )
        let profileStore = ProfileStore(
            rootURL: ProfileStore.defaultRootURL(
                fileManager: dependencies.fileManager,
                overridePath: environment[Environment.profileRootOverride]
            ),
            fileManager: dependencies.fileManager
        )
        let generatedFileStore = GeneratedFileStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true)
        )
        let generationJobStore = GenerationJobStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true)
        )
        let textProfilesURL = profileStore.rootURL.appending(path: ProfileStore.textProfilesFileName)
        let normalizer = configuration?.textNormalizer
            ?? makeDefaultNormalizer(
                persistenceURL: textProfilesURL,
                dependencies: dependencies
            )
        let playbackController = PlaybackController(driver: await dependencies.makePlaybackController())

        let runtime = SpeakSwiftly.Runtime(
            dependencies: dependencies,
            speechBackend: configuredSpeechBackend,
            qwenConditioningStrategy: configuredQwenConditioningStrategy,
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
        environment: [String: String],
        configuration: SpeakSwiftly.Configuration?
    ) -> SpeakSwiftly.SpeechBackend {
        if let configuration {
            return configuration.speechBackend
        }

        if let environmentBackend = SpeakSwiftly.SpeechBackend.configured(in: environment) {
            return environmentBackend
        }

        return .qwen3
    }

    static func resolvedSpeechBackend(
        dependencies _: WorkerDependencies,
        environment: [String: String],
        configuration: SpeakSwiftly.Configuration?
    ) -> SpeakSwiftly.SpeechBackend {
        resolvedSpeechBackend(
            environment: environment,
            configuration: configuration
        )
    }

    static func resolvedQwenConditioningStrategy(
        configuration: SpeakSwiftly.Configuration?
    ) -> SpeakSwiftly.QwenConditioningStrategy {
        configuration?.qwenConditioningStrategy ?? .legacyRaw
    }

    private static func resolvedPersistedConfiguration(
        dependencies: WorkerDependencies,
        environment: [String: String]
    ) -> SpeakSwiftly.Configuration? {
        do {
            return try SpeakSwiftly.Configuration.loadDefault(
                fileManager: dependencies.fileManager,
                profileRootOverride: environment[Environment.profileRootOverride]
            )
        } catch {
            let configurationPath = SpeakSwiftly.Configuration.defaultPersistenceURL(
                fileManager: dependencies.fileManager,
                profileRootOverride: environment[Environment.profileRootOverride]
            ).path
            let message = "SpeakSwiftly could not load persisted runtime configuration from '\(configurationPath)'. Falling back to the default runtime configuration. \(error.localizedDescription)\n"
            dependencies.writeStderr(message)
            return nil
        }
    }

    func installPlaybackHooks() async {
        await playbackController.bind(
            PlaybackHooks(
                handleEvent: { [weak self] event, job in
                    await self?.handlePlaybackEvent(event, for: job)
                },
                handleEnvironmentEvent: { [weak self] event, activeRequest in
                    await self?.handlePlaybackEnvironmentEvent(event, activeRequest: activeRequest)
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

    public func statusEvents() -> AsyncStream<SpeakSwiftly.StatusEvent> {
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
        ensureRequestBroker(for: request)
        let handle = makeRequestHandle(for: request)
        await submitRequest(request)
        return handle
    }

    public func start() {
        guard preloadTask == nil else { return }
        startResidentPreload()
    }

    func startResidentPreload() {
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
            await emitFailure(id: id, error: workerError)
            return
        } catch {
            let id = bestEffortID(from: line)
            let workerError = WorkerError(
                code: .internalError,
                message: "The request could not be decoded due to an unexpected internal error. \(error.localizedDescription)"
            )
            failRequestStream(for: id, error: workerError)
            await emitFailure(
                id: id,
                error: workerError
            )
            return
        }

        ensureRequestBroker(for: request)

        if isShuttingDown {
            let workerError = WorkerError(
                code: .workerShuttingDown,
                message: "Request '\(request.id)' was rejected because the SpeakSwiftly worker is shutting down."
            )
            failRequestStream(for: request.id, error: workerError)
            await emitFailure(
                id: request.id,
                error: workerError
            )
            return
        }

        if request.isImmediateControlOperation {
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
            await emitFailure(id: request.id, error: workerError)
            return
        }

        if request.requiresPlayback, await playbackController.jobCount() >= maxAcceptedSpeechJobs {
            let workerError = WorkerError(
                code: .invalidRequest,
                message: "Request '\(request.id)' was rejected because the live speech queue is already holding \(maxAcceptedSpeechJobs) accepted jobs. Wait for playback to drain or clear queued work before adding more."
            )
            failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        }

        let queuedGenerationJob: SpeakSwiftly.GenerationJob?
        do {
            queuedGenerationJob = try createQueuedGenerationJobIfNeeded(for: request)
        } catch let workerError as WorkerError {
            failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        } catch {
            let workerError = WorkerError(
                code: .filesystemError,
                message: "Request '\(request.id)' could not create a persisted generation job record before queueing generation work. \(error.localizedDescription)"
            )
            failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        }
        let job = await generationController.enqueue(request)
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
            lastQueuedGenerationParkReason[request.id] = GenerationParkReason(rawValue: queuedEvent.reason.rawValue)
            await logRequestEvent(
                "request_queued",
                requestID: request.id,
                op: request.opName,
                profileName: request.profileName,
                queueDepth: await generationQueueDepth(),
                details: [
                    "park_reason": .string(queuedEvent.reason.rawValue),
                    "queue_position": .int(queuedEvent.queuePosition)
                ]
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
}
