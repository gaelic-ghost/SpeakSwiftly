import Foundation
import TextForSpeech

// MARK: - Worker Runtime

public extension SpeakSwiftly {
    actor Runtime {
    // MARK: Environment

    enum Environment {
        static let profileRootOverride = "SPEAKSWIFTLY_PROFILE_ROOT"
    }

    enum RequestObservationConfiguration {
        static let maxReplayUpdates = 16
        static let maxRetainedTerminalRequests = 128
    }

    // MARK: Configuration

    enum PlaybackConfiguration {
        // Shorter chunk cadence gives playback a second chunk in reserve before
        // the first one drains, which reduces audible shudder from one-chunk starts.
        static let residentStreamingInterval = 0.18
    }

    // MARK: Runtime State

    enum ResidentState: Sendable {
        case warming
        case ready(ResidentSpeechModels)
        case unloaded
        case failed(WorkerError)
    }

    struct ActiveRequest: Sendable {
        let token: UUID
        let request: WorkerRequest
        let task: Task<Void, Never>
    }

    struct RequestBroker {
        let id: String
        let operation: String
        let profileName: String?
        let acceptedAt: Date
        var lastUpdatedAt: Date
        var sequence = 0
        var latestState: SpeakSwiftly.RequestState?
        var replayUpdates = [SpeakSwiftly.RequestUpdate]()
        var subscriberContinuations = [UUID: AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error>.Continuation]()
        var isTerminal = false

        mutating func record(
            state: SpeakSwiftly.RequestState,
            date: Date,
            maxReplayUpdates: Int
        ) -> SpeakSwiftly.RequestUpdate {
            sequence += 1
            lastUpdatedAt = date
            latestState = state

            let update = SpeakSwiftly.RequestUpdate(
                id: id,
                sequence: sequence,
                date: date,
                state: state
            )
            replayUpdates.append(update)
            if replayUpdates.count > maxReplayUpdates {
                replayUpdates.removeFirst(replayUpdates.count - maxReplayUpdates)
            }
            return update
        }

        func snapshot() -> SpeakSwiftly.RequestSnapshot? {
            guard let latestState else { return nil }
            return SpeakSwiftly.RequestSnapshot(
                id: id,
                operation: operation,
                profileName: profileName,
                acceptedAt: acceptedAt,
                lastUpdatedAt: lastUpdatedAt,
                sequence: sequence,
                state: latestState
            )
        }
    }

    enum GenerationParkReason: String, Sendable {
        case waitingForResidentModel = "waiting_for_resident_model"
        case waitingForResidentModels = "waiting_for_resident_models"
        case waitingForActiveRequest = "waiting_for_active_request"
        case waitingForPlaybackStability = "waiting_for_playback_stability"
        case waitingForMarvisGenerationLane = "waiting_for_marvis_generation_lane"
    }

    struct GenerationScheduleDecision: Sendable {
        let runnableJobs: [GenerationController.Job]
        let parkReasons: [UUID: GenerationParkReason]
    }

    struct WorkerSuccessPayload: Sendable {
        let id: String
        let generatedFile: SpeakSwiftly.GeneratedFile?
        let generatedFiles: [SpeakSwiftly.GeneratedFile]?
        let generatedBatch: SpeakSwiftly.GeneratedBatch?
        let generatedBatches: [SpeakSwiftly.GeneratedBatch]?
        let generationJob: SpeakSwiftly.GenerationJob?
        let generationJobs: [SpeakSwiftly.GenerationJob]?
        let profileName: String?
        let profilePath: String?
        let profiles: [ProfileSummary]?
        let textProfile: TextForSpeech.Profile?
        let textProfiles: [TextForSpeech.Profile]?
        let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
        let textProfilePath: String?
        let activeRequest: ActiveWorkerRequestSummary?
        let activeRequests: [ActiveWorkerRequestSummary]?
        let queue: [QueuedWorkerRequestSummary]?
        let playbackState: PlaybackStateSummary?
        let runtimeOverview: SpeakSwiftly.RuntimeOverview?
        let status: WorkerStatusEvent?
        let speechBackend: SpeakSwiftly.SpeechBackend?
        let clearedCount: Int?
        let cancelledRequestID: String?

        init(
            id: String,
            generatedFile: SpeakSwiftly.GeneratedFile? = nil,
            generatedFiles: [SpeakSwiftly.GeneratedFile]? = nil,
            generatedBatch: SpeakSwiftly.GeneratedBatch? = nil,
            generatedBatches: [SpeakSwiftly.GeneratedBatch]? = nil,
            generationJob: SpeakSwiftly.GenerationJob? = nil,
            generationJobs: [SpeakSwiftly.GenerationJob]? = nil,
            profileName: String? = nil,
            profilePath: String? = nil,
            profiles: [ProfileSummary]? = nil,
            textProfile: TextForSpeech.Profile? = nil,
            textProfiles: [TextForSpeech.Profile]? = nil,
            textProfileStyle: TextForSpeech.BuiltInProfileStyle? = nil,
            textProfilePath: String? = nil,
            activeRequest: ActiveWorkerRequestSummary? = nil,
            activeRequests: [ActiveWorkerRequestSummary]? = nil,
            queue: [QueuedWorkerRequestSummary]? = nil,
            playbackState: PlaybackStateSummary? = nil,
            runtimeOverview: SpeakSwiftly.RuntimeOverview? = nil,
            status: WorkerStatusEvent? = nil,
            speechBackend: SpeakSwiftly.SpeechBackend? = nil,
            clearedCount: Int? = nil,
            cancelledRequestID: String? = nil
        ) {
            self.id = id
            self.generatedFile = generatedFile
            self.generatedFiles = generatedFiles
            self.generatedBatch = generatedBatch
            self.generatedBatches = generatedBatches
            self.generationJob = generationJob
            self.generationJobs = generationJobs
            self.profileName = profileName
            self.profilePath = profilePath
            self.profiles = profiles
            self.textProfile = textProfile
            self.textProfiles = textProfiles
            self.textProfileStyle = textProfileStyle
            self.textProfilePath = textProfilePath
            self.activeRequest = activeRequest
            self.activeRequests = activeRequests
            self.queue = queue
            self.playbackState = playbackState
            self.runtimeOverview = runtimeOverview
            self.status = status
            self.speechBackend = speechBackend
            self.clearedCount = clearedCount
            self.cancelledRequestID = cancelledRequestID
        }
    }

    enum GenerationCompletionDisposition: Sendable {
        case requestCompleted(Result<WorkerSuccessPayload, WorkerError>)
        case requestStillPendingPlayback(String)
    }

    struct OutgoingWorkerRequest: Encodable {
        let id: String
        let op: String
        let artifactID: String?
        let batchID: String?
        let jobID: String?
        let items: [SpeakSwiftly.GenerationJobItem]?
        let text: String?
        let profileName: String?
        let textProfileName: String?
        let textProfileID: String?
        let textProfileDisplayName: String?
        let textProfile: TextForSpeech.Profile?
        let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
        let replacements: [TextForSpeech.Replacement]?
        let replacement: TextForSpeech.Replacement?
        let replacementID: String?
        let cwd: String?
        let repoRoot: String?
        let textFormat: TextForSpeech.TextFormat?
        let nestedSourceFormat: TextForSpeech.SourceFormat?
        let sourceFormat: TextForSpeech.SourceFormat?
        let requestID: String?
        let speechBackend: SpeakSwiftly.SpeechBackend?
        let vibe: SpeakSwiftly.Vibe?
        let voiceDescription: String?
        let outputPath: String?
        let referenceAudioPath: String?
        let transcript: String?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case artifactID = "artifact_id"
            case batchID = "batch_id"
            case jobID = "job_id"
            case items
            case text
            case profileName = "profile_name"
            case textProfileName = "text_profile_name"
            case textProfileID = "text_profile_id"
            case textProfileDisplayName = "text_profile_display_name"
            case textProfile = "text_profile"
            case textProfileStyle = "text_profile_style"
            case replacements
            case replacement
            case replacementID = "replacement_id"
            case cwd
            case repoRoot = "repo_root"
            case textFormat = "text_format"
            case nestedSourceFormat = "nested_source_format"
            case sourceFormat = "source_format"
            case requestID = "request_id"
            case speechBackend = "speech_backend"
            case vibe
            case voiceDescription = "voice_description"
            case outputPath = "output_path"
            case referenceAudioPath = "reference_audio_path"
            case transcript
        }
    }

    typealias LogLevel = WorkerLogLevel
    typealias LogValue = WorkerLogValue
    typealias LogEvent = WorkerLogEvent

    // MARK: Stored Properties

    let dependencies: WorkerDependencies
    var speechBackend: SpeakSwiftly.SpeechBackend
    let encoder = JSONEncoder()
    let profileStore: ProfileStore
    let generatedFileStore: GeneratedFileStore
    let generationJobStore: GenerationJobStore
    let normalizerRef: SpeakSwiftly.Normalizer
    let playbackController: PlaybackController
    let generationController = GenerationController()
    let logTimestampFormatter = ISO8601DateFormatter()
    let maxAcceptedSpeechJobs = 8

    var residentState: ResidentState = .warming
    var isShuttingDown = false
    var preloadTask: Task<Void, Never>?
    var residentPreloadToken: UUID?
    var lastQueuedGenerationParkReason = [String: GenerationParkReason]()
    var statusContinuations = [UUID: AsyncStream<WorkerStatusEvent>.Continuation]()
    var requestBrokers = [String: RequestBroker]()
    var terminalRequestBrokerOrder = [String]()
    var activeGenerations = [UUID: ActiveRequest]()
    var lastLoggedMarvisSchedulerState: String?

    // MARK: Initialization

    init(
        dependencies: WorkerDependencies,
        speechBackend: SpeakSwiftly.SpeechBackend,
        profileStore: ProfileStore,
        generatedFileStore: GeneratedFileStore,
        generationJobStore: GenerationJobStore,
        normalizer: SpeakSwiftly.Normalizer,
        playbackController: PlaybackController
    ) {
        self.dependencies = dependencies
        self.speechBackend = speechBackend
        self.profileStore = profileStore
        self.generatedFileStore = generatedFileStore
        self.generationJobStore = generationJobStore
        normalizerRef = normalizer
        self.playbackController = playbackController
        encoder.outputFormatting = [.sortedKeys]
    }

    }
}
