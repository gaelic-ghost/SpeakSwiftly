import Foundation

// MARK: - Public Library Streams

public enum WorkerRequestStreamEvent: Sendable, Equatable {
    case queued(WorkerQueuedEvent)
    case acknowledged(WorkerSuccessResponse)
    case started(WorkerStartedEvent)
    case progress(WorkerProgressEvent)
    case completed(WorkerSuccessResponse)
}

public struct WorkerRequestHandle: Sendable {
    public let id: String
    public let request: WorkerRequest
    public let events: AsyncThrowingStream<WorkerRequestStreamEvent, Error>

    init(
        id: String,
        request: WorkerRequest,
        events: AsyncThrowingStream<WorkerRequestStreamEvent, Error>
    ) {
        self.id = id
        self.request = request
        self.events = events
    }
}

// MARK: - Public Runtime

public enum SpeakSwiftly {
    public static func makeLiveRuntime() async -> WorkerRuntime {
        await WorkerRuntime.live()
    }
}
