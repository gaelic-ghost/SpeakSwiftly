import Foundation
import SpeakSwiftlyCore

public enum LocalPlaybackAudioOutput {
    public static func sampleChunks(
        from chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
    ) -> AsyncThrowingStream<[Float], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in chunks {
                        guard !chunk.isFinal else {
                            continue
                        }

                        continuation.yield(chunk.samples)
                    }
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
