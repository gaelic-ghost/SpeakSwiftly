import Foundation
import Network
import SpeakSwiftlyCore

public enum NetworkAudioEndpoint: Codable, Sendable, Equatable {
    case hostPort(host: String, port: UInt16)
    case bonjourService(name: String, type: String = NetworkAudioBonjour.serviceType, domain: String = NetworkAudioBonjour.domain)

    public init(host: String, port: UInt16) {
        self = .hostPort(host: host, port: port)
    }

    public init(serviceName: String, type: String = NetworkAudioBonjour.serviceType, domain: String = NetworkAudioBonjour.domain) {
        self = .bonjourService(name: serviceName, type: type, domain: domain)
    }

    public var nwEndpoint: NWEndpoint {
        switch self {
            case let .hostPort(host, port):
                .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
            case let .bonjourService(name, type, domain):
                .service(name: name, type: type, domain: domain, interface: nil)
        }
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
