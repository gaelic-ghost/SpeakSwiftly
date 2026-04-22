import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@preconcurrency import MLXLMCommon

// MARK: - Qwen Speech Generation

extension SpeakSwiftly.Runtime {
    func generationEventInfo(from info: ModelGenerationEvent.Info) -> SpeakSwiftly.GenerationEventInfo {
        SpeakSwiftly.GenerationEventInfo(
            promptTokenCount: info.promptTokenCount,
            generationTokenCount: info.generationTokenCount,
            prefillTime: info.prefillTime,
            generateTime: info.generateTime,
            tokensPerSecond: info.tokensPerSecond,
            peakMemoryUsage: info.peakMemoryUsage,
        )
    }

    func qwenGenerationStream(
        requestID: String,
        model: AnySpeechModel,
        text: String,
        materialization: StoredProfileMaterialization,
        refAudio: MLXArray?,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let eventStream = model.generateEventStream(
            text: text,
            voice: nil,
            refAudio: refAudio,
            refText: materialization.manifest.referenceText,
            language: nil,
            generationParameters: generationParameters,
            streamingInterval: streamingInterval,
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        switch event {
                            case let .token(token):
                                recordGenerationEvent(.token(token), for: requestID)
                            case let .info(info):
                                recordGenerationEvent(.info(generationEventInfo(from: info)), for: requestID)
                            case let .audio(samples):
                                recordGenerationEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                                continuation.yield(samples)
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

    func qwenGenerationStream(
        requestID: String,
        model: AnySpeechModel,
        text: String,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let eventStream = model.generateConditionedEventStream(
            text: text,
            conditioning: conditioning,
            generationParameters: generationParameters,
            streamingInterval: streamingInterval,
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in eventStream {
                        switch event {
                            case let .token(token):
                                recordGenerationEvent(.token(token), for: requestID)
                            case let .info(info):
                                recordGenerationEvent(.info(generationEventInfo(from: info)), for: requestID)
                            case let .audio(samples):
                                recordGenerationEvent(.audioChunk(sampleCount: samples.count), for: requestID)
                                continuation.yield(samples)
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
}
