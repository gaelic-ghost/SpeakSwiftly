import Foundation

public extension SpeakSwiftly {
    /// Identifies a runtime work queue for queue-specific controls.
    enum QueueType: String, Codable, Sendable, Equatable {
        case generation
        case playback
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Queue Control

    /// Clears queued work from one runtime queue.
    func clearQueue(_ queueType: SpeakSwiftly.QueueType) async -> SpeakSwiftly.RequestHandle {
        await submit(.clearQueue(id: UUID().uuidString, queueType: queueType))
    }

    /// Cancels one queued or active request in one runtime queue.
    func cancel(_ queueType: SpeakSwiftly.QueueType, requestID: String) async -> SpeakSwiftly.RequestHandle {
        await submit(.cancelRequest(id: UUID().uuidString, requestID: requestID, queueType: queueType))
    }
}
