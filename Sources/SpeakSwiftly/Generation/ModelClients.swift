import Foundation
@preconcurrency import MLX
import MLXAudioSTT
import MLXAudioTTS
@preconcurrency import MLXLMCommon

enum GenerationPolicy {
    private static let qwenResidentMaxTokens = 4096
    private static let qwenResidentTemperature: Float = 0.9
    private static let qwenResidentTopP: Float = 1.0
    private static let qwenResidentRepetitionPenalty: Float = 1.05
    private static let chatterboxResidentTemperature: Float = 0.9
    private static let chatterboxResidentTopP: Float = 1.0
    private static let profileTemperature: Float = 0.9
    private static let profileTopP: Float = 1.0
    private static let profileRepetitionPenalty: Float = 1.05
    private static let cloneTranscriptionMaxTokens = 256
    private static let cloneTranscriptionChunkDuration: Float = 120.0
    private static let cloneTranscriptionMinimumChunkDuration: Float = 1.0

    static func residentParameters(
        for backend: SpeakSwiftly.SpeechBackend,
        text _: String,
    ) -> GenerateParameters {
        switch backend {
            case .qwen3:
                GenerateParameters(
                    maxTokens: qwenResidentMaxTokens,
                    temperature: qwenResidentTemperature,
                    topP: qwenResidentTopP,
                    repetitionPenalty: qwenResidentRepetitionPenalty,
                )
            case .chatterboxTurbo:
                // Current mlx-audio-swift Chatterbox Turbo computes its own max-token
                // cap and hardcodes repetition penalty internally, so only pass the
                // knobs that upstream actually reads from the caller surface.
                GenerateParameters(
                    temperature: chatterboxResidentTemperature,
                    topP: chatterboxResidentTopP,
                )
            case .marvis:
                // Current mlx-audio-swift Marvis ignores caller-supplied generation
                // parameters and samples with its own internal settings.
                GenerateParameters()
        }
    }

    static func profileModelParameters(for _: String) -> GenerateParameters {
        GenerateParameters(
            maxTokens: qwenResidentMaxTokens,
            temperature: profileTemperature,
            topP: profileTopP,
            repetitionPenalty: profileRepetitionPenalty,
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
            minChunkDuration: cloneTranscriptionMinimumChunkDuration,
        )
    }
}

enum ModelFactory {
    static let qwenResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    static let chatterboxResidentModelRepo = "mlx-community/chatterbox-turbo-8bit"
    static let legacyQwenCustomVoiceResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
    static let marvisResidentModelRepo = "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
    static let profileModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
    static let cloneTranscriptionModelRepo = "mlx-community/GLM-ASR-Nano-2512-4bit"
    static let canonicalProfileSampleRate = 24000
    static let cloneTranscriptionSampleRate = 16000
    static let importedCloneModelRepo = "SpeakSwiftly/imported-reference-audio"
    static let importedCloneVoiceDescription = "Imported reference audio clone."

    static func loadResidentModels(for backend: SpeakSwiftly.SpeechBackend) async throws -> ResidentSpeechModels {
        switch backend {
            case .qwen3:
                return try await .qwen3(loadModel(modelRepo: residentModelRepo(for: backend)))
            case .chatterboxTurbo:
                return try await .chatterboxTurbo(loadModel(modelRepo: residentModelRepo(for: backend)))
            case .marvis:
                // Marvis keeps mutable generation caches on the model instance, so each
                // resident lane needs its own model object even though both lanes load
                // the same published weights.
                async let conversationalA = loadModel(modelRepo: residentModelRepo(for: backend))
                async let conversationalB = loadModel(modelRepo: residentModelRepo(for: backend))
                return try await .marvis(
                    MarvisResidentModels(
                        conversationalA: conversationalA,
                        conversationalB: conversationalB,
                    ),
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
