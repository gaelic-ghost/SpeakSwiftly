import Foundation

// MARK: - Event Logging

extension SpeakSwiftly.Runtime {
    func logQwenLiveChunkPlan(for speechRequest: LiveSpeechRequestState) async {
        guard let plannedChunks = speechRequest.normalizedLiveChunks, !plannedChunks.isEmpty else { return }

        await logRequestEvent(
            "qwen_live_chunk_plan",
            requestID: speechRequest.id,
            op: speechRequest.op,
            profileName: speechRequest.profileName,
            details: [
                "chunk_count": .int(plannedChunks.count),
                "streaming_cadence_profile": .string(speechRequest.residentStreamingCadenceProfile.rawValue),
                "streaming_interval": .double(speechRequest.residentStreamingInterval),
            ],
        )

        for chunk in plannedChunks {
            var details = qwenLiveChunkDetails(
                chunk,
                totalChunkCount: plannedChunks.count,
            )
            details.merge(qwenLiveChunkTextDetails(chunk), uniquingKeysWith: { _, new in new })
            await logRequestEvent(
                "qwen_live_chunk_planned",
                requestID: speechRequest.id,
                op: speechRequest.op,
                profileName: speechRequest.profileName,
                details: details,
            )
        }
    }

    func logQwenLiveChunkStarted(
        requestID: String,
        op: String?,
        profileName: String,
        chunk: LiveSpeechTextChunk,
        totalChunkCount: Int,
        streamingInterval: Double,
    ) async {
        var details = qwenLiveChunkDetails(chunk, totalChunkCount: totalChunkCount)
        details["streaming_interval"] = .double(streamingInterval)
        details.merge(qwenLiveChunkTextDetails(chunk), uniquingKeysWith: { _, new in new })
        await logRequestEvent(
            "qwen_live_chunk_started",
            requestID: requestID,
            op: op,
            profileName: profileName,
            details: details,
        )
    }

    func logQwenLiveChunkFirstAudio(
        requestID: String,
        op: String?,
        profileName: String,
        chunk: LiveSpeechTextChunk,
        totalChunkCount: Int,
        timeToFirstAudioMS: Int,
        sampleCount: Int,
    ) async {
        var details = qwenLiveChunkDetails(chunk, totalChunkCount: totalChunkCount)
        details["time_to_first_audio_ms"] = .int(timeToFirstAudioMS)
        details["first_audio_sample_count"] = .int(sampleCount)
        await logRequestEvent(
            "qwen_live_chunk_first_audio",
            requestID: requestID,
            op: op,
            profileName: profileName,
            details: details,
        )
    }

    func logQwenLiveChunkFinished(
        requestID: String,
        op: String?,
        profileName: String,
        chunk: LiveSpeechTextChunk,
        totalChunkCount: Int,
        elapsedMS: Int,
        audioChunkCount: Int,
        sampleCount: Int,
    ) async {
        var details = qwenLiveChunkDetails(chunk, totalChunkCount: totalChunkCount)
        details["elapsed_ms"] = .int(elapsedMS)
        details["audio_chunk_count"] = .int(audioChunkCount)
        details["sample_count"] = .int(sampleCount)
        await logRequestEvent(
            "qwen_live_chunk_finished",
            requestID: requestID,
            op: op,
            profileName: profileName,
            details: details,
        )
    }

    func logPlaybackEngineReady(
        for speechRequest: LiveSpeechRequestState,
        sampleRate: Double,
    ) async {
        await logRequestEvent(
            "playback_engine_ready",
            requestID: speechRequest.id,
            op: speechRequest.op,
            profileName: speechRequest.profileName,
            details: [
                "sample_rate": .int(Int(sampleRate.rounded())),
            ].merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
        )
    }

    func logPlaybackFinished(
        for speechRequest: LiveSpeechRequestState,
        playbackSummary: PlaybackSummary,
        sampleRate: Double,
    ) async {
        let id = speechRequest.id
        let op = speechRequest.op
        let profileName = speechRequest.profileName

        var details: [String: LogValue] = [
            "text_complexity_class": .string(playbackSummary.thresholds.complexityClass.rawValue),
            "chunk_count": .int(playbackSummary.chunkCount),
            "sample_count": .int(playbackSummary.sampleCount),
            "streaming_cadence_profile": .string(speechRequest.residentStreamingCadenceProfile.rawValue),
            "streaming_interval": .double(speechRequest.residentStreamingInterval),
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
        details.merge(textFeatureDetails(speechRequest.textFeatures), uniquingKeysWith: { _, new in new })
        details["section_count"] = .int(speechRequest.textSections.count)
        details.merge(memoryDetails(), uniquingKeysWith: { _, new in new })
        await logRequestEvent(
            "playback_finished",
            requestID: id,
            op: op,
            profileName: profileName,
            details: details,
        )

        let totalDurationMS = Int((Double(playbackSummary.sampleCount) / sampleRate * 1000).rounded())
        let sectionWindows = SpeakSwiftly.DeepTrace.sectionWindows(
            originalText: speechRequest.text,
            totalDurationMS: totalDurationMS,
            totalChunkCount: playbackSummary.chunkCount,
        )
        for window in sectionWindows {
            await logRequestEvent(
                "playback_section_window",
                requestID: id,
                op: op,
                profileName: profileName,
                details: textSectionWindowDetails(window),
            )
        }
    }

    func logError(
        _ message: String,
        requestID: String? = nil,
        op: String? = nil,
        profileName: String? = nil,
        details: [String: LogValue]? = nil,
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
            details: mergedDetails,
        )
    }

    func logRequestEvent(
        _ event: String,
        requestID: String,
        op: String?,
        profileName: String? = nil,
        queueDepth: Int? = nil,
        details: [String: LogValue]? = nil,
    ) async {
        await logEvent(
            event,
            requestID: requestID,
            op: op,
            profileName: profileName,
            queueDepth: queueDepth,
            elapsedMS: elapsedMS(for: requestID),
            details: details,
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
        details: [String: LogValue]? = nil,
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
            details: details,
        )

        do {
            try dependencies.writeStderr(WorkerStructuredLogSupport.encode(logEvent))
        } catch {
            dependencies.writeStderr(WorkerStructuredLogSupport.encodingFailureLine(
                timestamp: logTimestampFormatter.string(from: dependencies.now()),
                errorDescription: error.localizedDescription,
            ))
        }
    }

    func elapsedMS(for requestID: String) -> Int? {
        guard let startedAt = requestBrokers[requestID]?.acceptedAt else { return nil }

        return elapsedMS(since: startedAt)
    }

    func elapsedMS(since startedAt: Date) -> Int {
        Int((dependencies.now().timeIntervalSince(startedAt) * 1000).rounded())
    }

    private func qwenLiveChunkDetails(
        _ chunk: LiveSpeechTextChunk,
        totalChunkCount: Int,
    ) -> [String: LogValue] {
        [
            "chunk_index": .int(chunk.index),
            "chunk_total": .int(totalChunkCount),
            "segmentation": .string(chunk.segmentation.rawValue),
            "word_count": .int(chunk.wordCount),
            "character_count": .int(chunk.text.count),
            "sentence_count": .int(LiveSpeechChunkPlanner.sentenceCount(in: chunk.text)),
            "paragraph_count": .int(LiveSpeechChunkPlanner.paragraphCount(in: chunk.text)),
        ]
    }

    private func qwenLiveChunkTextDetails(
        _ chunk: LiveSpeechTextChunk,
    ) -> [String: LogValue] {
        [
            "text": .string(chunk.text),
            "text_visible_breaks": .string(
                chunk.text
                    .replacingOccurrences(of: "\r\n", with: "\\r\\n")
                    .replacingOccurrences(of: "\n", with: "\\n"),
            ),
        ]
    }
}
