import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

// MARK: - Marvis Speech Generation

extension SpeakSwiftly.Runtime {
    func marvisGenerationStream(
        model: AnySpeechModel,
        text: String,
        materialization: StoredProfileMaterialization,
        refAudio: MLXArray?,
        generationParameters: GenerateParameters,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        model.generateSamplesStream(
            text: text,
            voice: nil,
            refAudio: refAudio,
            refText: materialization.manifest.referenceText,
            language: nil,
            generationParameters: generationParameters,
            streamingInterval: streamingInterval
        )
    }
}
