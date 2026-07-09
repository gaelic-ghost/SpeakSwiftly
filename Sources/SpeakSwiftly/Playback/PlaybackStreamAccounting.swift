import Foundation

struct PlaybackRecordedChunk {
    let chunkIndex: Int
    let sampleCount: Int
    let durationMS: Int
    let interChunkGapMS: Int?
    let qualityObservation: GeneratedAudioQualityObservation
    let qualityWarning: GeneratedAudioQualityWarning?
    let emittedFirstChunk: Bool
    let fadeInApplied: Bool
}

struct PlaybackStreamAccounting {
    let sampleRate: Double
    let startedAt: Date

    private(set) var chunkCount = 0
    private(set) var sampleCount = 0
    private(set) var startupBufferedAudioMS: Int?
    private(set) var timeToFirstChunkMS: Int?
    private(set) var timeToPrerollReadyMS: Int?
    private(set) var minQueuedAudioMS: Int?
    private(set) var maxQueuedAudioMS: Int?
    private(set) var queueDepthTotalMS = 0
    private(set) var queueDepthSampleCount = 0
    private(set) var maxInterChunkGapMS: Int?
    private(set) var interChunkGapTotalMS = 0
    private(set) var interChunkGapCount = 0
    private(set) var maxBoundaryDiscontinuity: Double?
    private(set) var maxLeadingAbsAmplitude: Double?
    private(set) var maxTrailingAbsAmplitude: Double?
    private(set) var fadeInChunkCount = 0

    private var lastChunkReceivedAt: Date?
    private var previousTrailingSample: Float?
    private var generatedAudioQualityMonitor: GeneratedAudioQualityMonitor
    private var emittedGenerationQualityWarningReasons = Set<GeneratedAudioQualityWarningReason>()

    var hasReceivedFirstChunk: Bool {
        chunkCount > 0
    }

    var hasEmittedPrerollReady: Bool {
        timeToPrerollReadyMS != nil
    }

    var bufferShapeSummaryEvent: PlaybackEvent? {
        guard let maxBoundaryDiscontinuity, let maxLeadingAbsAmplitude, let maxTrailingAbsAmplitude else { return nil }

        return .bufferShapeSummary(
            maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
            maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
            maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
            fadeInChunkCount: fadeInChunkCount,
        )
    }

    init(sampleRate: Double, startedAt: Date = Date()) {
        self.sampleRate = sampleRate
        self.startedAt = startedAt
        generatedAudioQualityMonitor = GeneratedAudioQualityMonitor(sampleRate: sampleRate)
    }

    mutating func recordQueueDepth(queuedAudioMS: Int) {
        minQueuedAudioMS = min(minQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
        maxQueuedAudioMS = max(maxQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
        queueDepthTotalMS += queuedAudioMS
        queueDepthSampleCount += 1
    }

    mutating func recordGeneratedChunk(
        samples: [Float],
        thresholds: PlaybackAdaptiveThresholds,
        queuedAudioBeforeMS: Int?,
        queuedAudioAfterMS: Int?,
        isRebuffering: Bool,
        fadeInApplied: Bool,
        now: Date = Date(),
    ) -> PlaybackRecordedChunk {
        chunkCount += 1
        sampleCount += samples.count

        let chunkDurationMS = durationMS(sampleCount: samples.count)
        let interChunkGapMS: Int?
        if let lastChunkReceivedAt {
            let gapMS = Int((now.timeIntervalSince(lastChunkReceivedAt) * 1000).rounded())
            interChunkGapMS = gapMS
            maxInterChunkGapMS = max(maxInterChunkGapMS ?? gapMS, gapMS)
            interChunkGapTotalMS += gapMS
            interChunkGapCount += 1
        } else {
            interChunkGapMS = nil
        }
        lastChunkReceivedAt = now

        let qualityObservation = generatedAudioQualityMonitor.observe(
            samples: samples,
            chunkIndex: chunkCount,
        )
        let qualityWarning = generatedAudioQualityMonitor
            .warning(for: qualityObservation)
            .flatMap { warning in
                emittedGenerationQualityWarningReasons.insert(warning.reason).inserted ? warning : nil
            }

        if timeToFirstChunkMS == nil {
            timeToFirstChunkMS = Int((now.timeIntervalSince(startedAt) * 1000).rounded())
        }

        return PlaybackRecordedChunk(
            chunkIndex: chunkCount,
            sampleCount: samples.count,
            durationMS: chunkDurationMS,
            interChunkGapMS: interChunkGapMS,
            qualityObservation: qualityObservation,
            qualityWarning: qualityWarning,
            emittedFirstChunk: chunkCount == 1,
            fadeInApplied: fadeInApplied,
        )
    }

    mutating func recordBufferShape(
        firstSample: Float,
        lastSample: Float,
        fadeInApplied: Bool,
    ) {
        let leadingAbs = Double(abs(firstSample))
        let trailingAbs = Double(abs(lastSample))
        maxLeadingAbsAmplitude = max(maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
        maxTrailingAbsAmplitude = max(maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
        if fadeInApplied {
            fadeInChunkCount += 1
        }
        if let previousTrailingSample {
            let jump = Double(abs(firstSample - previousTrailingSample))
            maxBoundaryDiscontinuity = max(maxBoundaryDiscontinuity ?? jump, jump)
        }
        previousTrailingSample = lastSample
    }

    mutating func markPrerollReady(
        bufferedAudioMS: Int,
        now: Date = Date(),
    ) -> Int {
        startupBufferedAudioMS = bufferedAudioMS
        timeToPrerollReadyMS = Int((now.timeIntervalSince(startedAt) * 1000).rounded())
        return bufferedAudioMS
    }

    func chunkGapWarning(for chunk: PlaybackRecordedChunk, thresholds: PlaybackAdaptiveThresholds) -> PlaybackEvent? {
        guard let gapMS = chunk.interChunkGapMS, gapMS >= thresholds.chunkGapWarningMS else { return nil }

        return .chunkGapWarning(gapMS: gapMS, chunkIndex: chunk.chunkIndex)
    }

    func generationQualityTrace(
        for chunk: PlaybackRecordedChunk,
        queuedAudioBeforeMS: Int?,
        queuedAudioAfterMS: Int?,
        isRebuffering: Bool,
    ) -> PlaybackTraceEvent {
        PlaybackTraceEvent(
            name: "generation_quality_chunk",
            chunkIndex: chunk.chunkIndex,
            bufferIndex: nil,
            sampleCount: chunk.sampleCount,
            durationMS: chunk.durationMS,
            queuedAudioBeforeMS: queuedAudioBeforeMS,
            queuedAudioAfterMS: queuedAudioAfterMS,
            gapMS: chunk.interChunkGapMS,
            isRebuffering: isRebuffering,
            fadeInApplied: chunk.fadeInApplied,
            generatedAudioQuality: chunk.qualityObservation,
        )
    }

    func chunkReceivedTrace(
        for chunk: PlaybackRecordedChunk,
        queuedAudioBeforeMS: Int?,
        queuedAudioAfterMS: Int?,
        isRebuffering: Bool,
    ) -> PlaybackTraceEvent {
        PlaybackTraceEvent(
            name: "chunk_received",
            chunkIndex: chunk.chunkIndex,
            bufferIndex: nil,
            sampleCount: chunk.sampleCount,
            durationMS: chunk.durationMS,
            queuedAudioBeforeMS: queuedAudioBeforeMS,
            queuedAudioAfterMS: queuedAudioAfterMS,
            gapMS: chunk.interChunkGapMS,
            isRebuffering: isRebuffering,
            fadeInApplied: chunk.fadeInApplied,
            generatedAudioQuality: nil,
        )
    }

    func summary(
        thresholds: PlaybackAdaptiveThresholds,
        timeFromPrerollReadyToDrainMS: Int? = nil,
        minQueuedAudioMS: Int? = nil,
        maxQueuedAudioMS: Int? = nil,
        avgQueuedAudioMS: Int? = nil,
        queueDepthSampleCount: Int? = nil,
        rebufferEventCount: Int,
        rebufferTotalDurationMS: Int,
        longestRebufferDurationMS: Int,
        starvationEventCount: Int,
        scheduleCallbackCount: Int,
        playedBackCallbackCount: Int,
        maxInterChunkGapMS: Int? = nil,
        avgInterChunkGapMS: Int? = nil,
        maxScheduleGapMS: Int?,
        avgScheduleGapMS: Int?,
        maxBoundaryDiscontinuity: Double? = nil,
        maxLeadingAbsAmplitude: Double? = nil,
        maxTrailingAbsAmplitude: Double? = nil,
        fadeInChunkCount: Int? = nil,
    ) -> PlaybackSummary {
        let resolvedTimeFromPrerollReadyToDrainMS: Int? = if let timeFromPrerollReadyToDrainMS {
            timeFromPrerollReadyToDrainMS
        } else if let timeToPrerollReadyMS {
            max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
        } else {
            nil
        }
        let resolvedQueueDepthSampleCount = queueDepthSampleCount ?? self.queueDepthSampleCount
        let resolvedAvgQueuedAudioMS = avgQueuedAudioMS
            ?? (self.queueDepthSampleCount == 0 ? nil : queueDepthTotalMS / self.queueDepthSampleCount)

        return PlaybackSummary(
            thresholds: thresholds,
            chunkCount: chunkCount,
            sampleCount: sampleCount,
            startupBufferedAudioMS: startupBufferedAudioMS,
            timeToFirstChunkMS: timeToFirstChunkMS,
            timeToPrerollReadyMS: timeToPrerollReadyMS,
            timeFromPrerollReadyToDrainMS: resolvedTimeFromPrerollReadyToDrainMS,
            minQueuedAudioMS: minQueuedAudioMS ?? self.minQueuedAudioMS,
            maxQueuedAudioMS: maxQueuedAudioMS ?? self.maxQueuedAudioMS,
            avgQueuedAudioMS: resolvedAvgQueuedAudioMS,
            queueDepthSampleCount: resolvedQueueDepthSampleCount,
            rebufferEventCount: rebufferEventCount,
            rebufferTotalDurationMS: rebufferTotalDurationMS,
            longestRebufferDurationMS: longestRebufferDurationMS,
            starvationEventCount: starvationEventCount,
            scheduleCallbackCount: scheduleCallbackCount,
            playedBackCallbackCount: playedBackCallbackCount,
            maxInterChunkGapMS: maxInterChunkGapMS ?? self.maxInterChunkGapMS,
            avgInterChunkGapMS: avgInterChunkGapMS
                ?? (interChunkGapCount == 0 ? nil : interChunkGapTotalMS / interChunkGapCount),
            maxScheduleGapMS: maxScheduleGapMS,
            avgScheduleGapMS: avgScheduleGapMS,
            maxBoundaryDiscontinuity: maxBoundaryDiscontinuity ?? self.maxBoundaryDiscontinuity,
            maxLeadingAbsAmplitude: maxLeadingAbsAmplitude ?? self.maxLeadingAbsAmplitude,
            maxTrailingAbsAmplitude: maxTrailingAbsAmplitude ?? self.maxTrailingAbsAmplitude,
            fadeInChunkCount: fadeInChunkCount ?? self.fadeInChunkCount,
        )
    }

    func durationMS(sampleCount: Int) -> Int {
        Int((Double(sampleCount) / sampleRate * 1000).rounded())
    }
}

extension PlaybackTraceEvent {
    static func generationChunkFinished(
        chunkIndex: Int,
        queuedAudioMS: Int,
        isRebuffering: Bool,
    ) -> PlaybackTraceEvent {
        PlaybackTraceEvent(
            name: "generation_chunk_finished",
            chunkIndex: chunkIndex,
            bufferIndex: nil,
            sampleCount: 0,
            durationMS: 0,
            queuedAudioBeforeMS: queuedAudioMS,
            queuedAudioAfterMS: queuedAudioMS,
            gapMS: nil,
            isRebuffering: isRebuffering,
            fadeInApplied: false,
            generatedAudioQuality: nil,
        )
    }

    static func bufferScheduled(
        chunkIndex: Int,
        bufferIndex: Int,
        frameCount: Int,
        sampleRate: Double,
        queuedAudioBeforeMS: Int,
        queuedAudioAfterMS: Int,
        gapMS: Int?,
        isRebuffering: Bool,
        fadeInApplied: Bool,
    ) -> PlaybackTraceEvent {
        PlaybackTraceEvent(
            name: "buffer_scheduled",
            chunkIndex: chunkIndex,
            bufferIndex: bufferIndex,
            sampleCount: frameCount,
            durationMS: Int((Double(frameCount) / sampleRate * 1000).rounded()),
            queuedAudioBeforeMS: queuedAudioBeforeMS,
            queuedAudioAfterMS: queuedAudioAfterMS,
            gapMS: gapMS,
            isRebuffering: isRebuffering,
            fadeInApplied: fadeInApplied,
            generatedAudioQuality: nil,
        )
    }

    static func bufferPlayedBack(
        chunkIndex: Int,
        bufferIndex: Int,
        frameCount: Int,
        sampleRate: Double,
        queuedAudioAfterMS: Int,
        isRebuffering: Bool,
        fadeInApplied: Bool,
    ) -> PlaybackTraceEvent {
        PlaybackTraceEvent(
            name: "buffer_played_back",
            chunkIndex: chunkIndex,
            bufferIndex: bufferIndex,
            sampleCount: frameCount,
            durationMS: Int((Double(frameCount) / sampleRate * 1000).rounded()),
            queuedAudioBeforeMS: nil,
            queuedAudioAfterMS: queuedAudioAfterMS,
            gapMS: nil,
            isRebuffering: isRebuffering,
            fadeInApplied: fadeInApplied,
            generatedAudioQuality: nil,
        )
    }
}
