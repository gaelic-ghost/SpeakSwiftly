import Foundation

// MARK: - Generation Job API

public extension SpeakSwiftly {
    enum GenerationJobKind: String, Codable, Sendable, Equatable {
        case file
        case batch
    }

    enum GenerationJobState: String, Codable, Sendable, Equatable {
        case queued
        case running
        case completed
        case failed
        case expired
    }

    enum GenerationArtifactKind: String, Codable, Sendable, Equatable {
        case audioWAV = "audio_wav"
    }

    enum GenerationRetentionPolicy: String, Codable, Sendable, Equatable {
        case manual
    }

    struct GenerationJobFailure: Codable, Sendable, Equatable {
        public let code: String
        public let message: String

        enum CodingKeys: String, CodingKey {
            case code
            case message
        }

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    struct GenerationArtifact: Codable, Sendable, Equatable {
        public let artifactID: String
        public let kind: GenerationArtifactKind
        public let createdAt: Date
        public let filePath: String
        public let sampleRate: Int
        public let profileName: String
        public let textProfileName: String?

        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case kind
            case createdAt = "created_at"
            case filePath = "file_path"
            case sampleRate = "sample_rate"
            case profileName = "profile_name"
            case textProfileName = "text_profile_name"
        }

        public init(
            artifactID: String,
            kind: GenerationArtifactKind,
            createdAt: Date,
            filePath: String,
            sampleRate: Int,
            profileName: String,
            textProfileName: String?
        ) {
            self.artifactID = artifactID
            self.kind = kind
            self.createdAt = createdAt
            self.filePath = filePath
            self.sampleRate = sampleRate
            self.profileName = profileName
            self.textProfileName = textProfileName
        }
    }

    struct GenerationJob: Codable, Sendable, Equatable {
        public let jobID: String
        public let jobKind: GenerationJobKind
        public let createdAt: Date
        public let updatedAt: Date
        public let profileName: String
        public let textProfileName: String?
        public let speechBackend: SpeechBackend
        public let state: GenerationJobState
        public let text: String
        public let artifacts: [GenerationArtifact]
        public let failure: GenerationJobFailure?
        public let startedAt: Date?
        public let completedAt: Date?
        public let failedAt: Date?
        public let expiresAt: Date?
        public let retentionPolicy: GenerationRetentionPolicy

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case jobKind = "job_kind"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case profileName = "profile_name"
            case textProfileName = "text_profile_name"
            case speechBackend = "speech_backend"
            case state
            case text
            case artifacts
            case failure
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case failedAt = "failed_at"
            case expiresAt = "expires_at"
            case retentionPolicy = "retention_policy"
        }

        public init(
            jobID: String,
            jobKind: GenerationJobKind,
            createdAt: Date,
            updatedAt: Date,
            profileName: String,
            textProfileName: String?,
            speechBackend: SpeechBackend,
            state: GenerationJobState,
            text: String,
            artifacts: [GenerationArtifact],
            failure: GenerationJobFailure?,
            startedAt: Date?,
            completedAt: Date?,
            failedAt: Date?,
            expiresAt: Date?,
            retentionPolicy: GenerationRetentionPolicy
        ) {
            self.jobID = jobID
            self.jobKind = jobKind
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.profileName = profileName
            self.textProfileName = textProfileName
            self.speechBackend = speechBackend
            self.state = state
            self.text = text
            self.artifacts = artifacts
            self.failure = failure
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.failedAt = failedAt
            self.expiresAt = expiresAt
            self.retentionPolicy = retentionPolicy
        }
    }
}

public extension SpeakSwiftly.Runtime {
    func generationJob(
        id jobID: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.generationJob(id: requestID, jobID: jobID))
    }

    func generationJobs(
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.generationJobs(id: requestID))
    }
}
