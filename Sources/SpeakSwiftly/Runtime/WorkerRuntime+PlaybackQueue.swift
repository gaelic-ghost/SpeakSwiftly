import Foundation

// MARK: - Runtime Playback Queue

extension SpeakSwiftly.Runtime {
    func clearQueuedRequests(cancelledByRequestID: String, reason: String) async -> Int {
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
                textProfileName: speechJob.textProfileName,
                jobType: .live,
                textContext: speechJob.textContext
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

    func failWaitingPlaybackRequests(with error: WorkerError) async {
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
                textProfileName: speechJob.textProfileName,
                jobType: .live,
                textContext: speechJob.textContext
            )
            await completeRequest(request: request, result: .failure(error))
        }
    }

    func cancelRequestNow(_ targetRequestID: String, cancelledByRequestID: String) async throws -> String {
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

    func removeSpeechJob(requestID: String) -> SpeechJobState? {
        speechJobs.removeValue(forKey: requestID)
    }

    func removePlaybackJob(requestID: String) {
        playbackQueue.removeAll { $0 == requestID }
    }

    func handlePlaybackControl(_ action: PlaybackAction) async -> PlaybackState {
        switch action {
        case .pause:
            return await playbackController.pause()
        case .resume:
            return await playbackController.resume()
        case .state:
            return await playbackController.state()
        }
    }

    func startNextPlaybackIfPossible() async {
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

    func processPlayback(for speechJob: SpeechJobState, sampleRate: Double) async {
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

    func finishPlayback(requestID: String, result: Result<WorkerSuccessPayload, WorkerError>) async {
        guard activePlayback?.requestID == requestID else { return }
        activePlayback = nil
        removePlaybackJob(requestID: requestID)
        if let speechJob = speechJobs[requestID] {
            speechJob.playbackTask = nil
        }
        await completeSpeechRequestIfNeeded(id: requestID, result: result)
        await startNextPlaybackIfPossible()
    }

    func completeSpeechRequestIfNeeded(id: String, result: Result<WorkerSuccessPayload, WorkerError>) async {
        guard let speechJob = removeSpeechJob(requestID: id) else { return }
        speechJob.generationTask = nil
        speechJob.playbackTask = nil
        requestAcceptedAt.removeValue(forKey: id)
        let request = WorkerRequest.queueSpeech(
            id: id,
            text: speechJob.text,
            profileName: speechJob.profileName,
            textProfileName: speechJob.textProfileName,
            jobType: .live,
            textContext: speechJob.textContext
        )
        await completeRequest(request: request, result: result)
    }

    func handlePlaybackEvent(_ event: PlaybackEvent, for speechJob: SpeechJobState) async {
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
            await logRequestEvent(
                "playback_queue_depth_low",
                requestID: id,
                op: op,
                profileName: profileName,
                details: ["queued_audio_ms": .int(queuedAudioMS)]
            )
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
                details: [
                    "gap_ms": .int(gapMS),
                    "buffer_index": .int(bufferIndex),
                    "queued_audio_ms": .int(queuedAudioMS),
                ]
            )
        case .starved:
            await logRequestEvent("playback_starved", requestID: id, op: op, profileName: profileName)
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
            var details = [String: LogValue]()
            if let previousDevice {
                details["previous_device"] = .string(previousDevice)
            }
            if let currentDevice {
                details["current_device"] = .string(currentDevice)
            }
            await logRequestEvent(
                "playback_output_device_changed",
                requestID: id,
                op: op,
                profileName: profileName,
                details: details
            )
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
            await logRequestEvent(
                "playback_trace_\(trace.name)",
                requestID: id,
                op: op,
                profileName: profileName,
                details: details
            )
        }
    }
}
