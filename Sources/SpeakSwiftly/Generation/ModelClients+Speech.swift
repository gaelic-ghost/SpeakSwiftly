import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon

// MARK: - UnsafeSpeechGenerationModelBox

private final class UnsafeSpeechGenerationModelBox: @unchecked Sendable {
    let model: any SpeechGenerationModel

    init(model: any SpeechGenerationModel) {
        self.model = model
    }
}

// MARK: - ModelGenerationEvent

enum ModelGenerationEvent: Equatable {
    struct Info: Equatable {
        let promptTokenCount: Int
        let generationTokenCount: Int
        let prefillTime: TimeInterval
        let generateTime: TimeInterval
        let tokensPerSecond: Double
        let peakMemoryUsage: Double
    }

    case token(Int)
    case info(Info)
    case audio([Float])
}

// MARK: - AnySpeechModel

final class AnySpeechModel: @unchecked Sendable {
    typealias GenerateSamplesStreamClosure = @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?,
        _ generationParameters: GenerateParameters,
        _ streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error>

    typealias GenerateEventStreamClosure = @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?,
        _ generationParameters: GenerateParameters,
        _ streamingInterval: Double,
    ) -> AsyncThrowingStream<ModelGenerationEvent, Error>

    typealias PrepareQwenReferenceConditioningClosure = @Sendable (
        _ refAudio: MLXArray,
        _ refText: String,
        _ language: String?,
    ) throws -> Qwen3TTSModel.Qwen3TTSReferenceConditioning

    typealias GenerateConditionedEventStreamClosure = @Sendable (
        _ text: String,
        _ conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning,
        _ generationParameters: GenerateParameters,
        _ streamingInterval: Double,
    ) -> AsyncThrowingStream<ModelGenerationEvent, Error>

    private let sampleRateValue: Int
    private let generateImpl: @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?,
        _ generationParameters: GenerateParameters,
    ) async throws -> [Float]
    private let generateSamplesStreamImpl: GenerateSamplesStreamClosure
    private let generateEventStreamImpl: GenerateEventStreamClosure
    private let prepareQwenReferenceConditioningImpl: PrepareQwenReferenceConditioningClosure?
    private let generateConditionedEventStreamImpl: GenerateConditionedEventStreamClosure?

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
            _ generationParameters: GenerateParameters,
        ) async throws -> [Float],
        generateSamplesStream: @escaping GenerateSamplesStreamClosure,
        generateEventStream: GenerateEventStreamClosure? = nil,
        prepareQwenReferenceConditioning: PrepareQwenReferenceConditioningClosure? = nil,
        generateConditionedEventStream: GenerateConditionedEventStreamClosure? = nil,
    ) {
        sampleRateValue = sampleRate
        generateImpl = generate
        generateSamplesStreamImpl = generateSamplesStream
        generateEventStreamImpl = generateEventStream ?? { text, voice, refAudio, refText, language, generationParameters, streamingInterval in
            let stream = generateSamplesStream(
                text,
                voice,
                refAudio,
                refText,
                language,
                generationParameters,
                streamingInterval,
            )
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await chunk in stream {
                            continuation.yield(.audio(chunk))
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        prepareQwenReferenceConditioningImpl = prepareQwenReferenceConditioning
        generateConditionedEventStreamImpl = generateConditionedEventStream
    }

    convenience init(model: any SpeechGenerationModel) {
        let box = UnsafeSpeechGenerationModelBox(model: model)
        let qwenModel = box.model as? Qwen3TTSModel
        let prepareQwenReferenceConditioning: PrepareQwenReferenceConditioningClosure? = if let qwenModel {
            { refAudio, refText, language in
                try qwenModel.prepareReferenceConditioning(
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                )
            }
        } else {
            nil
        }
        let generateConditionedEventStream: GenerateConditionedEventStreamClosure? = if let qwenModel {
            { text, conditioning, generationParameters, streamingInterval in
                let stream = qwenModel.generateStream(
                    text: text,
                    conditioning: conditioning,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
                return AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            for try await event in stream {
                                switch event {
                                    case let .token(token):
                                        continuation.yield(.token(token))
                                    case let .info(info):
                                        continuation.yield(
                                            .info(
                                                .init(
                                                    promptTokenCount: info.promptTokenCount,
                                                    generationTokenCount: info.generationTokenCount,
                                                    prefillTime: info.prefillTime,
                                                    generateTime: info.generateTime,
                                                    tokensPerSecond: info.tokensPerSecond,
                                                    peakMemoryUsage: info.peakMemoryUsage,
                                                ),
                                            ),
                                        )
                                    case let .audio(samples):
                                        continuation.yield(.audio(samples.asArray(Float.self)))
                                }
                            }
                            continuation.finish()
                        } catch is CancellationError {
                            continuation.finish(throwing: CancellationError())
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        } else {
            nil
        }

        self.init(
            sampleRate: box.model.sampleRate,
            generate: { text, voice, refAudio, refText, language, generationParameters in
                try await box.model
                    .generate(
                        text: text,
                        voice: voice,
                        refAudio: refAudio,
                        refText: refText,
                        language: language,
                        generationParameters: generationParameters,
                    )
                    .asArray(Float.self)
            },
            generateSamplesStream: { text, voice, refAudio, refText, language, generationParameters, streamingInterval in
                box.model.generateSamplesStream(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
            },
            generateEventStream: { text, voice, refAudio, refText, language, generationParameters, streamingInterval in
                let stream = box.model.generateStream(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: generationParameters,
                    streamingInterval: streamingInterval,
                )
                return AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            for try await event in stream {
                                switch event {
                                    case let .token(token):
                                        continuation.yield(.token(token))
                                    case let .info(info):
                                        continuation.yield(
                                            .info(
                                                .init(
                                                    promptTokenCount: info.promptTokenCount,
                                                    generationTokenCount: info.generationTokenCount,
                                                    prefillTime: info.prefillTime,
                                                    generateTime: info.generateTime,
                                                    tokensPerSecond: info.tokensPerSecond,
                                                    peakMemoryUsage: info.peakMemoryUsage,
                                                ),
                                            ),
                                        )
                                    case let .audio(samples):
                                        continuation.yield(.audio(samples.asArray(Float.self)))
                                }
                            }
                            continuation.finish()
                        } catch is CancellationError {
                            continuation.finish(throwing: CancellationError())
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            prepareQwenReferenceConditioning: prepareQwenReferenceConditioning,
            generateConditionedEventStream: generateConditionedEventStream,
        )
    }

    func generate(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters,
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
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        generateSamplesStreamImpl(text, voice, refAudio, refText, language, generationParameters, streamingInterval)
    }

    func generateEventStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<ModelGenerationEvent, Error> {
        generateEventStreamImpl(text, voice, refAudio, refText, language, generationParameters, streamingInterval)
    }

    func prepareQwenReferenceConditioning(
        refAudio: MLXArray,
        refText: String,
        language: String?,
    ) throws -> Qwen3TTSModel.Qwen3TTSReferenceConditioning {
        guard let prepareQwenReferenceConditioningImpl else {
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly attempted to prepare reusable Qwen reference conditioning with a resident model that does not support the Qwen conditioning API. This indicates a model-routing bug.",
            )
        }

        return try prepareQwenReferenceConditioningImpl(refAudio, refText, language)
    }

    func generateConditionedEventStream(
        text: String,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<ModelGenerationEvent, Error> {
        guard let generateConditionedEventStreamImpl else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: WorkerError(
                        code: .internalError,
                        message: "SpeakSwiftly attempted to start conditioned Qwen generation with a resident model that does not support the Qwen conditioning API. This indicates a model-routing bug.",
                    ),
                )
            }
        }

        return generateConditionedEventStreamImpl(
            text,
            conditioning,
            generationParameters,
            streamingInterval,
        )
    }
}
