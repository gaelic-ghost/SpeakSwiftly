import Foundation
import TextForSpeech

// MARK: - Generated Batch API

public extension SpeakSwiftly {
    struct BatchItem: Codable, Sendable, Equatable {
        public let artifactID: String?
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

        public init(
            artifactID: String? = nil,
            text: String,
            textProfileName: String? = nil,
            textContext: TextForSpeech.Context? = nil,
            sourceFormat: TextForSpeech.SourceFormat? = nil
        ) {
            self.artifactID = artifactID
            self.text = text
            self.textProfileName = textProfileName
            self.textContext = textContext
            self.sourceFormat = sourceFormat
        }
    }

    struct GeneratedBatch: Codable, Sendable, Equatable {
        public let batchID: String
        public let profileName: String
        public let textProfileName: String?
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

        enum CodingKeys: String, CodingKey {
            case batchID = "batch_id"
            case profileName = "profile_name"
            case textProfileName = "text_profile_name"
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

        public init(
            batchID: String,
            profileName: String,
            textProfileName: String?,
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
            retentionPolicy: GenerationRetentionPolicy
        ) {
            self.batchID = batchID
            self.profileName = profileName
            self.textProfileName = textProfileName
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
    func batch(
        id batchID: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedBatch(id: requestID, batchID: batchID))
    }

    func batches(
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedBatches(id: requestID))
    }
}

public extension SpeakSwiftly.Runtime {
    static func resolveBatchItems(
        _ items: [SpeakSwiftly.BatchItem],
        batchID: String
    ) -> [SpeakSwiftly.GenerationJobItem] {
        items.enumerated().map { index, item in
            SpeakSwiftly.GenerationJobItem(
                artifactID: item.artifactID ?? "\(batchID)-artifact-\(index + 1)",
                text: item.text,
                textProfileName: item.textProfileName,
                textContext: item.textContext,
                sourceFormat: item.sourceFormat
            )
        }
    }
}
