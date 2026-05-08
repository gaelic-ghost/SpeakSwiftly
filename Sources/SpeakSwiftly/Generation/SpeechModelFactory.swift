import Foundation
@preconcurrency import Metal
@preconcurrency import MLX
import MLXAudioSTT
import MLXAudioTTS
@preconcurrency import MLXLMCommon

enum ModelFactory {
    static let qwen06B4BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"
    static let qwen06B5BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-5bit"
    static let qwen06B6BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-6bit"
    static let qwen06B8BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    static let qwen06BBF16ResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    static let qwen17B4BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit"
    static let qwen17B5BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-5bit"
    static let qwen17B6BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit"
    static let qwen17B8BitResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
    static let qwen17BBF16ResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    static let qwenResidentModelRepo = qwen06B8BitResidentModelRepo
    static let chatterboxResidentModelRepo = "mlx-community/chatterbox-turbo-8bit"
    static let legacyQwenCustomVoiceResidentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"
    static let marvis4BitResidentModelRepo = "Marvis-AI/marvis-tts-250m-v0.2-MLX-4bit"
    static let marvis6BitResidentModelRepo = "Marvis-AI/marvis-tts-250m-v0.2-MLX-6bit"
    static let marvis8BitResidentModelRepo = "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
    static let marvisResidentModelRepo = marvis8BitResidentModelRepo
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
                 .qwen3_smol_4bit,
                 .qwen3_smol_5bit,
                 .qwen3_smol_6bit,
                 .qwen3_smol_8bit,
                 .qwen3_smol_bf16,
                 .qwen3_BIG,
                 .qwen3_BIG_4bit,
                 .qwen3_BIG_5bit,
                 .qwen3_BIG_6bit,
                 .qwen3_BIG_8bit,
                 .qwen3_BIG_bf16:
                return try await .qwen3(loadModel(modelRepo: residentModelRepo(for: backend)))
            case .chatterboxTurbo:
                return try await .chatterboxTurbo(loadModel(modelRepo: residentModelRepo(for: backend)))
            case .marvis, .marvis_4bit, .marvis_6bit:
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

    static func loadProfileModel(
        allowsCPUFallback: Bool = false,
        hasDefaultMetalDevice: @Sendable () -> Bool = defaultMetalDeviceIsAvailable,
        modelLoader: @Sendable (String) async throws -> AnySpeechModel = loadModel,
    ) async throws -> AnySpeechModel {
        guard hasDefaultMetalDevice() else {
            guard allowsCPUFallback else {
                throw WorkerError(
                    code: .modelLoading,
                    message: "SpeakSwiftly could not load the voice-design profile model because Metal did not provide a default GPU device for this process. Fix the launch context so Metal is available, or explicitly allow CPU profile-model fallback for system-profile authoring.",
                )
            }

            do {
                let model = try await Device.withDefaultDevice(.cpu) {
                    try await modelLoader(profileModelRepo)
                }
                return model.usingDefaultDevice(.cpu)
            } catch let workerError as WorkerError {
                throw workerError
            } catch {
                throw WorkerError(
                    code: .modelLoading,
                    message: "SpeakSwiftly could not load the voice-design profile model on the CPU fallback after Metal did not provide a default GPU device for this process. The profile model may be unavailable, unreadable, or unsupported in this launch context. \(error.localizedDescription)",
                )
            }
        }

        do {
            return try await modelLoader(profileModelRepo)
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .modelLoading,
                message: "SpeakSwiftly could not load the voice-design profile model. The profile model may be unavailable, unreadable, or unsupported in this launch context. \(error.localizedDescription)",
            )
        }
    }

    static func loadCloneTranscriptionModel() async throws -> AnyCloneTranscriptionModel {
        let model = try await GLMASRModel.fromPretrained(cloneTranscriptionModelRepo)
        return AnyCloneTranscriptionModel(model: model)
    }

    private static func loadModel(modelRepo: String) async throws -> AnySpeechModel {
        let model = try await TTS.loadModel(modelRepo: modelRepo)
        return AnySpeechModel(model: model)
    }

    private static func defaultMetalDeviceIsAvailable() -> Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
}
