import Foundation
import TextForSpeech

/// The top-level namespace and startup entrypoint for the SpeakSwiftly library.
///
/// Use ``liftoff(configuration:stateRootURL:)`` to create a shared ``Runtime`` and then work
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
        public let context: TextForSpeech.InputContext?
        public let sourceFormat: TextForSpeech.SourceFormat?

        public init(
            context: TextForSpeech.InputContext? = nil,
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

    /// Identifies the kind of work represented by a request.
    public struct RequestKind: RawRepresentable, Codable, Sendable, Equatable, Hashable {
        public static let generateSpeech = Self(rawValue: "generate_speech")
        public static let generateAudioFile = Self(rawValue: "generate_audio_file")
        public static let generateBatch = Self(rawValue: "generate_batch")
        public static let getGeneratedFile = Self(rawValue: "get_generated_file")
        public static let listGeneratedFiles = Self(rawValue: "list_generated_files")
        public static let getGeneratedBatch = Self(rawValue: "get_generated_batch")
        public static let listGeneratedBatches = Self(rawValue: "list_generated_batches")
        public static let getGenerationJob = Self(rawValue: "get_generation_job")
        public static let listGenerationJobs = Self(rawValue: "list_generation_jobs")
        public static let expireGenerationJob = Self(rawValue: "expire_generation_job")
        public static let createVoiceProfileFromDescription = Self(rawValue: "create_voice_profile_from_description")
        public static let createVoiceProfileFromAudio = Self(rawValue: "create_voice_profile_from_audio")
        public static let createSystemVoiceProfileFromDescription = Self(rawValue: "create_system_voice_profile_from_description")
        public static let listVoiceProfiles = Self(rawValue: "list_voice_profiles")
        public static let updateVoiceProfileName = Self(rawValue: "update_voice_profile_name")
        public static let rerollVoiceProfile = Self(rawValue: "reroll_voice_profile")
        public static let deleteVoiceProfile = Self(rawValue: "delete_voice_profile")
        public static let getActiveTextProfile = Self(rawValue: "get_active_text_profile")
        public static let getTextProfile = Self(rawValue: "get_text_profile")
        public static let listTextProfiles = Self(rawValue: "list_text_profiles")
        public static let getEffectiveTextProfile = Self(rawValue: "get_effective_text_profile")
        public static let getTextProfilePersistence = Self(rawValue: "get_text_profile_persistence")
        public static let getActiveTextProfileStyle = Self(rawValue: "get_active_text_profile_style")
        public static let listTextProfileStyles = Self(rawValue: "list_text_profile_styles")
        public static let setActiveTextProfileStyle = Self(rawValue: "set_active_text_profile_style")
        public static let createTextProfile = Self(rawValue: "create_text_profile")
        public static let updateTextProfileName = Self(rawValue: "update_text_profile_name")
        public static let setActiveTextProfile = Self(rawValue: "set_active_text_profile")
        public static let deleteTextProfile = Self(rawValue: "delete_text_profile")
        public static let factoryResetTextProfiles = Self(rawValue: "factory_reset_text_profiles")
        public static let resetTextProfile = Self(rawValue: "reset_text_profile")
        public static let loadTextProfiles = Self(rawValue: "load_text_profiles")
        public static let saveTextProfiles = Self(rawValue: "save_text_profiles")
        public static let createTextReplacement = Self(rawValue: "create_text_replacement")
        public static let replaceTextReplacement = Self(rawValue: "replace_text_replacement")
        public static let deleteTextReplacement = Self(rawValue: "delete_text_replacement")
        public static let listGenerationQueue = Self(rawValue: "list_generation_queue")
        public static let listPlaybackQueue = Self(rawValue: "list_playback_queue")
        public static let clearGenerationQueue = Self(rawValue: "clear_generation_queue")
        public static let clearPlaybackQueue = Self(rawValue: "clear_playback_queue")
        public static let cancelGeneration = Self(rawValue: "cancel_generation")
        public static let cancelPlayback = Self(rawValue: "cancel_playback")
        public static let getStatus = Self(rawValue: "get_status")
        public static let getRuntimeOverview = Self(rawValue: "get_runtime_overview")
        public static let getPlaybackState = Self(rawValue: "get_playback_state")
        public static let playbackPause = Self(rawValue: "playback_pause")
        public static let playbackResume = Self(rawValue: "playback_resume")
        public static let setSpeechBackend = Self(rawValue: "set_speech_backend")
        public static let reloadModels = Self(rawValue: "reload_models")
        public static let unloadModels = Self(rawValue: "unload_models")
        public static let clearQueue = Self(rawValue: "clear_queue")
        public static let cancelRequest = Self(rawValue: "cancel_request")

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

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
        case completed(RequestCompletion)
    }

    /// A point-in-time state for a submitted request.
    public enum RequestState: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(Success)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(RequestCompletion)
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
        public let kind: RequestKind
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
        public let kind: RequestKind
        public let voiceProfile: String?
        public let requestContext: RequestContext?
        /// A stream of lifecycle events such as queueing, start, progress, and completion.
        public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>
        /// A stream of generation-specific updates such as token counts and audio chunks.
        public let generationEvents: AsyncThrowingStream<GenerationEventUpdate, any Swift.Error>

        init(
            id: String,
            kind: RequestKind,
            voiceProfile: String?,
            requestContext: RequestContext?,
            events: AsyncThrowingStream<RequestEvent, any Swift.Error>,
            generationEvents: AsyncThrowingStream<GenerationEventUpdate, any Swift.Error>,
        ) {
            self.id = id
            self.kind = kind
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
    /// - Parameters:
    ///   - configuration: Optional startup configuration for backend selection
    ///     and text normalization.
    ///   - stateRootURL: Optional runtime state directory. When omitted,
    ///     SpeakSwiftly uses the platform Application Support default unless a
    ///     process-level compatibility override is set.
    /// - Returns: A live ``Runtime`` that owns request submission, playback, and stored resources.
    public static func liftoff(
        configuration: SpeakSwiftly.Configuration? = nil,
        stateRootURL: URL? = nil,
    ) async -> Runtime {
        await Runtime.liftoff(configuration: configuration, stateRootURL: stateRootURL)
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
typealias SpeechNormalizationContext = TextForSpeech.InputContext
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
