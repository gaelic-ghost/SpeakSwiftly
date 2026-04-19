@preconcurrency import MLX
import MLXAudioSTT

private final class UnsafeCloneTranscriptionModelBox: @unchecked Sendable {
    let model: GLMASRModel

    init(model: GLMASRModel) {
        self.model = model
    }
}

final class AnyCloneTranscriptionModel: @unchecked Sendable {
    private let sampleRateValue: Int
    private let transcribeImpl: @Sendable (
        _ audio: [Float],
        _ generationParameters: STTGenerateParameters,
    ) -> String

    var sampleRate: Int {
        sampleRateValue
    }

    init(
        sampleRate: Int,
        transcribe: @escaping @Sendable (
            _ audio: [Float],
            _ generationParameters: STTGenerateParameters,
        ) -> String,
    ) {
        sampleRateValue = sampleRate
        transcribeImpl = transcribe
    }

    convenience init(model: GLMASRModel) {
        let box = UnsafeCloneTranscriptionModelBox(model: model)

        self.init(
            sampleRate: ModelFactory.cloneTranscriptionSampleRate,
            transcribe: { audio, generationParameters in
                box.model
                    .generate(
                        audio: MLXArray(audio),
                        generationParameters: generationParameters,
                    )
                    .text
            },
        )
    }

    func transcribe(
        audio: [Float],
        generationParameters: STTGenerateParameters,
    ) -> String {
        transcribeImpl(audio, generationParameters)
    }
}
