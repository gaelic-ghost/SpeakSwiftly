import Foundation

extension SpeakSwiftly.Runtime {
    // MARK: - Playback Events

    func handlePlaybackEvent(_ event: PlaybackEvent, for speechRequest: LiveSpeechRequestState) async {
        let id = speechRequest.id
        let op = speechRequest.op
        let profileName = speechRequest.profileName

        switch event {
            case .firstChunk:
                await emitProgress(id: id, stage: .bufferingAudio)
                await logRequestEvent("playback_first_chunk", requestID: id, op: op, profileName: profileName)
            case let .prerollReady(startupBufferedAudioMS, thresholds):
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
                    ],
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
                    .merging(textFeatureDetails(speechRequest.textFeatures), uniquingKeysWith: { _, new in new })
                    .merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
                )
                try? await startNextGenerationIfPossible()
            case let .queueDepthLow(queuedAudioMS):
                await logRequestEvent(
                    "playback_queue_depth_low",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: ["queued_audio_ms": .int(queuedAudioMS)],
                )
            case let .rebufferStarted(queuedAudioMS, thresholds):
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
                    .merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
                )
            case let .rebufferResumed(bufferedAudioMS, thresholds):
                await logRequestEvent(
                    "playback_rebuffer_resumed",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "buffered_audio_ms": .int(bufferedAudioMS),
                        "resume_buffer_target_ms": .int(thresholds.resumeBufferTargetMS),
                    ]
                    .merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
                )
                try? await startNextGenerationIfPossible()
            case let .chunkGapWarning(gapMS, chunkIndex):
                await logRequestEvent(
                    "playback_chunk_gap_warning",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "gap_ms": .int(gapMS),
                        "chunk_index": .int(chunkIndex),
                    ],
                )
            case let .scheduleGapWarning(gapMS, bufferIndex, queuedAudioMS):
                await logRequestEvent(
                    "playback_schedule_gap_warning",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "gap_ms": .int(gapMS),
                        "buffer_index": .int(bufferIndex),
                        "queued_audio_ms": .int(queuedAudioMS),
                    ],
                )
            case let .rebufferThrashWarning(rebufferEventCount, windowMS):
                await logRequestEvent(
                    "playback_rebuffer_thrash_warning",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "rebuffer_event_count": .int(rebufferEventCount),
                        "window_ms": .int(windowMS),
                    ],
                )
            case let .outputDeviceChanged(previousDevice, currentDevice):
                await logRequestEvent(
                    "playback_output_device_changed",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: [
                        "previous_device": .string(previousDevice ?? "unknown"),
                        "current_device": .string(currentDevice ?? "unknown"),
                    ],
                )
            case let .engineConfigurationChanged(engineIsRunning):
                await logRequestEvent(
                    "playback_engine_configuration_changed",
                    requestID: id,
                    op: op,
                    profileName: profileName,
                    details: ["engine_is_running": .bool(engineIsRunning)],
                )
            case let .bufferShapeSummary(
            maxBoundaryDiscontinuity,
            maxLeadingAbsAmplitude,
            maxTrailingAbsAmplitude,
            fadeInChunkCount,
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
                    ],
                )
            case let .trace(trace):
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
                    details: details,
                )
            case .starved:
                await logRequestEvent("playback_starved", requestID: id, op: op, profileName: profileName)
        }
    }

    func handlePlaybackEnvironmentEvent(
        _ event: PlaybackEnvironmentEvent,
        activeRequest: ActiveWorkerRequestSummary?,
    ) async {
        let requestID = activeRequest?.id
        let op = activeRequest?.op
        let profileName = activeRequest?.profileName

        switch event {
            case let .outputDeviceObserved(currentDevice):
                await logEvent(
                    "playback_output_device_observed",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "current_device": .string(currentDevice ?? "unknown"),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
            case let .outputDeviceChanged(previousDevice, currentDevice):
                await logEvent(
                    "playback_output_device_changed",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "previous_device": .string(previousDevice ?? "unknown"),
                        "current_device": .string(currentDevice ?? "unknown"),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
            case let .engineConfigurationChanged(engineIsRunning):
                await logEvent(
                    "playback_engine_configuration_changed",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "engine_is_running": .bool(engineIsRunning),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
            case let .interruptionStateChanged(isInterrupted, shouldResume):
                var details: [String: LogValue] = [
                    "is_interrupted": .bool(isInterrupted),
                    "had_active_request": .bool(activeRequest != nil),
                ]
                if let shouldResume {
                    details["should_resume"] = .bool(shouldResume)
                }
                await logEvent(
                    isInterrupted ? "playback_interruption_began" : "playback_interruption_ended",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: details,
                )
            case let .systemSleepStateChanged(isSleeping):
                await logEvent(
                    isSleeping ? "playback_system_sleep_started" : "playback_system_woke",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "is_sleeping": .bool(isSleeping),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
            case let .screenSleepStateChanged(isSleeping):
                await logEvent(
                    isSleeping ? "playback_screen_sleep_started" : "playback_screen_woke",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "is_sleeping": .bool(isSleeping),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
            case let .sessionActivityChanged(isActive):
                await logEvent(
                    isActive ? "playback_session_became_active" : "playback_session_resigned_active",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "is_active": .bool(isActive),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
            case let .recoveryStateChanged(reason, stage, attempt, currentDevice):
                var details: [String: LogValue] = [
                    "reason": .string(reason),
                    "stage": .string(stage),
                    "current_device": .string(currentDevice ?? "unknown"),
                    "had_active_request": .bool(activeRequest != nil),
                ]
                if let attempt {
                    details["attempt"] = .int(attempt)
                }
                await logEvent(
                    "playback_recovery_state_changed",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: details,
                )
            case let .interJobBoopPlayed(durationMS, frequencyHz, sampleRate):
                await logEvent(
                    "playback_inter_job_boop_played",
                    requestID: requestID,
                    op: op,
                    profileName: profileName,
                    details: [
                        "duration_ms": .int(durationMS),
                        "frequency_hz": .double(frequencyHz),
                        "sample_rate": .double(sampleRate),
                        "had_active_request": .bool(activeRequest != nil),
                    ],
                )
        }
    }
}
