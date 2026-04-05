import Foundation

// MARK: - Playback Runtime Glue

extension SpeakSwiftly.Runtime {
    // MARK: - Queue Management

    func clearQueuedRequests(cancelledByRequestID: String, reason: String) async -> Int {
        let queuedJobs = await generationController.clearQueued()
        let activePlaybackRequestID = await playbackController.activeRequestSummary()?.id
        let protectedRequestIDs = Set([activeGeneration?.request.id, activePlaybackRequestID].compactMap { $0 })
        let waitingPlaybackJobs = await playbackController.clearQueued(excluding: protectedRequestIDs)

        let cancellation = WorkerError(
            code: .requestCancelled,
            message: "Request '\(cancelledByRequestID)' cancelled this work because \(reason)."
        )

        for job in queuedJobs {
            if job.request.isSpeechRequest {
                _ = await playbackController.discard(requestID: job.request.id)
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

        for job in waitingPlaybackJobs {
            job.generationTask?.cancel()
            job.playbackTask?.cancel()
            job.continuation.finish(throwing: cancellation)
            await logError(
                cancellation.message,
                requestID: job.requestID,
                details: ["failure_code": .string(cancellation.code.rawValue)]
            )
            await completePlaybackJob(job, result: .failure(cancellation))
        }

        return queuedJobs.count + waitingPlaybackJobs.count
    }

    func failWaitingPlaybackRequests(with error: WorkerError) async {
        let activePlaybackRequestID = await playbackController.activeRequestSummary()?.id
        let protectedRequestIDs = Set([activeGeneration?.request.id, activePlaybackRequestID].compactMap { $0 })
        let waitingPlaybackJobs = await playbackController.clearQueued(excluding: protectedRequestIDs)

        for job in waitingPlaybackJobs {
            job.generationTask?.cancel()
            job.playbackTask?.cancel()
            job.continuation.finish(throwing: error)
            await completePlaybackJob(job, result: .failure(error))
        }
    }

    func cancelRequestNow(_ targetRequestID: String, cancelledByRequestID: String) async throws -> String {
        let cancellation = WorkerError(
            code: .requestCancelled,
            message: "Request '\(targetRequestID)' was cancelled by control request '\(cancelledByRequestID)'."
        )

        let cancelledGenerationTarget = await generationController.cancel(requestID: targetRequestID)

        if let job = await playbackController.cancel(requestID: targetRequestID) {
            job.continuation.finish(throwing: cancellation)
            await completePlaybackJob(job, result: .failure(cancellation))
            try? await startNextGenerationIfPossible()
            await playbackController.startNextIfPossible()
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

    // MARK: - Playback Completion

    func completePlaybackJob(
        _ job: PlaybackJob,
        result: Result<WorkerSuccessPayload, WorkerError>
    ) async {
        job.generationTask = nil
        job.playbackTask = nil
        requestAcceptedAt.removeValue(forKey: job.requestID)
        let request = WorkerRequest.queueSpeech(
            id: job.requestID,
            text: job.text,
            profileName: job.profileName,
            textProfileName: job.textProfileName,
            jobType: .live,
            textContext: job.textContext
        )
        await completeRequest(request: request, result: result)
    }

    // MARK: - Playback Events

    func handlePlaybackEvent(_ event: PlaybackEvent, for speechJob: PlaybackJob) async {
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
                    "low_water_target_ms": .int(thresholds.lowWaterTargetMS),
                    "resume_buffer_target_ms": .int(thresholds.resumeBufferTargetMS),
                    "startup_buffered_audio_ms": .int(startupBufferedAudioMS),
                ]
                .merging(textFeatureDetails(speechJob.textFeatures), uniquingKeysWith: { _, new in new })
                .merging(memoryDetails(), uniquingKeysWith: { _, new in new })
            )
        case .queueDepthLow(let queuedAudioMS):
            await logRequestEvent(
                "playback_queue_depth_low",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["queued_audio_ms": .int(queuedAudioMS)]
            )
        case .rebufferStarted(let queuedAudioMS, let thresholds):
            await logRequestEvent(
                "playback_rebuffer_started",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "queued_audio_ms": .int(queuedAudioMS),
                    "low_water_target_ms": .int(thresholds.lowWaterTargetMS),
                    "resume_buffer_target_ms": .int(thresholds.resumeBufferTargetMS),
                ]
            )
        case .rebufferResumed(let bufferedAudioMS, let thresholds):
            await logRequestEvent(
                "playback_rebuffer_resumed",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "buffered_audio_ms": .int(bufferedAudioMS),
                    "resume_buffer_target_ms": .int(thresholds.resumeBufferTargetMS),
                ]
            )
        case .chunkGapWarning(let gapMS, let chunkIndex):
            await logRequestEvent(
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
            await logRequestEvent(
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
        case .rebufferThrashWarning(let rebufferEventCount, let windowMS):
            await logRequestEvent(
                "playback_rebuffer_thrash_warning",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "rebuffer_event_count": .int(rebufferEventCount),
                    "window_ms": .int(windowMS),
                ]
            )
        case .outputDeviceChanged(let previousDevice, let currentDevice):
            await logRequestEvent(
                "playback_output_device_changed",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "previous_device": .string(previousDevice ?? "unknown"),
                    "current_device": .string(currentDevice ?? "unknown"),
                ]
            )
        case .engineConfigurationChanged(let engineIsRunning):
            await logRequestEvent(
                "playback_engine_configuration_changed",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["engine_is_running": .bool(engineIsRunning)]
            )
        case .bufferShapeSummary(
            let maxBoundaryDiscontinuity,
            let maxLeadingAbsAmplitude,
            let maxTrailingAbsAmplitude,
            let fadeInChunkCount
        ):
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
            var details = [String: LogValue](minimumCapacity: 8)
            details["name"] = .string(trace.name)
            if let chunkIndex = trace.chunkIndex { details["chunk_index"] = .int(chunkIndex) }
            if let bufferIndex = trace.bufferIndex { details["buffer_index"] = .int(bufferIndex) }
            if let sampleCount = trace.sampleCount { details["sample_count"] = .int(sampleCount) }
            if let durationMS = trace.durationMS { details["duration_ms"] = .int(durationMS) }
            if let queuedAudioBeforeMS = trace.queuedAudioBeforeMS { details["queued_audio_before_ms"] = .int(queuedAudioBeforeMS) }
            if let queuedAudioAfterMS = trace.queuedAudioAfterMS { details["queued_audio_after_ms"] = .int(queuedAudioAfterMS) }
            if let gapMS = trace.gapMS { details["gap_ms"] = .int(gapMS) }
            if let isRebuffering = trace.isRebuffering { details["is_rebuffering"] = .bool(isRebuffering) }
            if let fadeInApplied = trace.fadeInApplied { details["fade_in_applied"] = .bool(fadeInApplied) }
            await logRequestEvent(
                "playback_trace_\(trace.name)",
                requestID: id,
                op: op,
                profileName: profileName,
                details: details
            )
        case .starved:
            await logRequestEvent("playback_starved", requestID: id, op: op, profileName: profileName)
        }
    }
}
