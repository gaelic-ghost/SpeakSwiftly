import Foundation
import TextForSpeech

// MARK: - Runtime Emission

extension SpeakSwiftly.Runtime {
    func completeRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
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
                textProfile: payload.textProfile,
                textProfiles: payload.textProfiles,
                textProfilePath: payload.textProfilePath,
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

    var isResidentReady: Bool {
        if case .ready = residentState {
            return true
        }
        return false
    }

    func generationActiveRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let activeGeneration else { return nil }
        return ActiveWorkerRequestSummary(
            id: activeGeneration.request.id,
            op: activeGeneration.request.opName,
            profileName: activeGeneration.request.profileName
        )
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

    func queueSummaryActiveRequest(for queueType: WorkerQueueType) async -> ActiveWorkerRequestSummary? {
        switch queueType {
        case .generation:
            return generationActiveRequestSummary()
        case .playback:
            return await playbackController.activeRequestSummary()
        }
    }

    func generationQueueDepth() async -> Int {
        (await generationController.queuedJobsOrdered()).count
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
        let status = WorkerStatusEvent(stage: stage)
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
        voiceDescription: String? = nil,
        outputPath: String? = nil,
        referenceAudioPath: String? = nil,
        transcript: String? = nil
    ) async {
        let request = OutgoingWorkerRequest(
            id: id,
            op: op,
            text: text,
            profileName: profileName,
            textProfileName: textProfileName,
            textProfileID: textProfileID,
            textProfileDisplayName: textProfileDisplayName,
            textProfile: textProfile,
            replacements: replacements,
            replacement: replacement,
            replacementID: replacementID,
            cwd: textContext?.cwd,
            repoRoot: textContext?.repoRoot,
            textFormat: textContext?.textFormat,
            nestedSourceFormat: textContext?.nestedSourceFormat,
            sourceFormat: sourceFormat,
            requestID: requestID,
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
        case .createProfile(let id, let profileName, let text, let voiceDescription, let outputPath):
            await submitRequest(
                id: id,
                op: request.opName,
                text: text,
                profileName: profileName,
                voiceDescription: voiceDescription,
                outputPath: outputPath
            )
        case .createClone(let id, let profileName, let referenceAudioPath, let transcript):
            await submitRequest(
                id: id,
                op: request.opName,
                profileName: profileName,
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
        let requestID = request.id
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, any Swift.Error> { continuation in
            requestContinuations[requestID] = continuation
            continuation.onTermination = { _ in
                Task {
                    await self.removeRequestContinuation(for: requestID)
                }
            }
        }

        return WorkerRequestHandle(
            id: requestID,
            operation: request.opName,
            profileName: request.profileName,
            events: events
        )
    }

    func yieldRequestEvent(_ event: WorkerRequestStreamEvent, for requestID: String) {
        requestContinuations[requestID]?.yield(event)
    }

    func finishRequestStream(for requestID: String) {
        requestContinuations[requestID]?.finish()
        requestContinuations.removeValue(forKey: requestID)
    }

    func failRequestStream(for requestID: String, error: WorkerError) {
        requestContinuations[requestID]?.finish(
            throwing: WorkerError(code: error.code, message: error.message)
        )
        requestContinuations.removeValue(forKey: requestID)
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
            return WorkerStatusEvent(stage: .warmingResidentModel)
        case .ready:
            return WorkerStatusEvent(stage: .residentModelReady)
        case .failed:
            return WorkerStatusEvent(stage: .residentModelFailed)
        }
    }

    func removeStatusContinuation(_ id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }

    func removeRequestContinuation(for requestID: String) {
        requestContinuations.removeValue(forKey: requestID)
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
            let data = try logEncoder.encode(logEvent)
            dependencies.writeStderr(String(decoding: data, as: UTF8.self))
        } catch {
            dependencies.writeStderr(
                #"{"event":"worker_error","level":"error","ts":"\#(logTimestampFormatter.string(from: dependencies.now()))","details":{"message":"SpeakSwiftly could not encode a stderr log event.","error":"\#(error.localizedDescription)"}}"#
            )
        }
    }

    func elapsedMS(for requestID: String) -> Int? {
        guard let startedAt = requestAcceptedAt[requestID] else { return nil }
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
