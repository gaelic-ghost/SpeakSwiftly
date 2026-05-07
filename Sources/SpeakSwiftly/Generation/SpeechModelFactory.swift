import Foundation
@preconcurrency import MLX
import MLXAudioSTT
import MLXAudioTTS
@preconcurrency import MLXLMCommon

enum ModelFactory {
    static let qwen06B6BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-6bit"
    static let qwen06B8BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    static let qwen06BBF16ResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    static let qwen17B6BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit"
    static let qwen17B8BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
    static let qwen17BBF16ResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    static let qwenResidentModelRepo = qwen06B8BitResidentModelRepo
    static let chatterboxResidentModelRepo = "mlx-community/chatterbox-turbo-8bit"
    static let legacyQwenCustomVoiceResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
    static let marvisResidentModelRepo = "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
    static let profileModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
    static let cloneTranscriptionModelRepo = "mlx-community/GLM-ASR-Nano-2512-4bit"
    static let canonicalProfileSampleRate = 24000
    static let profileReferenceTargetPeakAmplitude: Float = 0.95
    static let cloneTranscriptionSampleRate = 16000
    static let importedCloneModelRepo = "SpeakSwiftly/imported-reference-audio"
    static let importedCloneVoiceDescription = "Imported reference audio clone."

    static func loadResidentModels(
        for backend: SpeakSwiftly.SpeechBackend,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy,
    ) async throws -> ResidentSpeechModels {
        switch backend {
            case .qwen3_smol,
                 .qwen3_smol_6bit,
                 .qwen3_smol_8bit,
                 .qwen3_smol_bf16,
                 .qwen3_BIG,
                 .qwen3_BIG_6bit,
                 .qwen3_BIG_8bit,
                 .qwen3_BIG_bf16:
                return try await .qwen3(loadModel(modelRepo: residentModelRepo(for: backend)))
            case .chatterboxTurbo:
                return try await .chatterboxTurbo(loadModel(modelRepo: residentModelRepo(for: backend)))
            case .marvis:
                switch marvisResidentPolicy {
                    case .dualResidentSerialized:
                        // Marvis keeps mutable generation caches on the model instance,
                        // so this policy warms one model object per conversational
                        // voice while runtime scheduling still serializes generation.
                        async let conversationalA = loadModel(modelRepo: residentModelRepo(for: backend))
                        async let conversationalB = loadModel(modelRepo: residentModelRepo(for: backend))
                        return try await .marvis(
                            .dual(
                                conversationalA: conversationalA,
                                conversationalB: conversationalB,
                            ),
                        )
                    case .singleResidentDynamic:
                        let model = try await loadModel(modelRepo: residentModelRepo(for: backend))
                        return .marvis(.single(model))
                }
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
