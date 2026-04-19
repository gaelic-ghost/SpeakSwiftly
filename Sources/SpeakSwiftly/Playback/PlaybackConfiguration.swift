@preconcurrency import AVFoundation
import Foundation

enum AudioPlaybackConfiguration {
    static let minimumDrainTimeout: Duration = .seconds(5)
    static let drainTimeoutPaddingMS = 3000
    static let drainProgressCheckIntervalMS = 500
    static let drainProgressStallTimeoutMS = 8000
    static let environmentInstabilityWindowMS = 8000
    static let recoveryStabilizationDelayMS = 900
    static let recoveryMaximumAttempts = 3
    static let lowQueueThresholdMS = 100
    static let channels: AVAudioChannelCount = 1
    static let interJobBoopDurationMS = 90
    static let interJobBoopFrequencyHz = 1176.0
    static let interJobBoopAmplitude: Float = 0.14
    static let interJobBoopFadeMS = 10
    static let interJobBoopTimeout: Duration = .seconds(2)

    static func drainTimeout(forQueuedAudioMS queuedAudioMS: Int) -> Duration {
        let paddedQueuedAudioMS = queuedAudioMS + drainTimeoutPaddingMS
        return max(minimumDrainTimeout, .milliseconds(paddedQueuedAudioMS))
    }
}
