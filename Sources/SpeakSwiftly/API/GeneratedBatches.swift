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
            case textProfile = "text_profile"
            case sourceFormat = "source_format"
            case requestContext = "request_context"
        }

        // MARK: Properties

        public let artifactID: String?
        public let text: String
        public let textProfile: SpeakSwiftly.TextProfileID?
        public let sourceFormat: TextForSpeech.SourceFormat?
        public let requestContext: SpeakSwiftly.RequestContext?

        // MARK: Lifecycle

        public init(
            artifactID: String? = nil,
            text: String,
            textProfile: SpeakSwiftly.TextProfileID? = nil,
            sourceFormat: TextForSpeech.SourceFormat? = nil,
            requestContext: SpeakSwiftly.RequestContext? = nil,
        ) {
            self.artifactID = artifactID
            self.text = text
            self.textProfile = textProfile
            self.sourceFormat = sourceFormat
            self.requestContext = requestContext
        }
    }
}

extension SpeakSwiftly {
    // MARK: Batch Output

    /// A JSONL compatibility projection for retained batch-generation responses.
    struct GeneratedBatch: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case batchID = "batch_id"
            case voiceProfile = "voice_profile"
            case textProfile = "text_profile"
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

        let batchID: String
        let voiceProfile: String
        let textProfile: SpeakSwiftly.TextProfileID?
        let speechBackend: SpeechBackend
        let state: GenerationJobState
        let items: [GenerationJobItem]
        let artifacts: [GeneratedFile]
        let failure: GenerationJobFailure?
        let createdAt: Date
        let updatedAt: Date
        let startedAt: Date?
        let completedAt: Date?
        let failedAt: Date?
        let expiresAt: Date?
        let retentionPolicy: GenerationRetentionPolicy

        init(
            batchID: String,
            voiceProfile: String,
            textProfile: SpeakSwiftly.TextProfileID?,
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
            self.voiceProfile = voiceProfile
            self.textProfile = textProfile
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

extension SpeakSwiftly.Runtime {
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
                textProfile: item.textProfile,
                sourceFormat: item.sourceFormat,
                requestContext: item.requestContext,
            )
        }
    }
}

extension SpeakSwiftly.GenerationArtifact {
    init(_ generatedFile: SpeakSwiftly.GeneratedFile) {
        self.init(
            artifactID: generatedFile.artifactID,
            kind: .audioWAV,
            createdAt: generatedFile.createdAt,
            filePath: generatedFile.filePath,
            sampleRate: generatedFile.sampleRate,
            voiceProfile: generatedFile.voiceProfile,
            textProfile: generatedFile.textProfile,
            sourceFormat: generatedFile.sourceFormat,
            requestContext: generatedFile.requestContext,
        )
    }
}

extension SpeakSwiftly.GenerationJob {
    init(_ generatedBatch: SpeakSwiftly.GeneratedBatch) {
        self.init(
            jobID: generatedBatch.batchID,
            jobKind: .batch,
            createdAt: generatedBatch.createdAt,
            updatedAt: generatedBatch.updatedAt,
            voiceProfile: generatedBatch.voiceProfile,
            textProfile: generatedBatch.textProfile,
            speechBackend: generatedBatch.speechBackend,
            state: generatedBatch.state,
            items: generatedBatch.items,
            artifacts: generatedBatch.artifacts.map(SpeakSwiftly.GenerationArtifact.init),
            failure: generatedBatch.failure,
            startedAt: generatedBatch.startedAt,
            completedAt: generatedBatch.completedAt,
            failedAt: generatedBatch.failedAt,
            expiresAt: generatedBatch.expiresAt,
            retentionPolicy: generatedBatch.retentionPolicy,
        )
    }
}
