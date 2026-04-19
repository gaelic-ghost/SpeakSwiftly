import Foundation

enum PlaybackMetricsConfiguration {
    static let rebufferThrashWarningCount = 3
    static let rebufferThrashWindowMS = 2000
}

struct PlaybackSummary {
    let thresholds: PlaybackAdaptiveThresholds
    let chunkCount: Int
    let sampleCount: Int
    let startupBufferedAudioMS: Int?
    let timeToFirstChunkMS: Int?
    let timeToPrerollReadyMS: Int?
    let timeFromPrerollReadyToDrainMS: Int?
    let minQueuedAudioMS: Int?
    let maxQueuedAudioMS: Int?
    let avgQueuedAudioMS: Int?
    let queueDepthSampleCount: Int
    let rebufferEventCount: Int
    let rebufferTotalDurationMS: Int
    let longestRebufferDurationMS: Int
    let starvationEventCount: Int
    let scheduleCallbackCount: Int
    let playedBackCallbackCount: Int
    let maxInterChunkGapMS: Int?
    let avgInterChunkGapMS: Int?
    let maxScheduleGapMS: Int?
    let avgScheduleGapMS: Int?
    let maxBoundaryDiscontinuity: Double?
    let maxLeadingAbsAmplitude: Double?
    let maxTrailingAbsAmplitude: Double?
    let fadeInChunkCount: Int
}

struct RuntimeMemorySnapshot {
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let processUserCPUTimeNS: Int?
    let processSystemCPUTimeNS: Int?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
    let mlxCacheLimitBytes: Int?
    let mlxMemoryLimitBytes: Int?
}

enum AudioPlaybackRecoveryReason: String {
    case systemWake = "system_wake"
    case outputDeviceChange = "output_device_change"
    case engineConfigurationChange = "engine_configuration_change"
    case audioSessionInterruption = "audio_session_interruption"
}
