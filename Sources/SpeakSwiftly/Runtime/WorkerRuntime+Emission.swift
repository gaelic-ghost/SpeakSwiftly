import Foundation
import TextForSpeech

// MARK: - Runtime Emission

extension SpeakSwiftly.Runtime {
    func completeRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        lastQueuedGenerationParkReason.removeValue(forKey: request.id)
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
                textProfilePath: payload.textProfilePath,
                activeRequest: payload.activeRequest,
                activeRequests: payload.activeRequests,
                queue: payload.queue,
                playbackState: payload.playbackState,
                runtimeOverview: payload.runtimeOverview,
                status: payload.status,
                speechBackend: payload.speechBackend,
                clearedCount: payload.clearedCount,
                cancelledRequestID: payload.cancelledRequestID
            )
            yieldRequestEvent(.completed(success), for: request.id)
            if !request.acknowledgesEnqueueImmediately || request.emitsTerminalSuccessAfterAcknowledgement {
                await emit(success)
            }

        case .failure(let error):
            failRequestStream(for: request.id, error: error)
            await logError(
                error.message,
                requestID: request.id,
                details: ["failure_code": .string(error.code.rawValue)]
            )
            await emitFailure(id: request.id, error: error)
        }
    }

    func cancellationError(for id: String) -> WorkerError {
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

    func makeQueuedEvent(for job: GenerationController.Job) async -> WorkerQueuedEvent? {
        let activeJobs = await generationController.activeJobsOrdered()
        let queuedJobs = await generationController.queuedJobsOrdered()
        let playbackSnapshot = await playbackController.concurrencySnapshot()
        let decision = try? evaluateGenerationSchedule(
            activeJobs: activeJobs,
            queuedJobs: queuedJobs,
            playbackSnapshot: playbackSnapshot
        )
        guard let reason = decision?.parkReasons[job.token] else {
            return nil
        }

        let queuePosition = await generationController.waitingPosition(
            for: job.token,
            residentReady: isResidentReady
        ) ?? 1
        return WorkerQueuedEvent(
            id: job.request.id,
            reason: queuedReason(for: reason),
            queuePosition: queuePosition
        )
    }

    func syncQueuedGenerationParkReasons(
        queuedJobs: [GenerationController.Job],
        parkReasons: [UUID: GenerationParkReason]
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
                residentReady: isResidentReady
            ) ?? 1
            let queuedEvent = WorkerQueuedEvent(
                id: job.request.id,
                reason: queuedReason(for: reason),
                queuePosition: queuePosition
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
                    op: $0.opName,
                    profileName: $0.profileName
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
                    op: job.request.opName,
                    profileName: job.request.profileName,
                    queuePosition: offset + 1
                )
            }
        case .playback:
            return await playbackController.queuedRequestSummaries()
        }
    }

    func queueSnapshot(for queueType: WorkerQueueType) async -> SpeakSwiftly.QueueSnapshot {
        SpeakSwiftly.QueueSnapshot(
            queueType: queueType.rawValue,
            activeRequest: await queueSummaryActiveRequest(for: queueType),
            activeRequests: await queueSummaryActiveRequests(for: queueType),
            queue: await queuedRequestSummaries(for: queueType)
        )
    }

    func queueSummaryActiveRequest(for queueType: WorkerQueueType) async -> ActiveWorkerRequestSummary? {
        switch queueType {
        case .generation:
            return generationActiveRequestSummaries().first
        case .playback:
            return await playbackController.activeRequestSummary()
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
        SpeakSwiftly.RuntimeOverview(
            status: currentStatusSnapshot(),
            speechBackend: speechBackend,
            generationQueue: await queueSnapshot(for: .generation),
            playbackQueue: await queueSnapshot(for: .playback),
            playbackState: await playbackController.stateSnapshot()
        )
    }

    func generationQueueDepth() async -> Int {
        (await generationController.queuedJobsOrdered()).count
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
        case .waitingForMarvisGenerationLane:
            .waitingForMarvisGenerationLane
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
            speechBackend: speechBackend
        )
        await emit(status)
        broadcastStatus(status)
    }

    func emitFailure(id: String, error: WorkerError) async {
        await emit(WorkerFailureResponse(id: id, code: error.code, message: error.message))
    }

    func emit<T: Encodable>(_ value: T) async {
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
        profileName: String? = nil,
        textProfileName: String? = nil,
        textProfileID: String? = nil,
        textProfileDisplayName: String? = nil,
        textProfile: TextForSpeech.Profile? = nil,
        replacements: [TextForSpeech.Replacement]? = nil,
        replacement: TextForSpeech.Replacement? = nil,
        replacementID: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        requestID: String? = nil,
        speechBackend: SpeakSwiftly.SpeechBackend? = nil,
        vibe: SpeakSwiftly.Vibe? = nil,
        voiceDescription: String? = nil,
        outputPath: String? = nil,
        cwd: String? = nil,
        referenceAudioPath: String? = nil,
        transcript: String? = nil
    ) async {
        let request = OutgoingWorkerRequest(
            id: id,
            op: op,
            artifactID: artifactID,
            batchID: batchID,
            jobID: jobID,
            items: items,
            text: text,
            profileName: profileName,
            textProfileName: textProfileName,
            textProfileID: textProfileID,
            textProfileDisplayName: textProfileDisplayName,
            textProfile: textProfile,
            replacements: replacements,
            replacement: replacement,
            replacementID: replacementID,
            cwd: cwd ?? textContext?.cwd,
            repoRoot: textContext?.repoRoot,
            textFormat: textContext?.textFormat,
            nestedSourceFormat: textContext?.nestedSourceFormat,
            sourceFormat: sourceFormat,
            requestID: requestID,
            speechBackend: speechBackend,
            vibe: vibe,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            referenceAudioPath: referenceAudioPath,
            transcript: transcript
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

    func submitRequest(_ request: WorkerRequest) async {
        switch request {
        case .queueSpeech(let id, let text, let profileName, let textProfileName, _, let textContext, let sourceFormat):
            await submitRequest(
                id: id,
                op: request.opName,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                textContext: textContext,
                sourceFormat: sourceFormat
            )
        case .queueBatch(let id, let profileName, let items):
            await submitRequest(
                id: id,
                op: request.opName,
                items: items,
                profileName: profileName
            )
        case .generatedFile(let id, let artifactID):
            await submitRequest(
                id: id,
                op: request.opName,
                artifactID: artifactID
            )
        case .generatedFiles(let id):
            await submitRequest(
                id: id,
                op: request.opName
            )
        case .overview(let id):
            await submitRequest(
                id: id,
                op: request.opName
            )
        case .generatedBatch(let id, let batchID):
            await submitRequest(
                id: id,
                op: request.opName,
                batchID: batchID
            )
        case .generatedBatches(let id):
            await submitRequest(
                id: id,
                op: request.opName
            )
        case .expireGenerationJob(let id, let jobID):
            await submitRequest(
                id: id,
                op: request.opName,
                jobID: jobID
            )
        case .generationJob(let id, let jobID):
            await submitRequest(
                id: id,
                op: request.opName,
                jobID: jobID
            )
        case .generationJobs(let id):
            await submitRequest(
                id: id,
                op: request.opName
            )
        case .createProfile(let id, let profileName, let text, let vibe, let voiceDescription, let outputPath, let cwd):
            await submitRequest(
                id: id,
                op: request.opName,
                text: text,
                profileName: profileName,
                vibe: vibe,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: cwd
            )
        case .createClone(let id, let profileName, let referenceAudioPath, let vibe, let transcript, let cwd):
            await submitRequest(
                id: id,
                op: request.opName,
                profileName: profileName,
                vibe: vibe,
                cwd: cwd,
                referenceAudioPath: referenceAudioPath,
                transcript: transcript
            )
        case .listProfiles(let id):
            await submitRequest(id: id, op: request.opName)
        case .removeProfile(let id, let profileName):
            await submitRequest(id: id, op: request.opName, profileName: profileName)
        case .textProfileActive(let id),
             .textProfileBase(let id),
             .textProfiles(let id),
             .textProfilePersistence(let id),
             .loadTextProfiles(let id),
             .saveTextProfiles(let id),
             .resetTextProfile(let id):
            await submitRequest(id: id, op: request.opName)
        case .textProfile(let id, let name),
             .removeTextProfile(let id, let name):
            await submitRequest(id: id, op: request.opName, textProfileName: name)
        case .textProfileEffective(let id, let name):
            await submitRequest(id: id, op: request.opName, textProfileName: name)
        case .createTextProfile(let id, let profileID, let profileName, let replacements):
            await submitRequest(
                id: id,
                op: request.opName,
                textProfileID: profileID,
                textProfileDisplayName: profileName,
                replacements: replacements
            )
        case .storeTextProfile(let id, let profile),
             .useTextProfile(let id, let profile):
            await submitRequest(
                id: id,
                op: request.opName,
                textProfile: profile
            )
        case .addTextReplacement(let id, let replacement, let profileName),
             .replaceTextReplacement(let id, let replacement, let profileName):
            await submitRequest(
                id: id,
                op: request.opName,
                textProfileName: profileName,
                replacement: replacement
            )
        case .removeTextReplacement(let id, let replacementID, let profileName):
            await submitRequest(
                id: id,
                op: request.opName,
                textProfileName: profileName,
                replacementID: replacementID
            )
        case .listQueue(let id, _):
            await submitRequest(id: id, op: request.opName)
        case .status(let id):
            await submitRequest(id: id, op: request.opName)
        case .switchSpeechBackend(let id, let speechBackend):
            await submitRequest(id: id, op: request.opName, speechBackend: speechBackend)
        case .reloadModels(let id):
            await submitRequest(id: id, op: request.opName)
        case .unloadModels(let id):
            await submitRequest(id: id, op: request.opName)
        case .playback(let id, _):
            await submitRequest(id: id, op: request.opName)
        case .clearQueue(let id):
            await submitRequest(id: id, op: request.opName)
        case .cancelRequest(let id, let requestID):
            await submitRequest(id: id, op: request.opName, requestID: requestID)
        }
    }

    func logPlaybackFinished(
        for speechJob: PlaybackJob,
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
        details.merge(textFeatureDetails(speechJob.textFeatures), uniquingKeysWith: { _, new in new })
        details["section_count"] = .int(speechJob.textSections.count)
        details.merge(memoryDetails(), uniquingKeysWith: { _, new in new })
        await logRequestEvent(
            "playback_finished",
            requestID: id,
            op: op,
            profileName: profileName,
            details: details
        )

        let totalDurationMS = Int((Double(playbackSummary.sampleCount) / sampleRate * 1_000).rounded())
        let sectionWindows = TextForSpeech.sectionWindows(
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

    func makeRequestHandle(for request: WorkerRequest) -> WorkerRequestHandle {
        return WorkerRequestHandle(
            id: request.id,
            operation: request.opName,
            profileName: request.profileName,
            events: makeLegacyRequestEventStream(for: request.id)
        )
    }

    func ensureRequestBroker(for request: WorkerRequest) {
        if requestBrokers[request.id]?.isTerminal == true {
            terminalRequestBrokerOrder.removeAll { $0 == request.id }
            requestBrokers.removeValue(forKey: request.id)
        }
        guard requestBrokers[request.id] == nil else { return }

        let acceptedAt = dependencies.now()
        requestBrokers[request.id] = RequestBroker(
            id: request.id,
            operation: request.opName,
            profileName: request.profileName,
            acceptedAt: acceptedAt,
            lastUpdatedAt: acceptedAt
        )
    }

    func requestSnapshot(for requestID: String) -> SpeakSwiftly.RequestSnapshot? {
        requestBrokers[requestID]?.snapshot()
    }

    func makeRequestUpdateStream(
        for requestID: String,
        replayBuffered: Bool = true
    ) -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error> {
        guard let broker = requestBrokers[requestID] else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        let subscriberID = UUID()
        let replayUpdates = replayBuffered ? broker.replayUpdates : []
        let isTerminal = broker.isTerminal

        return AsyncThrowingStream { continuation in
            replayUpdates.forEach { continuation.yield($0) }

            guard !isTerminal, requestBrokers[requestID] != nil else {
                continuation.finish()
                return
            }

            requestBrokers[requestID]?.subscriberContinuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeRequestUpdateSubscriber(subscriberID, for: requestID)
                }
            }
        }
    }

    func makeLegacyRequestEventStream(
        for requestID: String
    ) -> AsyncThrowingStream<WorkerRequestStreamEvent, any Swift.Error> {
        let updates = makeRequestUpdateStream(for: requestID, replayBuffered: false)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in updates {
                        switch update.state {
                        case .queued(let event):
                            continuation.yield(.queued(event))
                        case .acknowledged(let success):
                            continuation.yield(.acknowledged(success))
                        case .started(let event):
                            continuation.yield(.started(event))
                        case .progress(let event):
                            continuation.yield(.progress(event))
                        case .completed(let success):
                            continuation.yield(.completed(success))
                        case .failed(let failure), .cancelled(let failure):
                            continuation.finish(
                                throwing: WorkerError(code: failure.code, message: failure.message)
                            )
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func yieldRequestEvent(_ event: WorkerRequestStreamEvent, for requestID: String) {
        let state: SpeakSwiftly.RequestState
        switch event {
        case .queued(let queuedEvent):
            state = .queued(queuedEvent)
        case .acknowledged(let success):
            state = .acknowledged(success)
        case .started(let startedEvent):
            state = .started(startedEvent)
        case .progress(let progressEvent):
            state = .progress(progressEvent)
        case .completed(let success):
            state = .completed(success)
        }

        recordRequestState(
            state,
            for: requestID,
            terminal: {
                if case .completed = state { return true }
                return false
            }()
        )
    }

    func failRequestStream(for requestID: String, error: WorkerError) {
        let failure = WorkerFailureResponse(
            id: requestID,
            code: error.code,
            message: error.message
        )
        let state: SpeakSwiftly.RequestState =
            error.code == .requestCancelled ? .cancelled(failure) : .failed(failure)
        recordRequestState(state, for: requestID, terminal: true)
    }

    func recordRequestState(
        _ state: SpeakSwiftly.RequestState,
        for requestID: String,
        terminal: Bool
    ) {
        guard var broker = requestBrokers[requestID] else { return }

        let update = broker.record(
            state: state,
            date: dependencies.now(),
            maxReplayUpdates: RequestObservationConfiguration.maxReplayUpdates
        )
        let continuations = Array(broker.subscriberContinuations.values)

        if terminal {
            broker.isTerminal = true
            broker.subscriberContinuations.removeAll()
        }

        requestBrokers[requestID] = broker

        continuations.forEach { continuation in
            continuation.yield(update)
            if terminal {
                continuation.finish()
            }
        }

        if terminal {
            retainTerminalRequestBrokerIfNeeded(for: requestID)
        }
    }

    func retainTerminalRequestBrokerIfNeeded(for requestID: String) {
        guard requestBrokers[requestID]?.isTerminal == true else { return }
        terminalRequestBrokerOrder.removeAll { $0 == requestID }
        terminalRequestBrokerOrder.append(requestID)

        while terminalRequestBrokerOrder.count > RequestObservationConfiguration.maxRetainedTerminalRequests {
            let evictedRequestID = terminalRequestBrokerOrder.removeFirst()
            requestBrokers.removeValue(forKey: evictedRequestID)
        }
    }

    func removeRequestUpdateSubscriber(_ subscriberID: UUID, for requestID: String) {
        requestBrokers[requestID]?.subscriberContinuations.removeValue(forKey: subscriberID)
    }

    func broadcastStatus(_ status: WorkerStatusEvent) {
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }

    func currentStatusSnapshot() -> WorkerStatusEvent? {
        switch residentState {
        case .warming:
            guard preloadTask != nil else { return nil }
            return WorkerStatusEvent(
                stage: .warmingResidentModel,
                residentState: residentStateSummary,
                speechBackend: speechBackend
            )
        case .ready:
            return WorkerStatusEvent(
                stage: .residentModelReady,
                residentState: residentStateSummary,
                speechBackend: speechBackend
            )
        case .unloaded:
            return WorkerStatusEvent(
                stage: .residentModelsUnloaded,
                residentState: residentStateSummary,
                speechBackend: speechBackend
            )
        case .failed:
            return WorkerStatusEvent(
                stage: .residentModelFailed,
                residentState: residentStateSummary,
                speechBackend: speechBackend
            )
        }
    }

    var residentStateSummary: SpeakSwiftly.ResidentModelState {
        switch residentState {
        case .warming:
            .warming
        case .ready:
            .ready
        case .unloaded:
            .unloaded
        case .failed:
            .failed
        }
    }

    func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }

    func logError(
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

    func logRequestEvent(
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

    func memoryDetails() -> [String: LogValue] {
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
        if let processUserCPUTimeNS = snapshot.processUserCPUTimeNS {
            details["process_user_cpu_time_ns"] = .int(processUserCPUTimeNS)
        }
        if let processSystemCPUTimeNS = snapshot.processSystemCPUTimeNS {
            details["process_system_cpu_time_ns"] = .int(processSystemCPUTimeNS)
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

    func logEvent(
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
            dependencies.writeStderr(try WorkerStructuredLogSupport.encode(logEvent))
        } catch {
            dependencies.writeStderr(WorkerStructuredLogSupport.encodingFailureLine(
                timestamp: logTimestampFormatter.string(from: dependencies.now()),
                errorDescription: error.localizedDescription
            ))
        }
    }

    func elapsedMS(for requestID: String) -> Int? {
        guard let startedAt = requestBrokers[requestID]?.acceptedAt else { return nil }
        return elapsedMS(since: startedAt)
    }

    func elapsedMS(since startedAt: Date) -> Int {
        Int((dependencies.now().timeIntervalSince(startedAt) * 1_000).rounded())
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
