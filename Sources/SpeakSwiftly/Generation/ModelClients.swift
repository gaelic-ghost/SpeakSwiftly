import Foundation
@preconcurrency import MLX
import MLXAudioSTT
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

private final class UnsafeCloneTranscriptionModelBox: @unchecked Sendable {
    let model: GLMASRModel

    init(model: GLMASRModel) {
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

final class AnyCloneTranscriptionModel: @unchecked Sendable {
    private let sampleRateValue: Int
    private let transcribeImpl: @Sendable (
        _ audio: [Float],
        _ generationParameters: STTGenerateParameters
    ) -> String

    var sampleRate: Int {
        sampleRateValue
    }

    init(
        sampleRate: Int,
        transcribe: @escaping @Sendable (
            _ audio: [Float],
            _ generationParameters: STTGenerateParameters
        ) -> String
    ) {
        sampleRateValue = sampleRate
        transcribeImpl = transcribe
    }

    convenience init(model: GLMASRModel) {
        let box = UnsafeCloneTranscriptionModelBox(model: model)

        self.init(
            sampleRate: ModelFactory.cloneTranscriptionSampleRate,
            transcribe: { audio, generationParameters in
                box.model.generate(
                    audio: MLXArray(audio),
                    generationParameters: generationParameters
                ).text
            }
        )
    }

    func transcribe(
        audio: [Float],
        generationParameters: STTGenerateParameters
    ) -> String {
        transcribeImpl(audio, generationParameters)
    }
}

enum GenerationPolicy {
    private static let residentTemperature: Float = 0.9
    private static let residentTopP: Float = 1.0
    private static let residentRepetitionPenalty: Float = 1.05
    private static let profileTemperature: Float = 0.9
    private static let profileTopP: Float = 1.0
    private static let profileRepetitionPenalty: Float = 1.05
    private static let cloneTranscriptionMaxTokens = 256
    private static let cloneTranscriptionChunkDuration: Float = 120.0
    private static let cloneTranscriptionMinimumChunkDuration: Float = 1.0

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

    static func cloneTranscriptionParameters() -> STTGenerateParameters {
        STTGenerateParameters(
            maxTokens: cloneTranscriptionMaxTokens,
            temperature: 0.0,
            topP: 0.95,
            topK: 0,
            verbose: false,
            language: "English",
            chunkDuration: cloneTranscriptionChunkDuration,
            minChunkDuration: cloneTranscriptionMinimumChunkDuration
        )
    }

    private static func residentMaxTokens(for text: String) -> Int {
        let wordCount = max(TextForSpeech.Forensics.words(in: text).count, 1)
        return min(2_048, max(56, wordCount * 8))
    }

    private static func profileMaxTokens(for text: String) -> Int {
        let wordCount = max(TextForSpeech.Forensics.words(in: text).count, 1)
        return min(3_072, max(96, wordCount * 10))
    }
}

enum ModelFactory {
    static let qwenResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    static let marvisResidentModelRepo = "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
    static let profileModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
    static let cloneTranscriptionModelRepo = "mlx-community/GLM-ASR-Nano-2512-4bit"
    static let canonicalProfileSampleRate = 24_000
    static let cloneTranscriptionSampleRate = 16_000
    static let importedCloneModelRepo = "SpeakSwiftly/imported-reference-audio"
    static let importedCloneVoiceDescription = "Imported reference audio clone."

    static func loadResidentModels(for backend: SpeakSwiftly.SpeechBackend) async throws -> ResidentSpeechModels {
        switch backend {
        case .qwen3:
            return .qwen3(try await loadModel(modelRepo: residentModelRepo(for: backend)))
        case .marvis:
            async let conversationalA = loadModel(modelRepo: residentModelRepo(for: backend))
            async let conversationalB = loadModel(modelRepo: residentModelRepo(for: backend))
            return .marvis(
                MarvisResidentModels(
                    conversationalA: try await conversationalA,
                    conversationalB: try await conversationalB
                )
            )
        }
    }

    static func residentModelRepo(for backend: SpeakSwiftly.SpeechBackend) -> String {
        backend.residentModelRepo
    }

    static func loadProfileModel() async throws -> AnySpeechModel {
        try await loadModel(modelRepo: profileModelRepo)
    }

    static func loadCloneTranscriptionModel() async throws -> AnyCloneTranscriptionModel {
        let model = try await GLMASRModel.fromPretrained(cloneTranscriptionModelRepo)
        return AnyCloneTranscriptionModel(model: model)
    }

    private static func loadModel(modelRepo: String) async throws -> AnySpeechModel {
        let model = try await TTS.loadModel(modelRepo: modelRepo)
        return AnySpeechModel(model: model)
    }
}
