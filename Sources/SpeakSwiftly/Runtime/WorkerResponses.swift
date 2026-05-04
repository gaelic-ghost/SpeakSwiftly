import Foundation
import TextForSpeech

// MARK: - Response Envelope

public extension SpeakSwiftly {
    enum RequestCompletion: Sendable, Equatable {
        case artifact(GenerationArtifact)
        case artifacts([GenerationArtifact])
        case generationJob(GenerationJob)
        case generationJobs([GenerationJob])
        case voiceProfile(name: String?, path: String?)
        case voiceProfiles([ProfileSummary])
        case textProfile(
            profile: SpeakSwiftly.TextProfileDetails?,
            profiles: [SpeakSwiftly.TextProfileSummary]?,
            styleOptions: [SpeakSwiftly.TextProfileStyleOption]?,
            activeStyle: TextForSpeech.BuiltInProfileStyle?,
            persistencePath: String?,
        )
        case queue(activeRequests: [ActiveRequest], queuedRequests: [QueuedRequest])
        case playbackState(PlaybackStateSnapshot)
        case runtimeOverview(RuntimeOverview)
        case runtimeStatus(status: StatusEvent?, speechBackend: SpeechBackend?)
        case defaultVoiceProfile(String)
        case queueCleared(count: Int)
        case requestCancelled(id: String)
        case empty

        init(_ success: Success) {
            if let generatedFile = success.generatedFile {
                self = .artifact(GenerationArtifact(generatedFile))
            } else if let generatedFiles = success.generatedFiles {
                self = .artifacts(generatedFiles.map(GenerationArtifact.init))
            } else if let generatedBatch = success.generatedBatch {
                self = .generationJob(GenerationJob(generatedBatch))
            } else if let generatedBatches = success.generatedBatches {
                self = .generationJobs(generatedBatches.map(GenerationJob.init))
            } else if let generationJob = success.generationJob {
                self = .generationJob(generationJob)
            } else if let generationJobs = success.generationJobs {
                self = .generationJobs(generationJobs)
            } else if success.profileName != nil || success.profilePath != nil {
                self = .voiceProfile(name: success.profileName, path: success.profilePath)
            } else if let profiles = success.profiles {
                self = .voiceProfiles(profiles)
            } else if success.textProfile != nil
                || success.textProfiles != nil
                || success.textProfileStyleOptions != nil
                || success.textProfileStyle != nil
                || success.textProfilePath != nil {
                self = .textProfile(
                    profile: success.textProfile,
                    profiles: success.textProfiles,
                    styleOptions: success.textProfileStyleOptions,
                    activeStyle: success.textProfileStyle,
                    persistencePath: success.textProfilePath,
                )
            } else if success.activeRequest != nil || success.activeRequests != nil || success.queue != nil {
                self = .queue(
                    activeRequests: success.resolvedActiveRequests,
                    queuedRequests: success.queue ?? [],
                )
            } else if let playbackState = success.playbackState {
                self = .playbackState(playbackState)
            } else if let runtimeOverview = success.runtimeOverview {
                self = .runtimeOverview(runtimeOverview)
            } else if success.status != nil || success.speechBackend != nil {
                self = .runtimeStatus(status: success.status, speechBackend: success.speechBackend)
            } else if let defaultVoiceProfile = success.defaultVoiceProfile {
                self = .defaultVoiceProfile(defaultVoiceProfile)
            } else if let clearedCount = success.clearedCount {
                self = .queueCleared(count: clearedCount)
            } else if let cancelledRequestID = success.cancelledRequestID {
                self = .requestCancelled(id: cancelledRequestID)
            } else {
                self = .empty
            }
        }
    }
}

extension SpeakSwiftly {
    struct Success: Encodable, Equatable {
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
            case defaultVoiceProfile = "default_voice_profile"
            case clearedCount = "cleared_count"
            case cancelledRequestID = "cancelled_request_id"
        }

        let id: String
        let ok = true
        let generatedFile: GeneratedFile?
        let generatedFiles: [GeneratedFile]?
        let generatedBatch: GeneratedBatch?
        let generatedBatches: [GeneratedBatch]?
        let generationJob: GenerationJob?
        let generationJobs: [GenerationJob]?
        let profileName: String?
        let profilePath: String?
        let profiles: [ProfileSummary]?
        let textProfile: SpeakSwiftly.TextProfileDetails?
        let textProfiles: [SpeakSwiftly.TextProfileSummary]?
        let textProfileStyleOptions: [SpeakSwiftly.TextProfileStyleOption]?
        let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
        let textProfilePath: String?
        let activeRequest: ActiveRequest?
        let activeRequests: [ActiveRequest]?
        let queue: [QueuedRequest]?
        let playbackState: PlaybackStateSnapshot?
        let runtimeOverview: RuntimeOverview?
        let status: StatusEvent?
        let speechBackend: SpeechBackend?
        let defaultVoiceProfile: String?
        let clearedCount: Int?
        let cancelledRequestID: String?

        var resolvedActiveRequests: [ActiveRequest] {
            if let activeRequests {
                return activeRequests
            }
            if let activeRequest {
                return [activeRequest]
            }
            return []
        }

        init(
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
            defaultVoiceProfile: String? = nil,
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
            self.defaultVoiceProfile = defaultVoiceProfile
            self.clearedCount = clearedCount
            self.cancelledRequestID = cancelledRequestID
        }
    }
}

public extension SpeakSwiftly {
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
