import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon
import TextForSpeech

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
        _ language: String?,
        _ generationParameters: GenerateParameters
    ) async throws -> [Float]
    private let generateSamplesStreamImpl: @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?,
        _ generationParameters: GenerateParameters,
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
            _ language: String?,
            _ generationParameters: GenerateParameters
        ) async throws -> [Float],
        generateSamplesStream: @escaping @Sendable (
            _ text: String,
            _ voice: String?,
            _ refAudio: MLXArray?,
            _ refText: String?,
            _ language: String?,
            _ generationParameters: GenerateParameters,
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
            generate: { text, voice, refAudio, refText, language, generationParameters in
                try await box.model.generate(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: generationParameters
                ).asArray(Float.self)
            },
            generateSamplesStream: { text, voice, refAudio, refText, language, generationParameters, streamingInterval in
                box.model.generateSamplesStream(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: generationParameters,
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
        language: String?,
        generationParameters: GenerateParameters
    ) async throws -> [Float] {
        try await generateImpl(text, voice, refAudio, refText, language, generationParameters)
    }

    func generateSamplesStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        generateSamplesStreamImpl(text, voice, refAudio, refText, language, generationParameters, streamingInterval)
    }
}

enum GenerationPolicy {
    private static let residentTemperature: Float = 0.9
    private static let residentTopP: Float = 1.0
    private static let residentRepetitionPenalty: Float = 1.05
    private static let profileTemperature: Float = 0.9
    private static let profileTopP: Float = 1.0
    private static let profileRepetitionPenalty: Float = 1.05

    static func residentParameters(for text: String) -> GenerateParameters {
        GenerateParameters(
            maxTokens: residentMaxTokens(for: text),
            temperature: residentTemperature,
            topP: residentTopP,
            repetitionPenalty: residentRepetitionPenalty
        )
    }

    static func profileParameters(for text: String) -> GenerateParameters {
        GenerateParameters(
            maxTokens: profileMaxTokens(for: text),
            temperature: profileTemperature,
            topP: profileTopP,
            repetitionPenalty: profileRepetitionPenalty
        )
    }

    private static func residentMaxTokens(for text: String) -> Int {
        let wordCount = max(TextForSpeech.words(in: text).count, 1)
        return min(2_048, max(56, wordCount * 8))
    }

    private static func profileMaxTokens(for text: String) -> Int {
        let wordCount = max(TextForSpeech.words(in: text).count, 1)
        return min(3_072, max(96, wordCount * 10))
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
