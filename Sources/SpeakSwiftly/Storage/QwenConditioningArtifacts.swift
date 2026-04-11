import Foundation
@preconcurrency import MLX
import MLXAudioTTS

// MARK: - Qwen Conditioning Artifact Models

struct QwenConditioningArtifactManifest: Codable, Sendable, Equatable {
    let backend: SpeakSwiftly.SpeechBackend
    let modelRepo: String
    let createdAt: Date
    let artifactVersion: Int
    let artifactFile: String
}

struct StoredQwenConditioningArtifact: Sendable, Equatable {
    let manifest: QwenConditioningArtifactManifest
    let artifactURL: URL
}

struct QwenConditioningFloatTensor: Codable, Sendable, Equatable {
    let values: [Float]
    let shape: [Int]

    init(array: MLXArray) {
        values = array.asArray(Float.self)
        shape = array.shape.map { Int($0) }
    }

    func makeArray() -> MLXArray {
        MLXArray(values).reshaped(shape)
    }
}

struct QwenConditioningInt32Tensor: Codable, Sendable, Equatable {
    let values: [Int32]
    let shape: [Int]

    init(array: MLXArray) {
        values = array.asArray(Int32.self)
        shape = array.shape.map { Int($0) }
    }

    func makeArray() -> MLXArray {
        MLXArray(values).reshaped(shape)
    }
}

struct PersistedQwenConditioningArtifact: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let speakerEmbedding: QwenConditioningFloatTensor?
    let referenceSpeechCodes: QwenConditioningInt32Tensor
    let referenceTextTokenIDs: QwenConditioningInt32Tensor
    let resolvedLanguage: String
    let codecLanguageID: Int?

    init(conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning) {
        version = Self.currentVersion
        speakerEmbedding = conditioning.speakerEmbedding.map(QwenConditioningFloatTensor.init)
        referenceSpeechCodes = QwenConditioningInt32Tensor(array: conditioning.referenceSpeechCodes)
        referenceTextTokenIDs = QwenConditioningInt32Tensor(array: conditioning.referenceTextTokenIDs)
        resolvedLanguage = conditioning.resolvedLanguage
        codecLanguageID = conditioning.codecLanguageID
    }

    func makeConditioning() -> Qwen3TTSModel.Qwen3TTSReferenceConditioning {
        Qwen3TTSModel.Qwen3TTSReferenceConditioning(
            speakerEmbedding: speakerEmbedding?.makeArray(),
            referenceSpeechCodes: referenceSpeechCodes.makeArray(),
            referenceTextTokenIDs: referenceTextTokenIDs.makeArray(),
            resolvedLanguage: resolvedLanguage,
            codecLanguageID: codecLanguageID
        )
    }
}
