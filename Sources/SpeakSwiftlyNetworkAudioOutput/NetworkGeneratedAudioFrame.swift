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

public struct NetworkAudioStreamHandshake: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let requestID: String
    public let senderName: String
    public let sharedToken: String

    public init(
        protocolVersion: Int = NetworkAudioBonjour.protocolVersion,
        requestID: String,
        senderName: String,
        sharedToken: String,
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.senderName = senderName
        self.sharedToken = sharedToken
    }
}

public enum NetworkAudioStreamFrame: Codable, Sendable, Equatable {
    case handshake(NetworkAudioStreamHandshake)
    case audio(NetworkGeneratedAudioFrame)

    private enum CodingKeys: String, CodingKey {
        case kind
        case handshake
        case audio
    }

    private enum Kind: String, Codable {
        case handshake
        case audio
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
            case .handshake:
                self = try .handshake(container.decode(NetworkAudioStreamHandshake.self, forKey: .handshake))
            case .audio:
                self = try .audio(container.decode(NetworkGeneratedAudioFrame.self, forKey: .audio))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .handshake(handshake):
                try container.encode(Kind.handshake, forKey: .kind)
                try container.encode(handshake, forKey: .handshake)
            case let .audio(audio):
                try container.encode(Kind.audio, forKey: .kind)
                try container.encode(audio, forKey: .audio)
        }
    }
}

public enum NetworkAudioLengthPrefixedFrameCodec {
    public static let prefixByteCount = 4
    public static let defaultMaximumFrameByteCount = 8 * 1024 * 1024

    public static func encode(
        _ frame: NetworkAudioStreamFrame,
        maximumFrameByteCount: Int = defaultMaximumFrameByteCount,
    ) throws -> Data {
        let payload = try JSONEncoder().encode(frame)
        guard payload.count <= maximumFrameByteCount else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID(for: frame),
                message: "Network audio frame payload is \(payload.count) bytes, which exceeds the configured maximum of \(maximumFrameByteCount) bytes.",
            )
        }

        var length = UInt32(payload.count).bigEndian
        var data = Data(bytes: &length, count: prefixByteCount)
        data.append(payload)
        return data
    }

    public static func decodePayload(_ payload: Data) throws -> NetworkAudioStreamFrame {
        try JSONDecoder().decode(NetworkAudioStreamFrame.self, from: payload)
    }

    public static func splitFrames(
        from buffer: inout Data,
        maximumFrameByteCount: Int = defaultMaximumFrameByteCount,
    ) throws -> [NetworkAudioStreamFrame] {
        var frames = [NetworkAudioStreamFrame]()
        while buffer.count >= prefixByteCount {
            let frameLength = Int(buffer.prefix(prefixByteCount).reduce(UInt32(0)) { partial, byte in
                (partial << 8) | UInt32(byte)
            })
            guard frameLength <= maximumFrameByteCount else {
                throw GeneratedAudioOutputError.transportFailed(
                    requestID: "unknown",
                    message: "Network audio frame declared \(frameLength) bytes, which exceeds the configured maximum of \(maximumFrameByteCount) bytes.",
                )
            }
            guard buffer.count >= prefixByteCount + frameLength else {
                break
            }

            let payloadStart = buffer.index(buffer.startIndex, offsetBy: prefixByteCount)
            let payloadEnd = buffer.index(payloadStart, offsetBy: frameLength)
            let payload = Data(buffer[payloadStart..<payloadEnd])
            try frames.append(decodePayload(payload))
            buffer.removeSubrange(buffer.startIndex..<payloadEnd)
        }
        return frames
    }

    private static func requestID(for frame: NetworkAudioStreamFrame) -> String {
        switch frame {
            case let .handshake(handshake):
                handshake.requestID
            case let .audio(frame):
                frame.chunk.requestID
        }
    }
}
