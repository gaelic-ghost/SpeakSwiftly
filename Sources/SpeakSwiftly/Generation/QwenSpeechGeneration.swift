import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

// MARK: - Qwen Speech Generation

extension SpeakSwiftly.Runtime {
    func qwenGenerationStream(
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
            language: "English",
            generationParameters: generationParameters,
            streamingInterval: streamingInterval
        )
    }
}
