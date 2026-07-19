import Foundation
import MLXAudioTTS

// MARK: - Worker Runtime

public extension SpeakSwiftly {
    actor Runtime {
        // MARK: Environment

        enum Environment {
            static let runtimeStateRootOverride = ProfileStore.runtimeStateRootOverrideEnvironmentVariable
            static let deprecatedProfileRootOverride = ProfileStore.deprecatedProfileRootOverrideEnvironmentVariable
        }

        enum RequestObservationConfiguration {
            static let maxReplayUpdates = 16
            static let maxRetainedTerminalRequests = 128
        }

        // MARK: Configuration

        enum PlaybackConfiguration {
            enum ResidentStreamingCadenceProfile: String, Equatable {
                case standard
            }

            static let qwenResidentStreamingInterval = 0.32

            static func residentStreamingCadenceProfile(
                speechBackend: SpeakSwiftly.SpeechBackend,
            ) -> ResidentStreamingCadenceProfile {
                .standard
            }

            static func residentStreamingInterval(
                for speechBackend: SpeakSwiftly.SpeechBackend,
                cadenceProfile: ResidentStreamingCadenceProfile,
            ) -> Double {
                switch cadenceProfile {
                    case .standard:
                        qwenResidentStreamingInterval
                }
            }

            static func residentStreamingInterval(
                for cadenceProfile: ResidentStreamingCadenceProfile,
            ) -> Double {
                switch cadenceProfile {
                    case .standard:
                        qwenResidentStreamingInterval
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
            let kind: SpeakSwiftly.RequestKind
            let voiceProfile: String?
            let requestContext: SpeakSwiftly.RequestContext?
            let acceptedAt: Date
            var lastUpdatedAt: Date
            var stateSequence = 0
            var synthesisSequence = 0
            var latestState: SpeakSwiftly.RequestState?
            var replayUpdates = [SpeakSwiftly.RequestUpdate]()
            var subscriberContinuations = [UUID: AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error>.Continuation]()
            var replaySynthesisUpdates = [SpeakSwiftly.SynthesisUpdate]()
            var synthesisContinuations = [UUID: AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error>.Continuation]()
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

            mutating func recordSynthesisEvent(
                _ event: SpeakSwiftly.SynthesisEvent,
                date: Date,
                maxReplayUpdates: Int,
            ) -> SpeakSwiftly.SynthesisUpdate {
                synthesisSequence += 1

                let update = SpeakSwiftly.SynthesisUpdate(
                    id: id,
                    sequence: synthesisSequence,
                    date: date,
                    event: event,
                )
                replaySynthesisUpdates.append(update)
                if replaySynthesisUpdates.count > maxReplayUpdates {
                    replaySynthesisUpdates.removeFirst(replaySynthesisUpdates.count - maxReplayUpdates)
                }
                return update
            }

            func snapshot() -> SpeakSwiftly.RequestSnapshot? {
                guard let latestState else { return nil }

                return SpeakSwiftly.RequestSnapshot(
                    id: id,
                    kind: kind,
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
            let runnableJobs: [GenerationQueue.Job]
            let parkReasons: [UUID: GenerationParkReason]
        }

        typealias WorkerSuccessPayload = WorkerSuccessResponse

        enum GenerationCompletionDisposition {
            case requestCompleted(Result<WorkerSuccessPayload, WorkerError>)
            case requestStillPendingPlayback
        }

        typealias LogLevel = WorkerLogLevel
        typealias LogValue = WorkerLogValue
        typealias LogEvent = WorkerLogEvent

        let dependencies: WorkerDependencies
        var speechBackend: SpeakSwiftly.SpeechBackend
        var qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy
        var duckMediaVolume: SpeakSwiftly.DuckMediaVolume
        var audioOutputDestination: SpeakSwiftly.AudioOutputDestination
        let encoder = JSONEncoder()
        let profileStore: ProfileStore
        let systemProfileResourceStore: ProfileStore?
        let generatedFileStore: GeneratedFileStore
        let generationJobStore: GenerationJobStore
        let recentGeneratedAudioStore: SpeakSwiftly.RecentGeneratedAudioStore
        let recentGeneratedAudioLimit: Int
        let normalizerRef: SpeakSwiftly.Normalizer
        let playbackQueue: PlaybackQueue
        let startsResidentModelsAutomatically: Bool
        let generationQueue = GenerationQueue()
        let logTimestampFormatter = ISO8601DateFormatter()
        let maxAcceptedSpeechJobs = 24

        var residentState: ResidentState = .warming
        var hasStarted = false
        var isShuttingDown = false
        var preloadTask: Task<Void, Never>?
        var residentPreloadToken: UUID?
        var lastQueuedGenerationParkReason = [String: GenerationParkReason]()
        var runtimeObservationBroker = SingletonObservationBroker<SpeakSwiftly.RuntimeUpdate>()
        var generateObservationBroker = SingletonObservationBroker<SpeakSwiftly.GenerateUpdate>()
        var playbackObservationBroker = SingletonObservationBroker<SpeakSwiftly.PlaybackUpdate>()
        var requestBrokers = [String: RequestBroker]()
        var requestAudioOutputDestinations = [String: SpeakSwiftly.AudioOutputDestination]()
        var generatedAudioStreamContinuations = [String: AsyncThrowingStream<SpeakSwiftly.GeneratedAudioChunk, any Swift.Error>.Continuation]()
        var terminalRequestBrokerOrder = [String]()
        var workerOutputContinuations = [UUID: AsyncStream<SpeakSwiftly.WorkerOutputEvent>.Continuation]()
        var activeGenerations = [UUID: ActiveRequest]()
        var activeGenerationCancellations = [String: WorkerError]()
        var qwenConditioningCache = [QwenConditioningCacheKey: Qwen3TTSModel.Qwen3TTSReferenceConditioning]()
        var defaultVoiceProfileName: SpeakSwiftly.Name

        // MARK: Initialization

        init(
            dependencies: WorkerDependencies,
            speechBackend: SpeakSwiftly.SpeechBackend,
            qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy = .preparedConditioning,
            duckMediaVolume: SpeakSwiftly.DuckMediaVolume = .off,
            audioOutputDestination: SpeakSwiftly.AudioOutputDestination = .localPlayback,
            defaultVoiceProfileName: SpeakSwiftly.Name = SpeakSwiftly.DefaultVoiceProfiles.signal,
            profileStore: ProfileStore,
            systemProfileResourceStore: ProfileStore? = nil,
            generatedFileStore: GeneratedFileStore,
            generationJobStore: GenerationJobStore,
            recentGeneratedAudioStore: SpeakSwiftly.RecentGeneratedAudioStore = SpeakSwiftly.RecentGeneratedAudioStore(),
            recentGeneratedAudioLimit: Int = 5,
            normalizer: SpeakSwiftly.Normalizer,
            playbackQueue: PlaybackQueue,
            startsResidentModelsAutomatically: Bool = true,
        ) {
            self.dependencies = dependencies
            self.speechBackend = speechBackend
            self.qwenConditioningStrategy = qwenConditioningStrategy
            self.duckMediaVolume = duckMediaVolume
            self.audioOutputDestination = audioOutputDestination
            self.defaultVoiceProfileName = SpeakSwiftly.Configuration.normalizedDefaultVoiceProfile(defaultVoiceProfileName)
            self.profileStore = profileStore
            self.systemProfileResourceStore = systemProfileResourceStore
            self.generatedFileStore = generatedFileStore
            self.generationJobStore = generationJobStore
            self.recentGeneratedAudioStore = recentGeneratedAudioStore
            self.recentGeneratedAudioLimit = SpeakSwiftly.Configuration
                .normalizedRecentGeneratedAudioLimit(recentGeneratedAudioLimit)
            normalizerRef = normalizer
            self.playbackQueue = playbackQueue
            self.startsResidentModelsAutomatically = startsResidentModelsAutomatically
            encoder.outputFormatting = [.sortedKeys]
        }
    }
}
