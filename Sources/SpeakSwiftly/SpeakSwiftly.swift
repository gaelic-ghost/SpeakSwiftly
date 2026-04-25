import Foundation
import TextForSpeech

/// The top-level namespace and startup entrypoint for the SpeakSwiftly library.
///
/// Use ``liftoff(configuration:)`` to create a shared ``Runtime`` and then work
/// through the runtime's typed concern handles such as ``SpeakSwiftly/Runtime/generate``
/// and ``SpeakSwiftly/Runtime/player``.
public enum SpeakSwiftly {
    // MARK: Names

    /// A stable operator-facing name used for stored resources such as voice profiles.
    public typealias Name = String

    /// A stable identifier for one stored text-normalization profile.
    public typealias TextProfileID = String

    /// Describes how one input text payload should be interpreted before generation.
    public struct InputTextContext: Codable, Sendable, Equatable {
        public let context: TextForSpeech.Context?
        public let sourceFormat: TextForSpeech.SourceFormat?

        public init(
            context: TextForSpeech.Context? = nil,
            sourceFormat: TextForSpeech.SourceFormat? = nil,
        ) {
            self.context = context
            self.sourceFormat = sourceFormat
        }
    }

    /// Describes where a generation request came from and what it is related to.
    ///
    /// `TextForSpeech` owns the concrete model so request metadata stays identical
    /// across normalization, generation, and downstream server surfaces.
    public typealias RequestContext = TextForSpeech.RequestContext

    /// Describes the current playback state of the live audio player.
    public enum PlaybackState: String, Codable, Sendable, Equatable {
        case idle
        case playing
        case paused
    }

    /// A high-level request lifecycle event emitted by a request handle.
    public enum RequestEvent: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(Success)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(Success)
    }

    /// A point-in-time state for a submitted request.
    public enum RequestState: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(Success)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(Success)
        case failed(Failure)
        case cancelled(Failure)
    }

    /// Summary metrics reported for a generation run.
    public struct GenerationEventInfo: Sendable, Equatable {
        public let promptTokenCount: Int
        public let generationTokenCount: Int
        public let prefillTime: TimeInterval
        public let generateTime: TimeInterval
        public let tokensPerSecond: Double
        public let peakMemoryUsage: Double
    }

    /// A generation-side event emitted while speech is being produced.
    public enum GenerationEvent: Sendable, Equatable {
        case token(Int)
        case info(GenerationEventInfo)
        case audioChunk(sampleCount: Int)
    }

    /// A sequenced request-state update produced by the runtime's observation stream.
    public struct RequestUpdate: Sendable, Equatable {
        public let id: String
        public let sequence: Int
        public let date: Date
        public let state: RequestState
    }

    /// A sequenced generation event update produced by the runtime's observation stream.
    public struct GenerationEventUpdate: Sendable, Equatable {
        public let id: String
        public let sequence: Int
        public let date: Date
        public let event: GenerationEvent
    }

    /// A retained snapshot of the most recent known state for one request.
    public struct RequestSnapshot: Sendable, Equatable {
        public let id: String
        public let operation: String
        public let voiceProfile: String?
        public let requestContext: RequestContext?
        public let acceptedAt: Date
        public let lastUpdatedAt: Date
        public let sequence: Int
        public let state: RequestState
    }

    // MARK: Handles

    /// A typed handle for one submitted request and its live event streams.
    public struct RequestHandle: Sendable {
        public let id: String
        public let operation: String
        public let voiceProfile: String?
        public let requestContext: RequestContext?
        /// A stream of lifecycle events such as queueing, start, progress, and completion.
        public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>
        /// A stream of generation-specific updates such as token counts and audio chunks.
        public let generationEvents: AsyncThrowingStream<GenerationEventUpdate, any Swift.Error>

        init(
            id: String,
            operation: String,
            voiceProfile: String?,
            requestContext: RequestContext?,
            events: AsyncThrowingStream<RequestEvent, any Swift.Error>,
            generationEvents: AsyncThrowingStream<GenerationEventUpdate, any Swift.Error>,
        ) {
            self.id = id
            self.operation = operation
            self.voiceProfile = voiceProfile
            self.requestContext = requestContext
            self.events = events
            self.generationEvents = generationEvents
        }
    }

    /// Identifies a runtime work queue for queue-specific controls.
    public enum QueueType: String, Sendable, Equatable {
        case generation
        case playback
    }

    // MARK: Internal Request Helpers

    enum SpeechJobType: Equatable {
        case live
        case file
    }

    enum PlaybackAction: Equatable {
        case pause
        case resume
        case state
    }

    /// Starts a SpeakSwiftly runtime.
    ///
    /// - Parameter configuration: Optional startup configuration for backend selection
    ///   and text normalization.
    /// - Returns: A live ``Runtime`` that owns request submission, playback, and stored resources.
    public static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil,
    ) async -> Runtime {
        await Runtime.liftoff(configuration: configuration)
    }
}

// MARK: - Internal Compatibility

typealias SpeechJobType = SpeakSwiftly.SpeechJobType
typealias WorkerQueueType = SpeakSwiftly.QueueType
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
