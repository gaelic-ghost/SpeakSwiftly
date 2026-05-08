import Foundation

public extension SpeakSwiftly {
    /// Describes the current playback state of the live audio player.
    enum PlaybackState: String, Codable, Sendable, Equatable {
        case idle
        case playing
        case paused
        case interrupted
        case recovering
    }

    /// A meaningful event in the live playback surface.
    enum PlaybackEvent: Codable, Sendable, Equatable {
        case stateChanged(PlaybackState)
        case started(requestID: String)
        case activeRequestChanged(ActiveRequest?)
        case queueChanged(activeRequest: ActiveRequest?, queuedRequests: [QueuedRequest])
        case firstChunk(requestID: String)
        case prerollReady(requestID: String, bufferedAudioMS: Int, startupBufferTargetMS: Int)
        case rebufferStarted(requestID: String, queuedAudioMS: Int, resumeBufferTargetMS: Int)
        case rebufferResumed(requestID: String, bufferedAudioMS: Int, resumeBufferTargetMS: Int)
        case completed(requestID: String)
        case outputDeviceChanged(previousDevice: String?, currentDevice: String?)
        case interruptionChanged(isInterrupted: Bool, shouldResume: Bool?)
    }

    /// A sequenced playback-state publication.
    struct PlaybackUpdate: Codable, Sendable, Equatable {
        public let sequence: Int
        public let date: Date
        public let state: PlaybackState
        public let event: PlaybackEvent
    }

    /// A point-in-time read of live playback state and queued playback work.
    struct PlaybackSnapshot: Codable, Sendable, Equatable {
        public let sequence: Int
        public let capturedAt: Date
        public let state: PlaybackState
        public let activeRequest: ActiveRequest?
        public let queuedRequests: [QueuedRequest]
        public let isRebuffering: Bool
        public let stableBufferedAudioMS: Int?
        public let stableBufferTargetMS: Int?
    }
}
