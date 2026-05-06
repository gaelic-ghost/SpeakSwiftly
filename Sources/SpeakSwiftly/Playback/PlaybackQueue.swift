import Foundation

actor PlaybackQueue {
    struct ActivePlayback {
        let requestID: String
        let task: Task<Void, Never>
    }

    let driver: AnyPlaybackDriver
    var hooks: PlaybackHooks?
    var activePlayback: ActivePlayback?
    var activePlaybackIsStableForConcurrentGeneration = false
    var activePlaybackStableBufferedAudioMS: Int?
    var activePlaybackStableBufferTargetMS: Int?
    var activePlaybackConcurrentGenerationTargetMS: Int?
    var activePlaybackFragileOverlapWindowProgress: FragileOverlapWindowProgress?
    var activePlaybackIsRebuffering = false
    var jobs = [String: LiveSpeechPlaybackState]()
    var queue = [String]()

    init(driver: AnyPlaybackDriver) {
        self.driver = driver
    }
}
