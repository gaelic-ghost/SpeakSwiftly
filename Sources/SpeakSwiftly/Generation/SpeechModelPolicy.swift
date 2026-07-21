import MLXAudioSTT
@preconcurrency import MLXLMCommon

enum GenerationPolicy {
    private static let qwenResidentMaxTokens = 4096
    private static let qwenTemperature: Float = 0.6
    private static let qwenTopP: Float = 0.9
    private static let qwenTopK = 50
    private static let qwenResidentRepetitionPenalty: Float = 1.05
    private static let cloneTranscriptionMaxTokens = 256
    private static let cloneTranscriptionChunkDuration: Float = 120.0
    private static let cloneTranscriptionMinimumChunkDuration: Float = 1.0

    static func residentParameters(
        for _: SpeakSwiftly.SpeechBackend,
        text _: String,
    ) -> GenerateParameters {
        GenerateParameters(
            maxTokens: qwenResidentMaxTokens,
            temperature: qwenTemperature,
            topP: qwenTopP,
            topK: qwenTopK,
            repetitionPenalty: qwenResidentRepetitionPenalty,
        )
    }

    static func profileModelParameters(for _: String) -> GenerateParameters {
        GenerateParameters(
            maxTokens: qwenResidentMaxTokens,
            temperature: qwenTemperature,
            topP: qwenTopP,
            topK: qwenTopK,
            repetitionPenalty: qwenResidentRepetitionPenalty,
        )
    }

#if DEBUG
    static func deterministicResidentParameters(
        for _: SpeakSwiftly.SpeechBackend,
        text _: String,
    ) -> GenerateParameters {
        GenerateParameters(
            maxTokens: qwenResidentMaxTokens,
            temperature: 0,
            topP: 1,
            topK: 1,
            repetitionPenalty: qwenResidentRepetitionPenalty,
        )
    }
#endif

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
