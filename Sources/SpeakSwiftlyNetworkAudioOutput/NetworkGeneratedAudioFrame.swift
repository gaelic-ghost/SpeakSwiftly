import Foundation
import Network
import SpeakSwiftlyCore

public struct NetworkAudioEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    public var nwEndpoint: NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 0)
    }
}

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
