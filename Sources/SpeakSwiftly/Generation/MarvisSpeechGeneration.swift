import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

// MARK: - Marvis Speech Generation

extension SpeakSwiftly.Runtime {
    func marvisGenerationStream(
        model: AnySpeechModel,
        text: String,
        voice: MarvisResidentVoice,
        generationParameters: GenerateParameters,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        model.generateSamplesStream(
            text: text,
            voice: voice.rawValue,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: generationParameters,
            streamingInterval: streamingInterval
        )
    }
}
