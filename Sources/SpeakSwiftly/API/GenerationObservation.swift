import Foundation

public extension SpeakSwiftly {
    /// A meaningful event in the global generation queue.
    enum GenerateEvent: Codable, Sendable, Equatable {
        case stateChanged(GenerateState)
    }

    /// Describes why global generation is not currently accepting another runnable request.
    enum GenerateBlockReason: String, Codable, Sendable, Equatable {
        case waitingForResidentModel = "waiting_for_resident_model"
        case waitingForResidentModels = "waiting_for_resident_models"
        case waitingForActiveRequest = "waiting_for_active_request"
        case waitingForPlaybackStability = "waiting_for_playback_stability"
        case waitingForMarvisGenerationLane = "waiting_for_marvis_generation_lane"
    }

    /// The current semantic state of the global generation queue.
    enum GenerateState: Codable, Sendable, Equatable {
        case idle
        case running
        case blocked(GenerateBlockReason)
    }

    /// A sequenced generation-queue state publication.
    struct GenerateUpdate: Codable, Sendable, Equatable {
        public let sequence: Int
        public let date: Date
        public let state: GenerateState
        public let event: GenerateEvent
    }

    /// A point-in-time read of the global generation queue.
    struct GenerateSnapshot: Codable, Sendable, Equatable {
        public let sequence: Int
        public let capturedAt: Date
        public let state: GenerateState
        public let activeRequests: [ActiveRequest]
        public let queuedRequests: [QueuedRequest]
    }
}
