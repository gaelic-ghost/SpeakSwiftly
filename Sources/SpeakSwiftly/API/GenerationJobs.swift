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
            case textProfile = "text_profile"
            case sourceFormat = "source_format"
            case requestContext = "request_context"
        }

        // MARK: Properties

        public let artifactID: String
        public let text: String
        public let textProfile: SpeakSwiftly.TextProfileID?
        public let sourceFormat: TextForSpeech.SourceFormat?
        public let requestContext: SpeakSwiftly.RequestContext?

        // MARK: Lifecycle

        init(
            artifactID: String,
            text: String,
            textProfile: SpeakSwiftly.TextProfileID?,
            sourceFormat: TextForSpeech.SourceFormat?,
            requestContext: SpeakSwiftly.RequestContext?,
        ) {
            self.artifactID = artifactID
            self.text = text
            self.textProfile = textProfile
            self.sourceFormat = sourceFormat
            self.requestContext = requestContext
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
            case voiceProfile = "voice_profile"
            case textProfile = "text_profile"
            case sourceFormat = "source_format"
            case requestContext = "request_context"
        }

        public let artifactID: String
        public let kind: GenerationArtifactKind
        public let createdAt: Date
        public let filePath: String
        public let sampleRate: Int
        public let voiceProfile: String
        public let textProfile: SpeakSwiftly.TextProfileID?
        public let sourceFormat: TextForSpeech.SourceFormat?
        public let requestContext: SpeakSwiftly.RequestContext?

        init(
            artifactID: String,
            kind: GenerationArtifactKind,
            createdAt: Date,
            filePath: String,
            sampleRate: Int,
            voiceProfile: String,
            textProfile: SpeakSwiftly.TextProfileID?,
            sourceFormat: TextForSpeech.SourceFormat?,
            requestContext: SpeakSwiftly.RequestContext?,
        ) {
            self.artifactID = artifactID
            self.kind = kind
            self.createdAt = createdAt
            self.filePath = filePath
            self.sampleRate = sampleRate
            self.voiceProfile = voiceProfile
            self.textProfile = textProfile
            self.sourceFormat = sourceFormat
            self.requestContext = requestContext
        }
    }

    /// A retained generation job snapshot.
    struct GenerationJob: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case jobKind = "job_kind"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case voiceProfile = "voice_profile"
            case textProfile = "text_profile"
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
        public let voiceProfile: String
        public let textProfile: SpeakSwiftly.TextProfileID?
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
            voiceProfile: String,
            textProfile: SpeakSwiftly.TextProfileID?,
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
            self.voiceProfile = voiceProfile
            self.textProfile = textProfile
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

    /// Clears queued generation work that has not started yet.
    func clearQueue() async -> SpeakSwiftly.RequestHandle {
        await runtime.clearQueue(.generation)
    }

    /// Cancels one queued or active generation request by identifier.
    func cancel(_ requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.cancel(.generation, requestID: requestID)
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
