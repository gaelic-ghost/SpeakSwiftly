import Foundation

enum PlaybackEvent {
    case firstChunk
    case prerollReady(startupBufferedAudioMS: Int, thresholds: PlaybackAdaptiveThresholds)
    case queueDepthLow(queuedAudioMS: Int)
    case rebufferStarted(queuedAudioMS: Int, thresholds: PlaybackAdaptiveThresholds)
    case rebufferResumed(bufferedAudioMS: Int, thresholds: PlaybackAdaptiveThresholds)
    case chunkGapWarning(gapMS: Int, chunkIndex: Int)
    case scheduleGapWarning(gapMS: Int, bufferIndex: Int, queuedAudioMS: Int)
    case rebufferThrashWarning(rebufferEventCount: Int, windowMS: Int)
    case generationQualityWarning(GeneratedAudioQualityWarning)
    case outputDeviceChanged(previousDevice: String?, currentDevice: String?)
    case engineConfigurationChanged(engineIsRunning: Bool)
    case bufferShapeSummary(
        maxBoundaryDiscontinuity: Double,
        maxLeadingAbsAmplitude: Double,
        maxTrailingAbsAmplitude: Double,
        fadeInChunkCount: Int,
    )
    case trace(PlaybackTraceEvent)
    case starved
}

enum PlaybackEnvironmentEvent {
    case outputDeviceObserved(currentDevice: String?)
    case outputDeviceChanged(previousDevice: String?, currentDevice: String?)
    case engineConfigurationChanged(engineIsRunning: Bool)
    case interruptionStateChanged(isInterrupted: Bool, shouldResume: Bool?)
    case systemSleepStateChanged(isSleeping: Bool)
    case screenSleepStateChanged(isSleeping: Bool)
    case sessionActivityChanged(isActive: Bool)
    case recoveryStateChanged(reason: String, stage: String, attempt: Int?, currentDevice: String?)
    case interJobBoopPlayed(durationMS: Int, frequencyHz: Double, sampleRate: Double)
}

struct PlaybackTraceEvent {
    let name: String
    let chunkIndex: Int?
    let bufferIndex: Int?
    let sampleCount: Int?
    let durationMS: Int?
    let queuedAudioBeforeMS: Int?
    let queuedAudioAfterMS: Int?
    let gapMS: Int?
    let isRebuffering: Bool?
    let fadeInApplied: Bool?
    let generatedAudioQuality: GeneratedAudioQualityObservation?

    init(
        name: String,
        chunkIndex: Int?,
        bufferIndex: Int?,
        sampleCount: Int?,
        durationMS: Int?,
        queuedAudioBeforeMS: Int?,
        queuedAudioAfterMS: Int?,
        gapMS: Int?,
        isRebuffering: Bool?,
        fadeInApplied: Bool?,
        generatedAudioQuality: GeneratedAudioQualityObservation? = nil,
    ) {
        self.name = name
        self.chunkIndex = chunkIndex
        self.bufferIndex = bufferIndex
        self.sampleCount = sampleCount
        self.durationMS = durationMS
        self.queuedAudioBeforeMS = queuedAudioBeforeMS
        self.queuedAudioAfterMS = queuedAudioAfterMS
        self.gapMS = gapMS
        self.isRebuffering = isRebuffering
        self.fadeInApplied = fadeInApplied
        self.generatedAudioQuality = generatedAudioQuality
    }
}
