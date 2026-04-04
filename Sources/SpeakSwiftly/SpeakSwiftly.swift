import Foundation

// MARK: - Public Library Streams

public struct SpeechNormalizationContext: Codable, Sendable, Equatable {
    public let cwd: String?
    public let repoRoot: String?

    public init(cwd: String? = nil, repoRoot: String? = nil) {
        self.cwd = SpeechNormalizationContext.normalizedPath(cwd)
        self.repoRoot = SpeechNormalizationContext.normalizedPath(repoRoot)
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let standardized = NSString(string: trimmed).standardizingPath
        return standardized.isEmpty ? nil : standardized
    }
}

public enum SpeechJobType: Sendable, Equatable {
    case live
}

public enum WorkerQueueType: Sendable, Equatable {
    case generation
    case playback
}

public enum PlaybackAction: Sendable, Equatable {
    case pause
    case resume
    case state
}

public enum PlaybackState: String, Codable, Sendable, Equatable {
    case idle
    case playing
    case paused
}

public enum WorkerRequestStreamEvent: Sendable, Equatable {
    case queued(WorkerQueuedEvent)
    case acknowledged(WorkerSuccessResponse)
    case started(WorkerStartedEvent)
    case progress(WorkerProgressEvent)
    case completed(WorkerSuccessResponse)
}

public struct WorkerRequestHandle: Sendable {
    public let id: String
    public let operationName: String
    public let profileName: String?
    public let events: AsyncThrowingStream<WorkerRequestStreamEvent, Error>

    init(
        id: String,
        operationName: String,
        profileName: String?,
        events: AsyncThrowingStream<WorkerRequestStreamEvent, Error>
    ) {
        self.id = id
        self.operationName = operationName
        self.profileName = profileName
        self.events = events
    }
}

// MARK: - Public Runtime

public enum SpeakSwiftly {
    public static func makeLiveRuntime() async -> WorkerRuntime {
        await WorkerRuntime.live()
    }
}
