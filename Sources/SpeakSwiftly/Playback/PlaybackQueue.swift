import Foundation

actor PlaybackQueue {
    struct ActivePlayback {
        let requestID: String
        let task: Task<Void, Never>
        var isStableForConcurrentGeneration = false
        var stableBufferedAudioMS: Int?
        var stableBufferTargetMS: Int?
        var concurrentGenerationTargetMS: Int?
        var fragileOverlapWindowProgress: FragileOverlapWindowProgress?
        var isRebuffering = false

        mutating func resetFragileOverlapWindowAfterDistress() {
            isStableForConcurrentGeneration = false
            guard var fragileOverlapWindowProgress else { return }

            fragileOverlapWindowProgress.hasSatisfiedHold = false
            fragileOverlapWindowProgress.stableBufferEventCount = 0
            self.fragileOverlapWindowProgress = fragileOverlapWindowProgress
            stableBufferTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS
        }
    }

    let driver: AnyPlaybackDriver
    var hooks: PlaybackHooks?
    var activePlayback: ActivePlayback?
    var jobs = [String: LiveSpeechPlaybackState]()
    var queue = [String]()

    init(driver: AnyPlaybackDriver) {
        self.driver = driver
    }
}
