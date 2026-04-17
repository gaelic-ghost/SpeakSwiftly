import Foundation
@preconcurrency import MLX
@preconcurrency import MLXLMCommon

// MARK: - Chatterbox Speech Generation

extension SpeakSwiftly.Runtime {
    func chatterboxGenerationStream(
        requestID: String,
        model: AnySpeechModel,
        text: String,
        refAudio: MLXArray?,
        generationParameters: GenerateParameters,
        streamingInterval: Double,
    ) -> AsyncThrowingStream<[Float], Error> {
        let plannedChunks = {
            let chunks = LiveSpeechChunkPlanner.chunks(for: text)
            return chunks.isEmpty ? [LiveSpeechTextChunk(index: 1, text: text, wordCount: 1)] : chunks
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for plannedChunk in plannedChunks {
                        try Task.checkCancellation()

                        let eventStream = model.generateEventStream(
                            text: plannedChunk.text,
                            voice: nil,
                            refAudio: refAudio,
                            refText: nil,
                            language: "English",
                            generationParameters: generationParameters,
                            streamingInterval: streamingInterval,
                        )

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
