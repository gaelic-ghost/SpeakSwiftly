import Foundation

public extension SpeakSwiftly {
    struct GeneratedAudioStream: Sendable {
        public let handle: RequestHandle
        public let chunks: GeneratedAudioChunkStream

        init(
            handle: RequestHandle,
            chunks: GeneratedAudioChunkStream,
        ) {
            self.handle = handle
            self.chunks = chunks
        }
    }
}
