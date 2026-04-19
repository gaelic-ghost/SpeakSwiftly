import Foundation
import TextForSpeech

// MARK: - Response Envelope

public extension SpeakSwiftly {
    struct Success: Encodable, Sendable, Equatable {
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
            case textProfileStyleOptions = "text_profile_style_options"
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
        public let textProfile: SpeakSwiftly.TextProfileDetails?
        public let textProfiles: [SpeakSwiftly.TextProfileSummary]?
        public let textProfileStyleOptions: [SpeakSwiftly.TextProfileStyleOption]?
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
            textProfile: SpeakSwiftly.TextProfileDetails? = nil,
            textProfiles: [SpeakSwiftly.TextProfileSummary]? = nil,
            textProfileStyleOptions: [SpeakSwiftly.TextProfileStyleOption]? = nil,
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
