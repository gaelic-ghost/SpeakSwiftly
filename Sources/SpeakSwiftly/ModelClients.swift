import Foundation
@preconcurrency import MLX
import MLXAudioTTS

// MARK: - Model Client

private final class UnsafeSpeechGenerationModelBox: @unchecked Sendable {
    let model: any SpeechGenerationModel

    init(model: any SpeechGenerationModel) {
        self.model = model
    }
}

final class AnySpeechModel: @unchecked Sendable {
    private let sampleRateValue: Int
    private let generateImpl: @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?
    ) async throws -> [Float]
    private let generateSamplesStreamImpl: @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?,
        _ streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error>

    var sampleRate: Int {
        sampleRateValue
    }

    init(
        sampleRate: Int,
        generate: @escaping @Sendable (
            _ text: String,
            _ voice: String?,
            _ refAudio: MLXArray?,
            _ refText: String?,
            _ language: String?
        ) async throws -> [Float],
        generateSamplesStream: @escaping @Sendable (
            _ text: String,
            _ voice: String?,
            _ refAudio: MLXArray?,
            _ refText: String?,
            _ language: String?,
            _ streamingInterval: Double
        ) -> AsyncThrowingStream<[Float], Error>
    ) {
        sampleRateValue = sampleRate
        generateImpl = generate
        generateSamplesStreamImpl = generateSamplesStream
    }

    convenience init(model: any SpeechGenerationModel) {
        let box = UnsafeSpeechGenerationModelBox(model: model)

        self.init(
            sampleRate: box.model.sampleRate,
            generate: { text, voice, refAudio, refText, language in
                try await box.model.generate(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: nil
                ).asArray(Float.self)
            },
            generateSamplesStream: { text, voice, refAudio, refText, language, streamingInterval in
                box.model.generateSamplesStream(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: nil,
                    streamingInterval: streamingInterval
                )
            }
        )
    }

    func generate(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?
    ) async throws -> [Float] {
        try await generateImpl(text, voice, refAudio, refText, language)
    }

    func generateSamplesStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        generateSamplesStreamImpl(text, voice, refAudio, refText, language, streamingInterval)
    }
}

enum ModelFactory {
    static let residentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    static let profileModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

    static func loadResidentModel() async throws -> AnySpeechModel {
        try await loadModel(modelRepo: residentModelRepo)
    }

    static func loadProfileModel() async throws -> AnySpeechModel {
        try await loadModel(modelRepo: profileModelRepo)
    }

    private static func loadModel(modelRepo: String) async throws -> AnySpeechModel {
        let model = try await TTS.loadModel(modelRepo: modelRepo)
        return AnySpeechModel(model: model)
    }
}
