import Foundation
import TextForSpeech

// MARK: - Worker Runtime Lifecycle

extension SpeakSwiftly.Runtime {
    // MARK: - Lifecycle

    func installPlaybackHooks() async {
        await playbackController.bind(
            PlaybackHooks(
                handleEvent: { [weak self] event, job in
                    await self?.handlePlaybackEvent(event, for: job)
                },
                handleEnvironmentEvent: { [weak self] event, activeRequest in
                    await self?.handlePlaybackEnvironmentEvent(event, activeRequest: activeRequest)
                },
                logEngineReady: { [weak self] job, sampleRate in
                    await self?.logPlaybackEngineReady(for: job, sampleRate: sampleRate)
                },
                logFinished: { [weak self] job, playbackSummary, sampleRate in
                    await self?.emitProgress(id: job.id, stage: .playbackFinished)
                    await self?.logPlaybackFinished(for: job, playbackSummary: playbackSummary, sampleRate: sampleRate)
                },
                completeJob: { [weak self] job, result in
                    await self?.completePlaybackJob(job, result: result)
                },
                resumeQueue: { [weak self] in
                    guard let self else { return }

                    try? await startNextGenerationIfPossible()
                    await playbackController.startNextIfPossible()
                },
            ),
        )
    }

    func runtimeUpdates() -> AsyncStream<SpeakSwiftly.RuntimeUpdate> {
        let subscriptionID = UUID()
        let latestUpdate = runtimeObservationBroker.latestUpdate ?? currentStatusSnapshot()?.runtimeUpdate(
            sequence: runtimeObservationBroker.sequence,
            date: dependencies.now(),
        )

        return AsyncStream { continuation in
            runtimeObservationBroker.subscribe(id: subscriptionID, continuation: continuation)
            if let latestUpdate {
                continuation.yield(latestUpdate)
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
                ],
            )

            do {
                try profileStore.ensureRootExists()
                let residentModels = try await dependencies.loadResidentModels(targetSpeechBackend)
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }

                residentState = .ready(residentModels)
                await emitStatus(.residentModelReady)
                await logEvent(
                    "resident_model_preload_ready",
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ].merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
                )
                try await startNextGenerationIfPossible()
                await playbackController.startNextIfPossible()
            } catch is CancellationError {
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }
                guard !isShuttingDown else { return }

                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload was cancelled before \(preloadModelRepos.joined(separator: ", ")) finished loading for the '\(targetSpeechBackend.rawValue)' backend.",
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ],
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
                    ],
                )
                await emitStatus(.residentModelFailed)
                await failQueuedRequests(with: workerError)
            } catch {
                guard shouldApplyResidentPreloadResult(token: preloadToken, backend: targetSpeechBackend) else { return }

                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Resident model preload failed while loading \(preloadModelRepos.joined(separator: ", ")) for the '\(targetSpeechBackend.rawValue)' backend. \(error.localizedDescription)",
                )
                residentState = .failed(workerError)
                await logError(
                    workerError.message,
                    details: [
                        "speech_backend": .string(targetSpeechBackend.rawValue),
                        "model_repos": .string(preloadModelRepos.joined(separator: ",")),
                        "duration_ms": .int(elapsedMS(since: preloadStartedAt)),
                    ],
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
                .resolvingRuntimeDefaultVoiceProfile(defaultVoiceProfileName)
        } catch let workerError as WorkerError {
            let id = bestEffortID(from: line)
            await failRequestStream(for: id, error: workerError)
            await emitFailure(id: id, error: workerError)
            return
        } catch {
            let id = bestEffortID(from: line)
            let workerError = WorkerError(
                code: .internalError,
                message: "The request could not be decoded due to an unexpected internal error. \(error.localizedDescription)",
            )
            await failRequestStream(for: id, error: workerError)
            await emitFailure(
                id: id,
                error: workerError,
            )
            return
        }

        ensureRequestBroker(for: request)

        if isShuttingDown {
            let workerError = WorkerError(
                code: .workerShuttingDown,
                message: "Request '\(request.id)' was rejected because the SpeakSwiftly worker is shutting down.",
            )
            await failRequestStream(for: request.id, error: workerError)
            await emitFailure(
                id: request.id,
                error: workerError,
            )
            return
        }

        if request.isImmediateControlOperation {
            await logRequestEvent(
                "request_accepted",
                requestID: request.id,
                op: request.opName,
                profileName: request.voiceProfile,
                queueDepth: generationQueueDepth(),
            )
            await emitStarted(for: request)
            await yieldRequestEvent(.started(WorkerStartedEvent(id: request.id, kind: request.requestKind)), for: request.id)
            await logRequestEvent(
                "request_started",
                requestID: request.id,
                op: request.opName,
                profileName: request.voiceProfile,
                queueDepth: generationQueueDepth(),
            )
            Task {
                await self.processImmediateControlRequest(request)
            }
            return
        }

        if case let .failed(error) = residentState, request.requiresResidentModels {
            let workerError = WorkerError(
                code: error.code,
                message: "Request '\(request.id)' cannot start because the resident model state is failed. Queue `reload_models` or `set_speech_backend` first, then retry the generation request.",
            )
            await failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        }

        if request.requiresPlayback, await playbackController.jobCount() >= maxAcceptedSpeechJobs {
            let workerError = WorkerError(
                code: .invalidRequest,
                message: "Request '\(request.id)' was rejected because the live speech queue is already holding \(maxAcceptedSpeechJobs) accepted jobs. Wait for playback to drain or clear queued work before adding more.",
            )
            await failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        }

        let queuedGenerationJob: SpeakSwiftly.GenerationJob?
        do {
            queuedGenerationJob = try createQueuedGenerationJobIfNeeded(for: request)
        } catch let workerError as WorkerError {
            await failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        } catch {
            let workerError = WorkerError(
                code: .filesystemError,
                message: "Request '\(request.id)' could not create a persisted generation job record before queueing generation work. \(error.localizedDescription)",
            )
            await failRequestStream(for: request.id, error: workerError)
            await emitFailure(id: request.id, error: workerError)
            return
        }
        let job = await generationController.enqueue(
            request,
            readiness: request.requiresPlayback ? .preparing : .ready,
        )
        await publishGenerateUpdate()
        await logRequestEvent(
            "request_accepted",
            requestID: request.id,
            op: request.opName,
            profileName: request.voiceProfile,
            queueDepth: generationQueueDepth(),
        )
        if let queuedEvent = await makeQueuedEvent(for: job) {
            await emit(queuedEvent)
            await yieldRequestEvent(.queued(queuedEvent), for: request.id)
            lastQueuedGenerationParkReason[request.id] = GenerationParkReason(rawValue: queuedEvent.reason.rawValue)
            await logRequestEvent(
                "request_queued",
                requestID: request.id,
                op: request.opName,
                profileName: request.voiceProfile,
                queueDepth: generationQueueDepth(),
                details: [
                    "park_reason": .string(queuedEvent.reason.rawValue),
                    "queue_position": .int(queuedEvent.queuePosition),
                ],
            )
        }
        if request.acknowledgesEnqueueImmediately {
            let acknowledgement = SpeakSwiftly.RequestAcknowledgement(
                id: request.id,
                kind: request.requestKind,
                generationJob: queuedGenerationJob,
            )
            await yieldRequestEvent(.acknowledged(acknowledgement), for: request.id)
            await logRequestEvent(
                "request_enqueue_acknowledged",
                requestID: request.id,
                op: request.opName,
                profileName: request.voiceProfile,
                queueDepth: generationQueueDepth(),
            )
            await emit(WorkerSuccessResponse(id: request.id, generationJob: queuedGenerationJob))
        }
        if request.requiresPlayback {
            let speechJob: LiveSpeechRequestState
            do {
                speechJob = try await makeSpeechJobState(for: request)
            } catch let workerError as WorkerError {
                guard await generationController.cancel(requestID: request.id) != nil else { return }

                await failRequestStream(for: request.id, error: workerError)
                await emitFailure(id: request.id, error: workerError)
                return
            } catch {
                let workerError = WorkerError(
                    code: .modelGenerationFailed,
                    message: "Request '\(request.id)' could not normalize text before queueing live playback. \(error.localizedDescription)",
                )
                guard await generationController.cancel(requestID: request.id) != nil else { return }

                await failRequestStream(for: request.id, error: workerError)
                await emitFailure(id: request.id, error: workerError)
                return
            }
            await playbackController.enqueue(speechJob)
            await publishPlaybackUpdate()
            guard await generationController.markReady(token: job.token) != nil else {
                _ = await playbackController.discard(requestID: request.id)
                return
            }
        }
        try? await startNextGenerationIfPossible()
        await playbackController.startNextIfPossible()
    }
}
