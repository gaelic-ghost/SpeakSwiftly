import Foundation
import TextForSpeech

// MARK: - Generated Batch API

public extension SpeakSwiftly {
    // MARK: Batch Input

    /// One batch-generation item to synthesize under a shared voice profile.
    struct BatchItem: Codable, Sendable, Equatable {
        // MARK: Nested Types

        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
            case text
            case textProfileID = "text_profile_id"
            case textContext = "text_context"
            case sourceFormat = "source_format"
        }

        // MARK: Properties

        public let artifactID: String?
        public let text: String
        public let textProfileID: String?
        public let textContext: TextForSpeech.Context?
        public let sourceFormat: TextForSpeech.SourceFormat?

        // MARK: Lifecycle

        public init(
            artifactID: String? = nil,
            text: String,
            textProfileID: String? = nil,
            textContext: TextForSpeech.Context? = nil,
            sourceFormat: TextForSpeech.SourceFormat? = nil,
        ) {
            self.artifactID = artifactID
            self.text = text
            self.textProfileID = textProfileID
            self.textContext = textContext
            self.sourceFormat = sourceFormat
        }
    }

    // MARK: Batch Output

    /// A retained batch-generation snapshot.
    struct GeneratedBatch: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case batchID = "batch_id"
            case profileName = "profile_name"
            case textProfileID = "text_profile_id"
            case speechBackend = "speech_backend"
            case state
            case items
            case artifacts
            case failure
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case failedAt = "failed_at"
            case expiresAt = "expires_at"
            case retentionPolicy = "retention_policy"
        }

        public let batchID: String
        public let profileName: String
        public let textProfileID: String?
        public let speechBackend: SpeechBackend
        public let state: GenerationJobState
        public let items: [GenerationJobItem]
        public let artifacts: [GeneratedFile]
        public let failure: GenerationJobFailure?
        public let createdAt: Date
        public let updatedAt: Date
        public let startedAt: Date?
        public let completedAt: Date?
        public let failedAt: Date?
        public let expiresAt: Date?
        public let retentionPolicy: GenerationRetentionPolicy

        init(
            batchID: String,
            profileName: String,
            textProfileID: String?,
            speechBackend: SpeechBackend,
            state: GenerationJobState,
            items: [GenerationJobItem],
            artifacts: [GeneratedFile],
            failure: GenerationJobFailure?,
            createdAt: Date,
            updatedAt: Date,
            startedAt: Date?,
            completedAt: Date?,
            failedAt: Date?,
            expiresAt: Date?,
            retentionPolicy: GenerationRetentionPolicy,
        ) {
            self.batchID = batchID
            self.profileName = profileName
            self.textProfileID = textProfileID
            self.speechBackend = speechBackend
            self.state = state
            self.items = items
            self.artifacts = artifacts
            self.failure = failure
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.failedAt = failedAt
            self.expiresAt = expiresAt
            self.retentionPolicy = retentionPolicy
        }
    }
}

public extension SpeakSwiftly.Artifacts {
    // MARK: Batch Queries

    /// Fetches one retained generated batch by identifier.
    func batch(id batchID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedBatch(id: UUID().uuidString, batchID: batchID))
    }

    /// Lists the retained generated batches known to the runtime.
    func batches() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedBatches(id: UUID().uuidString))
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Batch Helpers

    /// Resolves batch items into retained job items with concrete artifact identifiers.
    static func resolveBatchItems(
        _ items: [SpeakSwiftly.BatchItem],
        batchID: String,
    ) -> [SpeakSwiftly.GenerationJobItem] {
        items.enumerated().map { index, item in
            SpeakSwiftly.GenerationJobItem(
                artifactID: item.artifactID ?? "\(batchID)-artifact-\(index + 1)",
                text: item.text,
                textProfileID: item.textProfileID,
                textContext: item.textContext,
                sourceFormat: item.sourceFormat,
            )
        }
    }
}
