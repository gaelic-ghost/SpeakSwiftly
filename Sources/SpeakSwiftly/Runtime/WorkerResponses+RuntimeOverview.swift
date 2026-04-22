import Foundation

// MARK: - Response Runtime Overview

public extension SpeakSwiftly {
    struct QueueSnapshot: Codable, Sendable, Equatable {
        public let queueType: String
        public let activeRequest: ActiveRequest?
        public let activeRequests: [ActiveRequest]?
        public let queue: [QueuedRequest]

        enum CodingKeys: String, CodingKey {
            case queueType = "queue_type"
            case activeRequest = "active_request"
            case activeRequests = "active_requests"
            case queue
        }

        public init(
            queueType: String,
            activeRequest: ActiveRequest? = nil,
            activeRequests: [ActiveRequest]? = nil,
            queue: [QueuedRequest],
        ) {
            self.queueType = queueType
            self.activeRequest = activeRequest
            self.activeRequests = activeRequests
            self.queue = queue
        }
    }

    struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
        public let state: PlaybackState
        public let activeRequest: ActiveRequest?
        /// These fields remain part of the runtime overview as playback telemetry for operators.
        /// Runtime scheduling no longer depends directly on this richer surface.
        public let isStableForConcurrentGeneration: Bool
        public let isRebuffering: Bool
        public let stableBufferedAudioMS: Int?
        public let stableBufferTargetMS: Int?

        enum CodingKeys: String, CodingKey {
            case state
            case activeRequest = "active_request"
            case isStableForConcurrentGeneration = "is_stable_for_concurrent_generation"
            case isRebuffering = "is_rebuffering"
            case stableBufferedAudioMS = "stable_buffered_audio_ms"
            case stableBufferTargetMS = "stable_buffer_target_ms"
        }

        public init(
            state: PlaybackState,
            activeRequest: ActiveRequest?,
            isStableForConcurrentGeneration: Bool = false,
            isRebuffering: Bool = false,
            stableBufferedAudioMS: Int? = nil,
            stableBufferTargetMS: Int? = nil,
        ) {
            self.state = state
            self.activeRequest = activeRequest
            self.isStableForConcurrentGeneration = isStableForConcurrentGeneration
            self.isRebuffering = isRebuffering
            self.stableBufferedAudioMS = stableBufferedAudioMS
            self.stableBufferTargetMS = stableBufferTargetMS
        }
    }

    struct RuntimeOverview: Encodable, Sendable, Equatable {
        public let status: StatusEvent?
        public let speechBackend: SpeechBackend
        public let generationQueue: QueueSnapshot
        public let playbackQueue: QueueSnapshot
        public let playbackState: PlaybackStateSnapshot

        enum CodingKeys: String, CodingKey {
            case status
            case speechBackend = "speech_backend"
            case generationQueue = "generation_queue"
            case playbackQueue = "playback_queue"
            case playbackState = "playback_state"
        }

        public init(
            status: StatusEvent?,
            speechBackend: SpeechBackend,
            generationQueue: QueueSnapshot,
            playbackQueue: QueueSnapshot,
            playbackState: PlaybackStateSnapshot,
        ) {
            self.status = status
            self.speechBackend = speechBackend
            self.generationQueue = generationQueue
            self.playbackQueue = playbackQueue
            self.playbackState = playbackState
        }
    }

    struct ActiveRequest: Codable, Sendable, Equatable {
        public let id: String
        public let op: String
        public let voiceProfile: String?
        public let requestContext: SpeakSwiftly.RequestContext?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case voiceProfile = "voice_profile"
            case requestContext = "request_context"
        }

        public init(id: String, op: String, voiceProfile: String?, requestContext: SpeakSwiftly.RequestContext?) {
            self.id = id
            self.op = op
            self.voiceProfile = voiceProfile
            self.requestContext = requestContext
        }
    }

    struct QueuedRequest: Codable, Sendable, Equatable {
        public let id: String
        public let op: String
        public let voiceProfile: String?
        public let requestContext: SpeakSwiftly.RequestContext?
        public let queuePosition: Int

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case voiceProfile = "voice_profile"
            case requestContext = "request_context"
            case queuePosition = "queue_position"
        }

        public init(
            id: String,
            op: String,
            voiceProfile: String?,
            requestContext: SpeakSwiftly.RequestContext?,
            queuePosition: Int,
        ) {
            self.id = id
            self.op = op
            self.voiceProfile = voiceProfile
            self.requestContext = requestContext
            self.queuePosition = queuePosition
        }
    }
}
