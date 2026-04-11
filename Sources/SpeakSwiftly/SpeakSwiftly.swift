import Foundation
import TextForSpeech

// MARK: - Public Library Streams

public enum SpeakSwiftly {
    // MARK: Names

    public typealias Name = String

    // MARK: Internal Request Helpers

    enum SpeechJobType: Sendable, Equatable {
        case live
        case file
    }

    enum WorkerQueueType: String, Sendable, Equatable {
        case generation
        case playback
    }

    enum PlaybackAction: Sendable, Equatable {
        case pause
        case resume
        case state
    }

    public enum PlaybackState: String, Codable, Sendable, Equatable {
        case idle
        case playing
        case paused
    }

    public enum RequestEvent: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(Success)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(Success)
    }

    public enum RequestState: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(Success)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(Success)
        case failed(Failure)
        case cancelled(Failure)
    }

    public struct GenerationEventInfo: Sendable, Equatable {
        public let promptTokenCount: Int
        public let generationTokenCount: Int
        public let prefillTime: TimeInterval
        public let generateTime: TimeInterval
        public let tokensPerSecond: Double
        public let peakMemoryUsage: Double
    }

    public enum GenerationEvent: Sendable, Equatable {
        case token(Int)
        case info(GenerationEventInfo)
        case audioChunk(sampleCount: Int)
    }

    public struct RequestUpdate: Sendable, Equatable {
        public let id: String
        public let sequence: Int
        public let date: Date
        public let state: RequestState
    }

    public struct GenerationEventUpdate: Sendable, Equatable {
        public let id: String
        public let sequence: Int
        public let date: Date
        public let event: GenerationEvent
    }

    public struct RequestSnapshot: Sendable, Equatable {
        public let id: String
        public let operation: String
        public let profileName: String?
        public let acceptedAt: Date
        public let lastUpdatedAt: Date
        public let sequence: Int
        public let state: RequestState
    }

    // MARK: Handles

    public struct RequestHandle: Sendable {
        public let id: String
        public let operation: String
        public let profileName: String?
        public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>
        public let generationEvents: AsyncThrowingStream<GenerationEventUpdate, any Swift.Error>

        init(
            id: String,
            operation: String,
            profileName: String?,
            events: AsyncThrowingStream<RequestEvent, any Swift.Error>,
            generationEvents: AsyncThrowingStream<GenerationEventUpdate, any Swift.Error>
        ) {
            self.id = id
            self.operation = operation
            self.profileName = profileName
            self.events = events
            self.generationEvents = generationEvents
        }
    }

    public static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil
    ) async -> Runtime {
        await Runtime.liftoff(configuration: configuration)
    }
}

// MARK: - Internal Compatibility

typealias SpeechJobType = SpeakSwiftly.SpeechJobType
typealias WorkerQueueType = SpeakSwiftly.WorkerQueueType
typealias PlaybackAction = SpeakSwiftly.PlaybackAction
typealias PlaybackState = SpeakSwiftly.PlaybackState
typealias WorkerRequestStreamEvent = SpeakSwiftly.RequestEvent
typealias WorkerRequestHandle = SpeakSwiftly.RequestHandle
typealias WorkerRuntime = SpeakSwiftly.Runtime
typealias SpeechNormalizationContext = TextForSpeech.Context
typealias SpeechTextDeepTraceFeatures = SpeakSwiftly.DeepTrace.Features
typealias SpeechTextDeepTraceSection = SpeakSwiftly.DeepTrace.Section
typealias SpeechTextDeepTraceSectionWindow = SpeakSwiftly.DeepTrace.SectionWindow
typealias WorkerStatusStage = SpeakSwiftly.StatusStage
typealias WorkerRequestEventName = SpeakSwiftly.RequestEventName
typealias WorkerProgressStage = SpeakSwiftly.ProgressStage
typealias WorkerQueuedReason = SpeakSwiftly.QueuedReason
typealias WorkerStatusEvent = SpeakSwiftly.StatusEvent
typealias WorkerQueuedEvent = SpeakSwiftly.QueuedEvent
typealias WorkerStartedEvent = SpeakSwiftly.StartedEvent
typealias WorkerProgressEvent = SpeakSwiftly.ProgressEvent
typealias WorkerSuccessResponse = SpeakSwiftly.Success
typealias PlaybackStateSummary = SpeakSwiftly.PlaybackStateSnapshot
typealias ActiveWorkerRequestSummary = SpeakSwiftly.ActiveRequest
typealias QueuedWorkerRequestSummary = SpeakSwiftly.QueuedRequest
typealias WorkerFailureResponse = SpeakSwiftly.Failure
typealias WorkerErrorCode = SpeakSwiftly.ErrorCode
typealias WorkerError = SpeakSwiftly.Error
typealias ProfileSummary = SpeakSwiftly.ProfileSummary
