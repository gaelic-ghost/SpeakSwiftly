import Foundation
import MLXAudioTTS
import TextForSpeech

// MARK: - Worker Runtime

public extension SpeakSwiftly {
    actor Runtime {
        // MARK: Environment

        enum Environment {
            static let profileRootOverride = ProfileStore.profileRootOverrideEnvironmentVariable
        }

        enum RequestObservationConfiguration {
            static let maxReplayUpdates = 16
            static let maxRetainedTerminalRequests = 128
        }

        // MARK: Configuration

        enum PlaybackConfiguration {
            enum ResidentStreamingCadenceProfile: String, Equatable {
                case standard
                case firstDrainedLiveMarvis = "first_drained_live_marvis"
            }

            /// Use a less aggressive resident cadence for Chatterbox and the normal
            /// Marvis path so backend chunk delivery stays closer to upstream timing.
            static let standardResidentStreamingInterval = 0.5
            static let qwenResidentStreamingInterval = 0.32

            /// Keep the Marvis-specific cadence roles for scheduling and playback
            /// policy, but align their timing to the current upstream streaming
            /// cadence instead of a SpeakSwiftly-specific faster interval.
            static let firstDrainedLiveMarvisStreamingInterval = 0.5

            static func residentStreamingCadenceProfile(
                speechBackend: SpeakSwiftly.SpeechBackend,
                existingPlaybackJobCount: Int,
            ) -> ResidentStreamingCadenceProfile {
                guard speechBackend == .marvis else { return .standard }

                return switch existingPlaybackJobCount {
                    case 0:
                        .firstDrainedLiveMarvis
                    default:
                        .standard
                }
            }

            static func residentStreamingInterval(
                for speechBackend: SpeakSwiftly.SpeechBackend,
                cadenceProfile: ResidentStreamingCadenceProfile,
            ) -> Double {
                switch cadenceProfile {
                    case .standard:
                        speechBackend == .qwen3 ? qwenResidentStreamingInterval : standardResidentStreamingInterval
                    case .firstDrainedLiveMarvis:
                        firstDrainedLiveMarvisStreamingInterval
                }
            }

            static func residentStreamingInterval(
                for cadenceProfile: ResidentStreamingCadenceProfile,
            ) -> Double {
                switch cadenceProfile {
                    case .standard:
                        standardResidentStreamingInterval
                    case .firstDrainedLiveMarvis:
                        firstDrainedLiveMarvisStreamingInterval
                }
            }
        }

        // MARK: Runtime State

        enum ResidentState {
            case warming
            case ready(ResidentSpeechModels)
            case unloaded
            case failed(WorkerError)
        }

        struct ActiveRequest {
            let token: UUID
            let request: WorkerRequest
            let task: Task<Void, Never>
        }

        struct QwenConditioningCacheKey: Hashable {
            let profileName: String
            let backend: SpeakSwiftly.SpeechBackend
            let modelRepo: String
            let artifactVersion: Int
            let artifactFile: String
        }

        struct RequestBroker {
            let id: String
            let operation: String
            let voiceProfile: String?
            let requestContext: SpeakSwiftly.RequestContext?
            let acceptedAt: Date
            var lastUpdatedAt: Date
            var stateSequence = 0
            var generationSequence = 0
            var latestState: SpeakSwiftly.RequestState?
            var replayUpdates = [SpeakSwiftly.RequestUpdate]()
            var subscriberContinuations = [UUID: AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error>.Continuation]()
            var replayGenerationEvents = [SpeakSwiftly.GenerationEventUpdate]()
            var generationContinuations = [UUID: AsyncThrowingStream<SpeakSwiftly.GenerationEventUpdate, any Swift.Error>.Continuation]()
            var isTerminal = false

            mutating func recordState(
                state: SpeakSwiftly.RequestState,
                date: Date,
                maxReplayUpdates: Int,
            ) -> SpeakSwiftly.RequestUpdate {
                stateSequence += 1
                lastUpdatedAt = date
                latestState = state

                let update = SpeakSwiftly.RequestUpdate(
                    id: id,
                    sequence: stateSequence,
                    date: date,
                    state: state,
                )
                replayUpdates.append(update)
                if replayUpdates.count > maxReplayUpdates {
                    replayUpdates.removeFirst(replayUpdates.count - maxReplayUpdates)
                }
                return update
            }

            mutating func recordGenerationEvent(
                _ event: SpeakSwiftly.GenerationEvent,
                date: Date,
                maxReplayUpdates: Int,
            ) -> SpeakSwiftly.GenerationEventUpdate {
                generationSequence += 1

                let update = SpeakSwiftly.GenerationEventUpdate(
                    id: id,
                    sequence: generationSequence,
                    date: date,
                    event: event,
                )
                replayGenerationEvents.append(update)
                if replayGenerationEvents.count > maxReplayUpdates {
                    replayGenerationEvents.removeFirst(replayGenerationEvents.count - maxReplayUpdates)
                }
                return update
            }

            func snapshot() -> SpeakSwiftly.RequestSnapshot? {
                guard let latestState else { return nil }

                return SpeakSwiftly.RequestSnapshot(
                    id: id,
                    operation: operation,
                    voiceProfile: voiceProfile,
                    requestContext: requestContext,
                    acceptedAt: acceptedAt,
                    lastUpdatedAt: lastUpdatedAt,
                    sequence: stateSequence,
                    state: latestState,
                )
            }
        }

        enum GenerationParkReason: String {
            case waitingForResidentModel = "waiting_for_resident_model"
            case waitingForResidentModels = "waiting_for_resident_models"
            case waitingForActiveRequest = "waiting_for_active_request"
            case waitingForPlaybackStability = "waiting_for_playback_stability"
        }

        struct GenerationScheduleDecision {
            let runnableJobs: [SpeechGenerationController.Job]
            let parkReasons: [UUID: GenerationParkReason]
        }

        struct WorkerSuccessPayload {
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
            let textProfile: SpeakSwiftly.TextProfileDetails?
            let textProfiles: [SpeakSwiftly.TextProfileSummary]?
            let textProfileStyleOptions: [SpeakSwiftly.TextProfileStyleOption]?
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
                textProfile: SpeakSwiftly.TextProfileDetails? = nil,
                textProfiles: [SpeakSwiftly.TextProfileSummary]? = nil,
                textProfileStyleOptions: [SpeakSwiftly.TextProfileStyleOption]? = nil,
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
                cancelledRequestID: String? = nil,
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
                self.textProfileStyleOptions = textProfileStyleOptions
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

        enum GenerationCompletionDisposition {
            case requestCompleted(Result<WorkerSuccessPayload, WorkerError>)
            case requestStillPendingPlayback
        }

        struct OutgoingWorkerRequest: Encodable {
            enum CodingKeys: String, CodingKey {
                case id
                case op
                case artifactID = "artifact_id"
                case batchID = "batch_id"
                case jobID = "job_id"
                case items
                case text
                case voiceProfile = "voice_profile"
                case profileName = "profile_name"
                case newProfileName = "new_profile_name"
                case textProfile = "text_profile"
                case textProfileID = "text_profile_id"
                case inputTextContext = "input_text_context"
                case requestContext = "request_context"
                case textProfileStyle = "text_profile_style"
                case replacement
                case replacementID = "replacement_id"
                case cwd
                case repoRoot = "repo_root"
                case textFormat = "text_format"
                case nestedSourceFormat = "nested_source_format"
                case sourceFormat = "source_format"
                case requestID = "request_id"
                case speechBackend = "speech_backend"
                case qwenPreModelTextChunking = "qwen_pre_model_text_chunking"
                case vibe
                case voiceDescription = "voice_description"
                case outputPath = "output_path"
                case referenceAudioPath = "reference_audio_path"
                case transcript
            }

            let id: String
            let op: String
            let artifactID: String?
            let batchID: String?
            let jobID: String?
            let items: [SpeakSwiftly.GenerationJobItem]?
            let text: String?
            let voiceProfile: String?
            let profileName: String?
            let newProfileName: String?
            let textProfile: SpeakSwiftly.TextProfileID?
            let inputTextContext: SpeakSwiftly.InputTextContext?
            let requestContext: SpeakSwiftly.RequestContext?
            let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
            let replacement: TextForSpeech.Replacement?
            let replacementID: String?
            let cwd: String?
            let repoRoot: String?
            let textFormat: TextForSpeech.TextFormat?
            let nestedSourceFormat: TextForSpeech.SourceFormat?
            let sourceFormat: TextForSpeech.SourceFormat?
            let requestID: String?
            let speechBackend: SpeakSwiftly.SpeechBackend?
            let qwenPreModelTextChunking: Bool?
            let vibe: SpeakSwiftly.Vibe?
            let voiceDescription: String?
            let outputPath: String?
            let referenceAudioPath: String?
            let transcript: String?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(op, forKey: .op)
                try container.encodeIfPresent(artifactID, forKey: .artifactID)
                try container.encodeIfPresent(batchID, forKey: .batchID)
                try container.encodeIfPresent(jobID, forKey: .jobID)
                try container.encodeIfPresent(items, forKey: .items)
                try container.encodeIfPresent(text, forKey: .text)
                try container.encodeIfPresent(voiceProfile, forKey: .voiceProfile)
                try container.encodeIfPresent(profileName, forKey: .profileName)
                try container.encodeIfPresent(newProfileName, forKey: .newProfileName)
                try container.encodeIfPresent(textProfile, forKey: .textProfile)
                try container.encodeIfPresent(inputTextContext, forKey: .inputTextContext)
                try container.encodeIfPresent(requestContext, forKey: .requestContext)
                try container.encodeIfPresent(textProfileStyle, forKey: .textProfileStyle)
                try container.encodeIfPresent(replacement, forKey: .replacement)
                try container.encodeIfPresent(replacementID, forKey: .replacementID)
                try container.encodeIfPresent(cwd, forKey: .cwd)
                try container.encodeIfPresent(repoRoot, forKey: .repoRoot)
                try container.encodeIfPresent(textFormat, forKey: .textFormat)
                try container.encodeIfPresent(nestedSourceFormat, forKey: .nestedSourceFormat)
                try container.encodeIfPresent(sourceFormat, forKey: .sourceFormat)
                try container.encodeIfPresent(requestID, forKey: .requestID)
                try container.encodeIfPresent(speechBackend, forKey: .speechBackend)
                try container.encodeIfPresent(qwenPreModelTextChunking, forKey: .qwenPreModelTextChunking)
                try container.encodeIfPresent(vibe, forKey: .vibe)
                try container.encodeIfPresent(voiceDescription, forKey: .voiceDescription)
                try container.encodeIfPresent(outputPath, forKey: .outputPath)
                try container.encodeIfPresent(referenceAudioPath, forKey: .referenceAudioPath)
                try container.encodeIfPresent(transcript, forKey: .transcript)
            }
        }

        typealias LogLevel = WorkerLogLevel
        typealias LogValue = WorkerLogValue
        typealias LogEvent = WorkerLogEvent

        let dependencies: WorkerDependencies
        var speechBackend: SpeakSwiftly.SpeechBackend
        var qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy
        let qwenResidentModel: SpeakSwiftly.QwenResidentModel
        let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
        let encoder = JSONEncoder()
        let profileStore: ProfileStore
        let generatedFileStore: GeneratedFileStore
        let generationJobStore: GenerationJobStore
        let normalizerRef: SpeakSwiftly.Normalizer
        let playbackController: PlaybackController
        let generationController = SpeechGenerationController()
        let logTimestampFormatter = ISO8601DateFormatter()
        let maxAcceptedSpeechJobs = 24

        var residentState: ResidentState = .warming
        var isShuttingDown = false
        var preloadTask: Task<Void, Never>?
        var residentPreloadToken: UUID?
        var lastQueuedGenerationParkReason = [String: GenerationParkReason]()
        var statusContinuations = [UUID: AsyncStream<WorkerStatusEvent>.Continuation]()
        var requestBrokers = [String: RequestBroker]()
        var terminalRequestBrokerOrder = [String]()
        var activeGenerations = [UUID: ActiveRequest]()
        var activeGenerationCancellations = [String: WorkerError]()
        var lastLoggedMarvisSchedulerState: String?
        var qwenConditioningCache = [QwenConditioningCacheKey: Qwen3TTSModel.Qwen3TTSReferenceConditioning]()

        // MARK: Initialization

        init(
            dependencies: WorkerDependencies,
            speechBackend: SpeakSwiftly.SpeechBackend,
            qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy = .preparedConditioning,
            qwenResidentModel: SpeakSwiftly.QwenResidentModel = .base06B8Bit,
            marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy = .dualResidentSerialized,
            profileStore: ProfileStore,
            generatedFileStore: GeneratedFileStore,
            generationJobStore: GenerationJobStore,
            normalizer: SpeakSwiftly.Normalizer,
            playbackController: PlaybackController,
        ) {
            self.dependencies = dependencies
            self.speechBackend = speechBackend
            self.qwenConditioningStrategy = qwenConditioningStrategy
            self.qwenResidentModel = qwenResidentModel
            self.marvisResidentPolicy = marvisResidentPolicy
            self.profileStore = profileStore
            self.generatedFileStore = generatedFileStore
            self.generationJobStore = generationJobStore
            normalizerRef = normalizer
            self.playbackController = playbackController
            encoder.outputFormatting = [.sortedKeys]
        }
    }
}
