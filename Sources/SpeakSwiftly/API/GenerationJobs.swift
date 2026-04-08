import Foundation
import TextForSpeech

// MARK: - Generation Job API

public extension SpeakSwiftly {
    struct GenerationJobItem: Codable, Sendable, Equatable {
        public let artifactID: String
        public let text: String
        public let textProfileName: String?
        public let textContext: TextForSpeech.Context?
        public let sourceFormat: TextForSpeech.SourceFormat?

        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case text
            case textProfileName = "text_profile_name"
            case textContext = "text_context"
            case sourceFormat = "source_format"
        }

        init(
            artifactID: String,
            text: String,
            textProfileName: String?,
            textContext: TextForSpeech.Context?,
            sourceFormat: TextForSpeech.SourceFormat?
        ) {
            self.artifactID = artifactID
            self.text = text
            self.textProfileName = textProfileName
            self.textContext = textContext
            self.sourceFormat = sourceFormat
        }
    }

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

        init(code: String, message: String) {
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

        init(
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
        public let items: [GenerationJobItem]
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
            case items
            case artifacts
            case failure
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case failedAt = "failed_at"
            case expiresAt = "expires_at"
            case retentionPolicy = "retention_policy"
        }

        init(
            jobID: String,
            jobKind: GenerationJobKind,
            createdAt: Date,
            updatedAt: Date,
            profileName: String,
            textProfileName: String?,
            speechBackend: SpeechBackend,
            state: GenerationJobState,
            items: [GenerationJobItem],
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
            self.items = items
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

public extension SpeakSwiftly {
    struct Jobs: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    nonisolated var jobs: SpeakSwiftly.Jobs {
        SpeakSwiftly.Jobs(runtime: self)
    }
}

public extension SpeakSwiftly.Jobs {
    func generationQueue() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: UUID().uuidString, queueType: .generation))
    }

    func expire(id jobID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.expireGenerationJob(id: UUID().uuidString, jobID: jobID))
    }

    func job(id jobID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generationJob(id: UUID().uuidString, jobID: jobID))
    }

    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generationJobs(id: UUID().uuidString))
    }
}
