import Foundation
import TextForSpeech

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
                    clearedCount: payload.clearedCount,
                    cancelledRequestID: payload.cancelledRequestID,
                )
                yieldRequestEvent(.completed(SpeakSwiftly.RequestCompletion(success)), for: request.id)
                if !request.acknowledgesEnqueueImmediately || request.emitsTerminalSuccessAfterAcknowledgement {
                    await emit(success)
                }

            case let .failure(error):
                failRequestStream(for: request.id, error: error)
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
            yieldRequestEvent(.queued(queuedEvent), for: job.request.id)
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

    func generationActiveRequestSummaries() -> [ActiveWorkerRequestSummary] {
        activeGenerations.values
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
            queueType: queueType.rawValue,
            activeRequest: queueSummaryActiveRequest(for: queueType),
            activeRequests: queueSummaryActiveRequests(for: queueType),
            queue: queuedRequestSummaries(for: queueType),
        )
    }

    func queueSummaryActiveRequest(for queueType: WorkerQueueType) async -> ActiveWorkerRequestSummary? {
        switch queueType {
            case .generation:
                generationActiveRequestSummaries().first
            case .playback:
                await playbackController.activeRequestSummary()
        }
    }

    func queueSummaryActiveRequests(for queueType: WorkerQueueType) async -> [ActiveWorkerRequestSummary]? {
        switch queueType {
            case .generation:
                let activeRequests = generationActiveRequestSummaries()
                return activeRequests.isEmpty ? nil : activeRequests
            case .playback:
                return nil
        }
    }

    func runtimeOverviewSnapshot() async -> SpeakSwiftly.RuntimeOverview {
        await SpeakSwiftly.RuntimeOverview(
            status: currentStatusSnapshot(),
            speechBackend: speechBackend,
            storage: runtimeStorageSnapshot(),
            generationQueue: queueSnapshot(for: .generation),
            playbackQueue: queueSnapshot(for: .playback),
            playbackState: playbackController.stateSnapshot(),
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
        await emit(WorkerStartedEvent(id: request.id, op: request.opName))
    }

    func emitProgress(id: String, stage: WorkerProgressStage) async {
        let progress = WorkerProgressEvent(id: id, stage: stage)
        await emit(progress)
        yieldRequestEvent(.progress(progress), for: id)
    }

    func emitStatus(_ stage: WorkerStatusStage) async {
        let status = WorkerStatusEvent(
            stage: stage,
            residentState: residentStateSummary,
            speechBackend: speechBackend,
        )
        await emit(status)
        broadcastStatus(status)
    }

    func emitFailure(id: String, error: WorkerError) async {
        await emit(WorkerFailureResponse(id: id, code: error.code, message: error.message))
    }

    func emit(_ value: some Encodable) async {
        do {
            let data = try encoder.encode(value) + Data("\n".utf8)
            try dependencies.writeStdout(data)
        } catch {
            await logError("SpeakSwiftly could not write a JSONL event to stdout. \(error.localizedDescription)")
        }
    }

    func submitRequest(
        id: String,
        op: String,
        artifactID: String? = nil,
        batchID: String? = nil,
        jobID: String? = nil,
        items: [SpeakSwiftly.GenerationJobItem]? = nil,
        text: String? = nil,
        voiceProfile: String? = nil,
        profileName: String? = nil,
        newProfileName: String? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        inputTextContext: SpeakSwiftly.InputTextContext? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        textProfileStyle: TextForSpeech.BuiltInProfileStyle? = nil,
        replacement: TextForSpeech.Replacement? = nil,
        replacementID: String? = nil,
        requestID: String? = nil,
        speechBackend: SpeakSwiftly.SpeechBackend? = nil,
        qwenPreModelTextChunking: Bool? = nil,
        vibe: SpeakSwiftly.Vibe? = nil,
        voiceDescription: String? = nil,
        outputPath: String? = nil,
        cwd: String? = nil,
        referenceAudioPath: String? = nil,
        transcript: String? = nil,
    ) async {
        let request = OutgoingWorkerRequest(
            id: id,
            op: op,
            artifactID: artifactID,
            batchID: batchID,
            jobID: jobID,
            items: items,
            text: text,
            voiceProfile: voiceProfile,
            profileName: profileName,
            newProfileName: newProfileName,
            textProfile: textProfile,
            inputTextContext: inputTextContext,
            requestContext: requestContext,
            textProfileStyle: textProfileStyle,
            replacement: replacement,
            replacementID: replacementID,
            cwd: cwd ?? inputTextContext?.context?.cwd,
            repoRoot: inputTextContext?.context?.repoRoot,
            textFormat: inputTextContext?.context?.textFormat,
            nestedSourceFormat: inputTextContext?.context?.nestedSourceFormat,
            sourceFormat: inputTextContext?.sourceFormat,
            requestID: requestID,
            speechBackend: speechBackend,
            qwenPreModelTextChunking: qwenPreModelTextChunking,
            vibe: vibe,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            referenceAudioPath: referenceAudioPath,
            transcript: transcript,
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
                    message: "SpeakSwiftly could not encode the outgoing '\(op)' request before queueing it. \(error.localizedDescription)",
                ),
            )
        }
    }

    func submitRequest(_ request: WorkerRequest) async {
        switch request {
            case let .queueSpeech(id, text, profileName, textProfileID, _, inputTextContext, requestContext, qwenPreModelTextChunking):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    text: text,
                    voiceProfile: profileName,
                    textProfile: textProfileID,
                    inputTextContext: inputTextContext,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                )
            case let .queueBatch(id, profileName, items):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    items: items,
                    voiceProfile: profileName,
                )
            case let .generatedFile(id, artifactID):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    artifactID: artifactID,
                )
            case let .generatedFiles(id):
                await submitRequest(
                    id: id,
                    op: request.opName,
                )
            case let .overview(id):
                await submitRequest(
                    id: id,
                    op: request.opName,
                )
            case let .generatedBatch(id, batchID):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    batchID: batchID,
                )
            case let .generatedBatches(id):
                await submitRequest(
                    id: id,
                    op: request.opName,
                )
            case let .expireGenerationJob(id, jobID):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    jobID: jobID,
                )
            case let .generationJob(id, jobID):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    jobID: jobID,
                )
            case let .generationJobs(id):
                await submitRequest(
                    id: id,
                    op: request.opName,
                )
            case let .createProfile(id, profileName, text, vibe, voiceDescription, _, _, outputPath, cwd):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    text: text,
                    profileName: profileName,
                    vibe: vibe,
                    voiceDescription: voiceDescription,
                    outputPath: outputPath,
                    cwd: cwd,
                )
            case let .createClone(id, profileName, referenceAudioPath, vibe, transcript, cwd):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    profileName: profileName,
                    vibe: vibe,
                    cwd: cwd,
                    referenceAudioPath: referenceAudioPath,
                    transcript: transcript,
                )
            case let .listProfiles(id):
                await submitRequest(id: id, op: request.opName)
            case let .renameProfile(id, profileName, newProfileName):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    profileName: profileName,
                    newProfileName: newProfileName,
                )
            case let .rerollProfile(id, profileName):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    profileName: profileName,
                )
            case let .removeProfile(id, profileName):
                await submitRequest(id: id, op: request.opName, profileName: profileName)
            case let .textProfileActive(id),
                 let .textProfiles(id),
                 let .activeTextProfileStyle(id),
                 let .textProfileStyleOptions(id),
                 let .textProfilePersistence(id),
                 let .loadTextProfiles(id),
                 let .saveTextProfiles(id),
                 let .factoryResetTextProfiles(id):
                await submitRequest(id: id, op: request.opName)
            case let .textProfile(id, profileID),
                 let .setActiveTextProfile(id, profileID),
                 let .deleteTextProfile(id, profileID),
                 let .resetTextProfile(id, profileID):
                await submitRequest(id: id, op: request.opName, textProfile: profileID)
            case let .textProfileEffective(id):
                await submitRequest(id: id, op: request.opName)
            case let .setActiveTextProfileStyle(id, style):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    textProfileStyle: style,
                )
            case let .createTextProfile(id, profileName):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    profileName: profileName,
                )
            case let .renameTextProfile(id, profileID, profileName):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    newProfileName: profileName,
                    textProfile: profileID,
                )
            case let .addTextReplacement(id, replacement, profileID),
                 let .replaceTextReplacement(id, replacement, profileID):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    textProfile: profileID,
                    replacement: replacement,
                )
            case let .removeTextReplacement(id, replacementID, profileID):
                await submitRequest(
                    id: id,
                    op: request.opName,
                    textProfile: profileID,
                    replacementID: replacementID,
                )
            case let .listQueue(id, _):
                await submitRequest(id: id, op: request.opName)
            case let .status(id):
                await submitRequest(id: id, op: request.opName)
            case let .switchSpeechBackend(id, speechBackend):
                await submitRequest(id: id, op: request.opName, speechBackend: speechBackend)
            case let .reloadModels(id):
                await submitRequest(id: id, op: request.opName)
            case let .unloadModels(id):
                await submitRequest(id: id, op: request.opName)
            case let .playback(id, _):
                await submitRequest(id: id, op: request.opName)
            case let .clearQueue(id, _):
                await submitRequest(id: id, op: request.opName)
            case let .cancelRequest(id, requestID, _):
                await submitRequest(id: id, op: request.opName, requestID: requestID)
        }
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
