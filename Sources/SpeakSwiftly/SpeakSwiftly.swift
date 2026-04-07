import Foundation
import TextForSpeech

// MARK: - Public Library Streams

public enum SpeakSwiftly {
    public enum Job: Sendable, Equatable {
        case live
        case file
    }

    public enum Queue: Sendable, Equatable {
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

    public enum RequestEvent: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(Success)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(Success)
    }

    public struct RequestHandle: Sendable {
        public let id: String
        public let operation: String
        public let profileName: String?
        public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>

        init(
            id: String,
            operation: String,
            profileName: String?,
            events: AsyncThrowingStream<RequestEvent, any Swift.Error>
        ) {
            self.id = id
            self.operation = operation
            self.profileName = profileName
            self.events = events
        }
    }

    public static func live(
        normalizer: SpeakSwiftly.Normalizer? = nil,
        configuration: SpeakSwiftly.Configuration? = nil,
        speechBackend: SpeakSwiftly.SpeechBackend? = nil
    ) async -> Runtime {
        await Runtime.live(
            normalizer: normalizer,
            configuration: configuration,
            speechBackend: speechBackend
        )
    }
}

// MARK: - Internal Compatibility

typealias SpeechJobType = SpeakSwiftly.Job
typealias WorkerQueueType = SpeakSwiftly.Queue
typealias PlaybackAction = SpeakSwiftly.PlaybackAction
typealias PlaybackState = SpeakSwiftly.PlaybackState
typealias WorkerRequestStreamEvent = SpeakSwiftly.RequestEvent
typealias WorkerRequestHandle = SpeakSwiftly.RequestHandle
typealias WorkerRuntime = SpeakSwiftly.Runtime
typealias SpeechNormalizationContext = TextForSpeech.Context
typealias SpeechTextForensicFeatures = TextForSpeech.ForensicFeatures
typealias SpeechTextForensicSection = TextForSpeech.Section
typealias SpeechTextForensicSectionWindow = TextForSpeech.SectionWindow
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
