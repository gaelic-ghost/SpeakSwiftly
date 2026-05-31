import Foundation
import SpeakSwiftlyCore

public enum QwenGeneratedAudioStream {
    public static func chunks(
        requestID: String,
        sampleRate: Int,
        channelCount: Int = 1,
        samples: AsyncThrowingStream<[Float], any Error>,
    ) -> AsyncThrowingStream<GeneratedAudioChunk, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sequenceNumber = 0
                do {
                    for try await sampleChunk in samples {
                        continuation.yield(
                            GeneratedAudioChunk(
                                requestID: requestID,
                                sequenceNumber: sequenceNumber,
                                sampleRate: sampleRate,
                                channelCount: channelCount,
                                samples: sampleChunk,
                            ),
                        )
                        sequenceNumber += 1
                    }
                    continuation.yield(
                        GeneratedAudioChunk(
                            requestID: requestID,
                            sequenceNumber: sequenceNumber,
                            sampleRate: sampleRate,
                            channelCount: channelCount,
                            samples: [],
                            isFinal: true,
                        ),
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
