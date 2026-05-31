import Foundation
import SpeakSwiftlyCore

public struct NetworkGeneratedAudioFrame: Codable, Sendable, Equatable {
    public let chunk: GeneratedAudioChunk

    public init(chunk: GeneratedAudioChunk) {
        self.chunk = chunk
    }
}

public enum NetworkGeneratedAudioFrameCodec {
    public static func encode(_ frame: NetworkGeneratedAudioFrame) throws -> Data {
        try JSONEncoder().encode(frame)
    }

    public static func decode(_ data: Data) throws -> NetworkGeneratedAudioFrame {
        try JSONDecoder().decode(NetworkGeneratedAudioFrame.self, from: data)
    }
}
