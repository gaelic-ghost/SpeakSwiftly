import Foundation
import TextForSpeech

// MARK: - Response Envelope

public extension SpeakSwiftly {
    // MARK: - Status

    enum StatusStage: String, Codable, Sendable {
        case warmingResidentModel = "warming_resident_model"
        case residentModelReady = "resident_model_ready"
        case residentModelsUnloaded = "resident_models_unloaded"
        case residentModelFailed = "resident_model_failed"
    }

    enum ResidentModelState: String, Codable, Sendable {
        case warming
        case ready
        case unloaded
        case failed
    }

    enum RequestEventName: String, Codable, Sendable {
        case queued
        case started
        case progress
    }

    enum ProgressStage: String, Codable, Sendable {
        case loadingProfile = "loading_profile"
        case generatingFileAudio = "generating_file_audio"
        case writingGeneratedFile = "writing_generated_file"
        case startingPlayback = "starting_playback"
        case bufferingAudio = "buffering_audio"
        case prerollReady = "preroll_ready"
        case playbackFinished = "playback_finished"
        case loadingProfileModel = "loading_profile_model"
        case generatingProfileAudio = "generating_profile_audio"
        case loadingCloneTranscriptionModel = "loading_clone_transcription_model"
        case transcribingCloneAudio = "transcribing_clone_audio"
        case writingProfileAssets = "writing_profile_assets"
        case exportingProfileAudio = "exporting_profile_audio"
        case removingProfile = "removing_profile"
    }

    enum QueuedReason: String, Codable, Sendable {
        case waitingForResidentModel = "waiting_for_resident_model"
        case waitingForResidentModels = "waiting_for_resident_models"
        case waitingForActiveRequest = "waiting_for_active_request"
        case waitingForPlaybackStability = "waiting_for_playback_stability"
        case waitingForMarvisGenerationLane = "waiting_for_marvis_generation_lane"
    }

    struct StatusEvent: Encodable, Sendable, Equatable {
        public let event = "worker_status"
        public let stage: StatusStage
        public let residentState: ResidentModelState
        public let speechBackend: SpeechBackend

        enum CodingKeys: String, CodingKey {
            case event
            case stage
            case residentState = "resident_state"
            case speechBackend = "speech_backend"
        }

        public init(stage: StatusStage, residentState: ResidentModelState, speechBackend: SpeechBackend) {
            self.stage = stage
            self.residentState = residentState
            self.speechBackend = speechBackend
        }
    }

    // MARK: - Request Events

    struct QueueSnapshot: Codable, Sendable, Equatable {
        public let queueType: String
        public let activeRequest: ActiveRequest?
        public let activeRequests: [ActiveRequest]?
        public let queue: [QueuedRequest]

        enum CodingKeys: String, CodingKey {
            case queueType = "queue_type"
            case activeRequest = "active_request"
            case activeRequests = "active_requests"
            case queue
        }

        public init(
            queueType: String,
            activeRequest: ActiveRequest? = nil,
            activeRequests: [ActiveRequest]? = nil,
            queue: [QueuedRequest]
        ) {
            self.queueType = queueType
            self.activeRequest = activeRequest
            self.activeRequests = activeRequests
            self.queue = queue
        }
    }

    struct QueuedEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.queued
        public let reason: QueuedReason
        public let queuePosition: Int

        enum CodingKeys: String, CodingKey {
            case id
            case event
            case reason
            case queuePosition = "queue_position"
        }

        public init(id: String, reason: QueuedReason, queuePosition: Int) {
            self.id = id
            self.reason = reason
            self.queuePosition = queuePosition
        }
    }

    struct StartedEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.started
        public let op: String

        public init(id: String, op: String) {
            self.id = id
            self.op = op
        }
    }

    struct ProgressEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.progress
        public let stage: ProgressStage

        public init(id: String, stage: ProgressStage) {
            self.id = id
            self.stage = stage
        }
    }

    struct Success: Encodable, Sendable, Equatable {
        public let id: String
        public let ok = true
        public let generatedFile: GeneratedFile?
        public let generatedFiles: [GeneratedFile]?
        public let generatedBatch: GeneratedBatch?
        public let generatedBatches: [GeneratedBatch]?
        public let generationJob: GenerationJob?
        public let generationJobs: [GenerationJob]?
        public let profileName: String?
        public let profilePath: String?
        public let profiles: [ProfileSummary]?
        public let textProfile: TextForSpeech.Profile?
        public let textProfiles: [TextForSpeech.Profile]?
        public let replacements: [TextForSpeech.Replacement]?
        public let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
        public let textProfilePath: String?
        public let activeRequest: ActiveRequest?
        public let activeRequests: [ActiveRequest]?
        public let queue: [QueuedRequest]?
        public let playbackState: PlaybackStateSnapshot?
        public let runtimeOverview: RuntimeOverview?
        public let status: StatusEvent?
        public let speechBackend: SpeechBackend?
        public let clearedCount: Int?
        public let cancelledRequestID: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ok
            case generatedFile = "generated_file"
            case generatedFiles = "generated_files"
            case generatedBatch = "generated_batch"
            case generatedBatches = "generated_batches"
            case generationJob = "generation_job"
            case generationJobs = "generation_jobs"
            case profileName = "profile_name"
            case profilePath = "profile_path"
            case profiles
            case textProfile = "text_profile"
            case textProfiles = "text_profiles"
            case replacements
            case textProfileStyle = "text_profile_style"
            case textProfilePath = "text_profile_path"
            case activeRequest = "active_request"
            case activeRequests = "active_requests"
            case queue
            case playbackState = "playback_state"
            case runtimeOverview = "runtime_overview"
            case status
            case speechBackend = "speech_backend"
            case clearedCount = "cleared_count"
            case cancelledRequestID = "cancelled_request_id"
        }

        public init(
            id: String,
            generatedFile: GeneratedFile? = nil,
            generatedFiles: [GeneratedFile]? = nil,
            generatedBatch: GeneratedBatch? = nil,
            generatedBatches: [GeneratedBatch]? = nil,
            generationJob: GenerationJob? = nil,
            generationJobs: [GenerationJob]? = nil,
            profileName: String? = nil,
            profilePath: String? = nil,
            profiles: [ProfileSummary]? = nil,
            textProfile: TextForSpeech.Profile? = nil,
            textProfiles: [TextForSpeech.Profile]? = nil,
            replacements: [TextForSpeech.Replacement]? = nil,
            textProfileStyle: TextForSpeech.BuiltInProfileStyle? = nil,
            textProfilePath: String? = nil,
            activeRequest: ActiveRequest? = nil,
            activeRequests: [ActiveRequest]? = nil,
            queue: [QueuedRequest]? = nil,
            playbackState: PlaybackStateSnapshot? = nil,
            runtimeOverview: RuntimeOverview? = nil,
            status: StatusEvent? = nil,
            speechBackend: SpeechBackend? = nil,
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
            self.replacements = replacements
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

    // MARK: - Runtime Overview

    struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
        public let state: PlaybackState
        public let activeRequest: ActiveRequest?
        public let isStableForConcurrentGeneration: Bool
        public let isRebuffering: Bool
        public let stableBufferedAudioMS: Int?
        public let stableBufferTargetMS: Int?

        enum CodingKeys: String, CodingKey {
            case state
            case activeRequest = "active_request"
            case isStableForConcurrentGeneration = "is_stable_for_concurrent_generation"
            case isRebuffering = "is_rebuffering"
            case stableBufferedAudioMS = "stable_buffered_audio_ms"
            case stableBufferTargetMS = "stable_buffer_target_ms"
        }

        public init(
            state: PlaybackState,
            activeRequest: ActiveRequest?,
            isStableForConcurrentGeneration: Bool = false,
            isRebuffering: Bool = false,
            stableBufferedAudioMS: Int? = nil,
            stableBufferTargetMS: Int? = nil
        ) {
            self.state = state
            self.activeRequest = activeRequest
            self.isStableForConcurrentGeneration = isStableForConcurrentGeneration
            self.isRebuffering = isRebuffering
            self.stableBufferedAudioMS = stableBufferedAudioMS
            self.stableBufferTargetMS = stableBufferTargetMS
        }
    }

    struct RuntimeOverview: Encodable, Sendable, Equatable {
        public let status: StatusEvent?
        public let speechBackend: SpeechBackend
        public let generationQueue: QueueSnapshot
        public let playbackQueue: QueueSnapshot
        public let playbackState: PlaybackStateSnapshot

        enum CodingKeys: String, CodingKey {
            case status
            case speechBackend = "speech_backend"
            case generationQueue = "generation_queue"
            case playbackQueue = "playback_queue"
            case playbackState = "playback_state"
        }

        public init(
            status: StatusEvent?,
            speechBackend: SpeechBackend,
            generationQueue: QueueSnapshot,
            playbackQueue: QueueSnapshot,
            playbackState: PlaybackStateSnapshot
        ) {
            self.status = status
            self.speechBackend = speechBackend
            self.generationQueue = generationQueue
            self.playbackQueue = playbackQueue
            self.playbackState = playbackState
        }
    }

    // MARK: - Queue Models

    struct ActiveRequest: Codable, Sendable, Equatable {
        public let id: String
        public let op: String
        public let profileName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case profileName = "profile_name"
        }

        public init(id: String, op: String, profileName: String?) {
            self.id = id
            self.op = op
            self.profileName = profileName
        }
    }

    struct QueuedRequest: Codable, Sendable, Equatable {
        public let id: String
        public let op: String
        public let profileName: String?
        public let queuePosition: Int

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case profileName = "profile_name"
            case queuePosition = "queue_position"
        }

        public init(id: String, op: String, profileName: String?, queuePosition: Int) {
            self.id = id
            self.op = op
            self.profileName = profileName
            self.queuePosition = queuePosition
        }
    }

    // MARK: - Failures

    struct Failure: Encodable, Sendable, Equatable {
        public let id: String
        public let ok = false
        public let code: ErrorCode
        public let message: String

        public init(id: String, code: ErrorCode, message: String) {
            self.id = id
            self.code = code
            self.message = message
        }
    }

    enum ErrorCode: String, Codable, Sendable {
        case invalidJSON = "invalid_json"
        case invalidRequest = "invalid_request"
        case unknownOperation = "unknown_operation"
        case generatedFileNotFound = "generated_file_not_found"
        case generatedBatchNotFound = "generated_batch_not_found"
        case generatedFileAlreadyExists = "generated_file_already_exists"
        case generationJobNotFound = "generation_job_not_found"
        case generationJobAlreadyExists = "generation_job_already_exists"
        case generationJobNotExpirable = "generation_job_not_expirable"
        case profileNotFound = "profile_not_found"
        case profileAlreadyExists = "profile_already_exists"
        case invalidProfileName = "invalid_profile_name"
        case modelLoading = "model_loading"
        case modelGenerationFailed = "model_generation_failed"
        case requestCancelled = "request_cancelled"
        case workerShuttingDown = "worker_shutting_down"
        case audioPlaybackTimeout = "audio_playback_timeout"
        case audioPlaybackFailed = "audio_playback_failed"
        case requestNotFound = "request_not_found"
        case filesystemError = "filesystem_error"
        case internalError = "internal_error"
    }

    struct Error: Swift.Error, Sendable, Equatable {
        public let code: ErrorCode
        public let message: String

        public init(code: ErrorCode, message: String) {
            self.code = code
            self.message = message
        }
    }
}
