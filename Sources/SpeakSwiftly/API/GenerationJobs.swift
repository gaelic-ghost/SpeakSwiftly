import Foundation
import TextForSpeech

// MARK: - Generation Job API

public extension SpeakSwiftly {
    // MARK: Job Models

    /// One generation item recorded inside a retained file or batch job.
    struct GenerationJobItem: Codable, Sendable, Equatable {
        // MARK: Nested Types

        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case text
            case textProfileID = "text_profile_id"
            case textContext = "text_context"
            case sourceFormat = "source_format"
        }

        // MARK: Properties

        public let artifactID: String
        public let text: String
        public let textProfileID: String?
        public let textContext: TextForSpeech.Context?
        public let sourceFormat: TextForSpeech.SourceFormat?

        // MARK: Lifecycle

        init(
            artifactID: String,
            text: String,
            textProfileID: String?,
            textContext: TextForSpeech.Context?,
            sourceFormat: TextForSpeech.SourceFormat?,
        ) {
            self.artifactID = artifactID
            self.text = text
            self.textProfileID = textProfileID
            self.textContext = textContext
            self.sourceFormat = sourceFormat
        }
    }

    /// The retained job family for a generation request.
    enum GenerationJobKind: String, Codable, Sendable, Equatable {
        case file
        case batch
    }

    /// The lifecycle state of a retained generation job.
    enum GenerationJobState: String, Codable, Sendable, Equatable {
        case queued
        case running
        case completed
        case failed
        case expired
    }

    /// The retained artifact type produced by a generation job.
    enum GenerationArtifactKind: String, Codable, Sendable, Equatable {
        case audioWAV = "audio_wav"
    }

    /// The retention behavior applied to a generated artifact or job.
    enum GenerationRetentionPolicy: String, Codable, Sendable, Equatable {
        case manual
    }

    /// Failure details recorded on a retained generation job.
    struct GenerationJobFailure: Codable, Sendable, Equatable {
        // MARK: Nested Types

        enum CodingKeys: String, CodingKey {
            case code
            case message
        }

        // MARK: Properties

        public let code: String
        public let message: String

        // MARK: Lifecycle

        init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    /// Metadata for one retained generated artifact.
    struct GenerationArtifact: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case kind
            case createdAt = "created_at"
            case filePath = "file_path"
            case sampleRate = "sample_rate"
            case profileName = "profile_name"
            case textProfileID = "text_profile_id"
        }

        public let artifactID: String
        public let kind: GenerationArtifactKind
        public let createdAt: Date
        public let filePath: String
        public let sampleRate: Int
        public let profileName: String
        public let textProfileID: String?

        init(
            artifactID: String,
            kind: GenerationArtifactKind,
            createdAt: Date,
            filePath: String,
            sampleRate: Int,
            profileName: String,
            textProfileID: String?,
        ) {
            self.artifactID = artifactID
            self.kind = kind
            self.createdAt = createdAt
            self.filePath = filePath
            self.sampleRate = sampleRate
            self.profileName = profileName
            self.textProfileID = textProfileID
        }
    }

    /// A retained generation job snapshot.
    struct GenerationJob: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case jobKind = "job_kind"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case profileName = "profile_name"
            case textProfileID = "text_profile_id"
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

        public let jobID: String
        public let jobKind: GenerationJobKind
        public let createdAt: Date
        public let updatedAt: Date
        public let profileName: String
        public let textProfileID: String?
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

        init(
            jobID: String,
            jobKind: GenerationJobKind,
            createdAt: Date,
            updatedAt: Date,
            profileName: String,
            textProfileID: String?,
            speechBackend: SpeechBackend,
            state: GenerationJobState,
            items: [GenerationJobItem],
            artifacts: [GenerationArtifact],
            failure: GenerationJobFailure?,
            startedAt: Date?,
            completedAt: Date?,
            failedAt: Date?,
            expiresAt: Date?,
            retentionPolicy: GenerationRetentionPolicy,
        ) {
            self.jobID = jobID
            self.jobKind = jobKind
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.profileName = profileName
            self.textProfileID = textProfileID
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
    // MARK: Jobs Handle

    /// Accesses retained generation jobs and the generation queue.
    struct Jobs: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the generation-job surface for this runtime.
    nonisolated var jobs: SpeakSwiftly.Jobs {
        SpeakSwiftly.Jobs(runtime: self)
    }
}

public extension SpeakSwiftly.Jobs {
    // MARK: Operations

    /// Lists queued and active generation work.
    func generationQueue() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: UUID().uuidString, queueType: .generation))
    }

    /// Expires one retained generation job.
    func expire(id jobID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.expireGenerationJob(id: UUID().uuidString, jobID: jobID))
    }

    /// Fetches one retained generation job by identifier.
    func job(id jobID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generationJob(id: UUID().uuidString, jobID: jobID))
    }

    /// Lists the retained generation jobs known to the runtime.
    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generationJobs(id: UUID().uuidString))
    }
}
