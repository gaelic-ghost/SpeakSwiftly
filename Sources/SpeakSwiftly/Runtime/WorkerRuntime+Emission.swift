import Foundation

// MARK: - Runtime Emission

extension SpeakSwiftly.Runtime {
    func completeRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        lastQueuedGenerationParkReason.removeValue(forKey: request.id)
        switch result {
            case let .success(payload):
                await logRequestEvent(
                    "request_succeeded",
                    requestID: payload.id,
                    op: nil,
                    profileName: payload.profileName,
                )
                let success = WorkerSuccessResponse(
                    id: payload.id,
                    generatedFile: payload.generatedFile,
                    generatedFiles: payload.generatedFiles,
                    generatedBatch: payload.generatedBatch,
                    generatedBatches: payload.generatedBatches,
                    generationJob: payload.generationJob,
                    generationJobs: payload.generationJobs,
                    profileName: payload.profileName,
                    profilePath: payload.profilePath,
                    profiles: payload.profiles,
                    textProfile: payload.textProfile,
                    textProfiles: payload.textProfiles,
                    textProfileStyleOptions: payload.textProfileStyleOptions,
                    textProfileStyle: payload.textProfileStyle,
                    textProfilePath: payload.textProfilePath,
                    activeRequest: payload.activeRequest,
                    activeRequests: payload.activeRequests,
                    queue: payload.queue,
                    playbackState: payload.playbackState,
                    runtimeOverview: payload.runtimeOverview,
                    status: payload.status,
                    speechBackend: payload.speechBackend,
                    defaultVoiceProfile: payload.defaultVoiceProfile,
                    clearedCount: payload.clearedCount,
                    cancelledRequestID: payload.cancelledRequestID,
                )
                await yieldRequestEvent(.completed(SpeakSwiftly.RequestCompletion(success)), for: request.id)
                if !request.acknowledgesEnqueueImmediately || request.emitsTerminalSuccessAfterAcknowledgement {
                    await emit(success)
                }

            case let .failure(error):
                await failRequestStream(for: request.id, error: error)
                await logError(
                    error.message,
                    requestID: request.id,
                    details: ["failure_code": .string(error.code.rawValue)],
                )
                await emitFailure(id: request.id, error: error)
        }
    }

    func cancellationError(for id: String) -> WorkerError {
        if isShuttingDown {
            return WorkerError(
                code: .requestCancelled,
                message: "Request '\(id)' was cancelled because the SpeakSwiftly worker is shutting down.",
            )
        }

        return WorkerError(
            code: .requestCancelled,
            message: "Request '\(id)' was cancelled before it could complete.",
        )
    }

    func makeQueuedEvent(for job: SpeechGenerationController.Job) async -> WorkerQueuedEvent? {
        let activeJobs = await generationController.activeJobsOrdered()
        let queuedJobs = await generationController.queuedJobsOrdered()
        let playbackAdmission = await playbackController.generationAdmissionSnapshot()
        let decision = try? evaluateGenerationSchedule(
            activeJobs: activeJobs,
            queuedJobs: queuedJobs,
            playbackAdmission: playbackAdmission,
        )
        guard let reason = decision?.parkReasons[job.token] else {
            return nil
        }

        let queuePosition = await generationController.waitingPosition(
            for: job.token,
            residentReady: isResidentReady,
        ) ?? 1
        return WorkerQueuedEvent(
            id: job.request.id,
            reason: queuedReason(for: reason),
            queuePosition: queuePosition,
        )
    }

    func syncQueuedGenerationParkReasons(
        queuedJobs: [SpeechGenerationController.Job],
        parkReasons: [UUID: GenerationParkReason],
    ) async {
        var queuedRequestIDs = Set<String>()

        for job in queuedJobs {
            queuedRequestIDs.insert(job.request.id)
            guard let reason = parkReasons[job.token] else {
                lastQueuedGenerationParkReason.removeValue(forKey: job.request.id)
                continue
            }
            guard lastQueuedGenerationParkReason[job.request.id] != reason else {
                continue
            }

            let queuePosition = await generationController.waitingPosition(
                for: job.token,
                residentReady: isResidentReady,
            ) ?? 1
            let queuedEvent = WorkerQueuedEvent(
                id: job.request.id,
                reason: queuedReason(for: reason),
                queuePosition: queuePosition,
            )
            await emit(queuedEvent)
            await yieldRequestEvent(.queued(queuedEvent), for: job.request.id)
            lastQueuedGenerationParkReason[job.request.id] = reason
        }

        let staleRequestIDs = Set(lastQueuedGenerationParkReason.keys).subtracting(queuedRequestIDs)
        for requestID in staleRequestIDs {
            lastQueuedGenerationParkReason.removeValue(forKey: requestID)
        }
    }

    var isResidentReady: Bool {
        if case .ready = residentState {
            return true
        }
        return false
    }

    func generationActiveRequestSummaries() async -> [ActiveWorkerRequestSummary] {
        await generationController.activeJobsOrdered()
            .map(\.request)
            .sorted { $0.id < $1.id }
            .map {
                ActiveWorkerRequestSummary(
                    id: $0.id,
                    kind: $0.requestKind,
                    voiceProfile: $0.voiceProfile,
                    requestContext: $0.requestContext,
                )
            }
    }

    func queuedRequestSummaries(for queueType: WorkerQueueType) async -> [QueuedWorkerRequestSummary] {
        switch queueType {
            case .generation:
                let jobs = await generationController.queuedJobsOrdered()
                return jobs.enumerated().map { offset, job in
                    QueuedWorkerRequestSummary(
                        id: job.request.id,
                        kind: job.request.requestKind,
                        voiceProfile: job.request.voiceProfile,
                        requestContext: job.request.requestContext,
                        queuePosition: offset + 1,
                    )
                }
            case .playback:
                return await playbackController.queuedRequestSummaries()
        }
    }

    func queueSnapshot(for queueType: WorkerQueueType) async -> SpeakSwiftly.QueueSnapshot {
        await SpeakSwiftly.QueueSnapshot(
            queueType: queueType,
            activeRequests: queueSummaryActiveRequests(for: queueType),
            queue: queuedRequestSummaries(for: queueType),
        )
    }

    func queueSummaryActiveRequest(for queueType: WorkerQueueType) async -> ActiveWorkerRequestSummary? {
        switch queueType {
            case .generation:
                await generationActiveRequestSummaries().first
            case .playback:
                await playbackController.activeRequestSummary()
        }
    }

    func queueSummaryActiveRequests(for queueType: WorkerQueueType) async -> [ActiveWorkerRequestSummary] {
        switch queueType {
            case .generation:
                await generationActiveRequestSummaries()
            case .playback:
                await queueSummaryActiveRequest(for: .playback).map { [$0] } ?? []
        }
    }

    func runtimeSnapshot() -> SpeakSwiftly.RuntimeSnapshot {
        SpeakSwiftly.RuntimeSnapshot(
            sequence: runtimeObservationBroker.sequence,
            capturedAt: dependencies.now(),
            state: currentRuntimeState,
            speechBackend: speechBackend,
            residentState: residentStateSummary,
            defaultVoiceProfile: defaultVoiceProfileName,
            storage: runtimeStorageSnapshot(),
        )
    }

    func runtimeOverviewSnapshot() async -> SpeakSwiftly.WorkerRuntimeOverview {
        await SpeakSwiftly.WorkerRuntimeOverview(
            status: currentStatusSnapshot(),
            speechBackend: speechBackend,
            storage: runtimeStorageSnapshot(),
            generationQueue: queueSnapshot(for: .generation),
            playbackQueue: queueSnapshot(for: .playback),
            playbackState: playbackController.workerStateSnapshot(),
            defaultVoiceProfile: defaultVoiceProfileName,
        )
    }

    var currentRuntimeState: SpeakSwiftly.RuntimeState {
        switch residentState {
            case .warming:
                .warmingResidentModel
            case .ready:
                .residentModelReady
            case .unloaded:
                .residentModelsUnloaded
            case .failed:
                .residentModelFailed
        }
    }

    func generateSnapshot() async -> SpeakSwiftly.GenerateSnapshot {
        let activeRequests = await generationActiveRequestSummaries()
        let queuedRequests = await queuedRequestSummaries(for: .generation)
        return SpeakSwiftly.GenerateSnapshot(
            sequence: generateObservationBroker.sequence,
            capturedAt: dependencies.now(),
            state: currentGenerateState(activeRequests: activeRequests, queuedRequests: queuedRequests),
            activeRequests: activeRequests,
            queuedRequests: queuedRequests,
        )
    }

    func playbackSnapshot() async -> SpeakSwiftly.PlaybackSnapshot {
        await playbackController.stateSnapshot(
            sequence: playbackObservationBroker.sequence,
            capturedAt: dependencies.now(),
        )
    }

    func runtimeStorageSnapshot() -> SpeakSwiftly.RuntimeStorageSnapshot {
        let stateRootURL = profileStore.stateRootURL.standardizedFileURL
        return SpeakSwiftly.RuntimeStorageSnapshot(
            stateRootPath: stateRootURL.path,
            profileStoreRootPath: profileStore.rootURL.standardizedFileURL.path,
            configurationPath: stateRootURL
                .appendingPathComponent(ProfileStore.configurationFileName, isDirectory: false)
                .path,
            textProfilesPath: stateRootURL
                .appendingPathComponent(ProfileStore.textProfilesFileName, isDirectory: false)
                .path,
            generatedFilesRootPath: generatedFileStore.rootURL.standardizedFileURL.path,
            generationJobsRootPath: generationJobStore.rootURL.standardizedFileURL.path,
        )
    }

    func generationQueueDepth() async -> Int {
        await (generationController.queuedJobsOrdered()).count
    }

    private func queuedReason(for parkReason: SpeakSwiftly.Runtime.GenerationParkReason) -> WorkerQueuedReason {
        switch parkReason {
            case .waitingForResidentModel:
                .waitingForResidentModel
            case .waitingForResidentModels:
                .waitingForResidentModels
            case .waitingForActiveRequest:
                .waitingForActiveRequest
            case .waitingForPlaybackStability:
                .waitingForPlaybackStability
        }
    }

    func emitStarted(for request: WorkerRequest) async {
        await emit(WorkerStartedEvent(id: request.id, kind: request.requestKind))
    }

    func emitProgress(id: String, stage: WorkerProgressStage) async {
        let progress = WorkerProgressEvent(id: id, stage: stage)
        await emit(progress)
        await yieldRequestEvent(.progress(progress), for: id)
    }

    func emitStatus(_ stage: WorkerStatusStage) async {
        let status = WorkerStatusEvent(
            stage: stage,
            residentState: residentStateSummary,
            speechBackend: speechBackend,
        )
        await emit(status)
        let update = recordRuntimeUpdate(state: stage)
        broadcastRuntimeUpdate(update)
    }

    func recordRuntimeUpdate(state: SpeakSwiftly.RuntimeState) -> SpeakSwiftly.RuntimeUpdate {
        runtimeObservationBroker.makeUpdate { sequence in
            SpeakSwiftly.RuntimeUpdate(
                sequence: sequence,
                date: dependencies.now(),
                state: state,
                event: .stateChanged(state),
            )
        }
    }

    func currentGenerateState(
        activeRequests: [ActiveWorkerRequestSummary],
        queuedRequests: [QueuedWorkerRequestSummary],
    ) -> SpeakSwiftly.GenerateState {
        if !activeRequests.isEmpty {
            return .running
        }

        if let firstQueued = queuedRequests.first,
           let parkReason = lastQueuedGenerationParkReason[firstQueued.id],
           let blockReason = SpeakSwiftly.GenerateBlockReason(rawValue: parkReason.rawValue) {
            return .blocked(blockReason)
        }

        return queuedRequests.isEmpty ? .idle : .blocked(.waitingForActiveRequest)
    }

    package func workerOutputEvents() -> AsyncStream<SpeakSwiftly.WorkerOutputEvent> {
        let subscriptionID = UUID()

        return AsyncStream { continuation in
            workerOutputContinuations[subscriptionID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeWorkerOutputContinuation(subscriptionID)
                }
            }
        }
    }

    package func setWorkerJSONLEmissionEnabled(_ enabled: Bool) {
        emitsWorkerJSONL = enabled
    }

    func removeWorkerOutputContinuation(_ id: UUID) {
        workerOutputContinuations.removeValue(forKey: id)
    }

    func emit(_ event: WorkerStatusEvent) async {
        await emitOutput(.status(event))
    }

    func emit(_ event: WorkerQueuedEvent) async {
        await emitOutput(.queued(event))
    }

    func emit(_ event: WorkerStartedEvent) async {
        await emitOutput(.started(event))
    }

    func emit(_ event: WorkerProgressEvent) async {
        await emitOutput(.progress(event))
    }

    func emit(_ response: WorkerSuccessResponse) async {
        await emitOutput(.success(response))
    }

    func emitFailure(id: String, error: WorkerError) async {
        await emitOutput(.failure(WorkerFailureResponse(id: id, code: error.code, message: error.message)))
    }

    func emitOutput(_ event: SpeakSwiftly.WorkerOutputEvent) async {
        for continuation in workerOutputContinuations.values {
            continuation.yield(event)
        }

        guard emitsWorkerJSONL else { return }

        await writeWorkerJSONL(event)
    }

    func writeWorkerJSONL(_ event: SpeakSwiftly.WorkerOutputEvent) async {
        switch event {
            case let .status(status):
                await writeWorkerJSONL(status)
            case let .queued(queued):
                await writeWorkerJSONL(queued)
            case let .started(started):
                await writeWorkerJSONL(started)
            case let .progress(progress):
                await writeWorkerJSONL(progress)
            case let .success(success):
                await writeWorkerJSONL(success)
            case let .failure(failure):
                await writeWorkerJSONL(failure)
        }
    }

    func writeWorkerJSONL(_ value: some Encodable) async {
        do {
            let data = try encoder.encode(value) + Data("\n".utf8)
            try dependencies.writeStdout(data)
        } catch {
            await logError("SpeakSwiftly could not write a JSONL event to stdout. \(error.localizedDescription)")
        }
    }

    func submitRequest(_ request: WorkerRequest) async {
        await submitDecodedRequest(request)
    }

    func bestEffortID(from line: String) -> String {
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
