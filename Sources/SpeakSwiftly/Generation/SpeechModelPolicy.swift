import MLXAudioSTT
@preconcurrency import MLXLMCommon

enum GenerationPolicy {
    private static let qwenResidentMaxTokens = 4096
    private static let qwenResidentTemperature: Float = 0.9
    private static let qwenResidentTopP: Float = 1.0
    private static let qwenResidentRepetitionPenalty: Float = 1.05
    private static let chatterboxResidentTemperature: Float = 0.8
    private static let chatterboxResidentTopP: Float = 0.8
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
