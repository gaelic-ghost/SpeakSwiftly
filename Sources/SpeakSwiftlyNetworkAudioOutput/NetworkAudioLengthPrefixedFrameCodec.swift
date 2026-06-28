import Foundation
import NIOCore
import SpeakSwiftlyCore

public enum NetworkAudioLengthPrefixedFrameCodec {
    public static let prefixByteCount = 4
    public static let defaultMaximumFrameByteCount = 8 * 1024 * 1024

    private static let handshakeFrameKind: UInt8 = 1
    private static let audioFrameKind: UInt8 = 2

    public static func encode(
        _ frame: NetworkAudioStreamFrame,
        maximumFrameByteCount: Int = defaultMaximumFrameByteCount,
    ) throws -> Data {
        var payload = ByteBufferAllocator().buffer(capacity: 256)
        switch frame {
            case let .handshake(handshake):
                let handshakeData = try JSONEncoder().encode(handshake)
                payload.writeInteger(handshakeFrameKind)
                try payload.writeLengthPrefixed(endianness: .big, as: UInt32.self) { buffer in
                    buffer.writeBytes(handshakeData)
                }
            case let .audio(frame):
                let headerData = try JSONEncoder().encode(frame.header)
                payload.writeInteger(audioFrameKind)
                try payload.writeLengthPrefixed(endianness: .big, as: UInt32.self) { buffer in
                    buffer.writeBytes(headerData)
                }
                payload.writeBytes(frame.payload)
        }

        guard payload.readableBytes <= maximumFrameByteCount else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID(for: frame),
                message: "Network audio frame payload is \(payload.readableBytes) bytes, which exceeds the configured maximum of \(maximumFrameByteCount) bytes.",
            )
        }

        var encoded = ByteBufferAllocator().buffer(capacity: prefixByteCount + payload.readableBytes)
        try encoded.writeLengthPrefixed(endianness: .big, as: UInt32.self) { buffer in
            buffer.writeImmutableBuffer(payload)
        }
        return Data(encoded.readableBytesView)
    }

    public static func decodePayload(_ payload: Data) throws -> NetworkAudioStreamFrame {
        var buffer = ByteBufferAllocator().buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        guard let frameKind = buffer.readInteger(as: UInt8.self) else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: "unknown",
                message: "Network audio frame payload was empty and did not contain a frame kind.",
            )
        }
        guard let header = buffer.readLengthPrefixedSlice(endianness: .big, as: UInt32.self) else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: "unknown",
                message: "Network audio frame kind \(frameKind) did not include a complete length-prefixed header.",
            )
        }

        let headerData = Data(header.readableBytesView)

        switch frameKind {
            case handshakeFrameKind:
                let handshake = try JSONDecoder().decode(NetworkAudioStreamHandshake.self, from: headerData)
                return .handshake(handshake)
            case audioFrameKind:
                let header = try JSONDecoder().decode(NetworkGeneratedAudioFrame.Header.self, from: headerData)
                guard buffer.readableBytes == header.payloadByteCount else {
                    throw GeneratedAudioOutputError.invalidChunk(
                        requestID: header.requestID,
                        message: "Network audio frame for request '\(header.requestID)' declared \(header.payloadByteCount) AAC payload byte(s), but received \(buffer.readableBytes).",
                    )
                }

                let payload = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
                return .audio(NetworkGeneratedAudioFrame(header: header, payload: payload))
            default:
                throw GeneratedAudioOutputError.transportFailed(
                    requestID: "unknown",
                    message: "Network audio frame used unknown frame kind \(frameKind).",
                )
        }
    }

    public static func splitFrames(
        from buffer: inout Data,
        maximumFrameByteCount: Int = defaultMaximumFrameByteCount,
    ) throws -> [NetworkAudioStreamFrame] {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: buffer.count)
        byteBuffer.writeBytes(buffer)
        var frames = [NetworkAudioStreamFrame]()
        while byteBuffer.readableBytes >= prefixByteCount {
            guard let declaredFrameLength = byteBuffer.getInteger(
                at: byteBuffer.readerIndex,
                endianness: .big,
                as: UInt32.self,
            ) else {
                break
            }
            guard declaredFrameLength <= maximumFrameByteCount else {
                throw GeneratedAudioOutputError.transportFailed(
                    requestID: "unknown",
                    message: "Network audio frame declared \(declaredFrameLength) bytes, which exceeds the configured maximum of \(maximumFrameByteCount) bytes.",
                )
            }
            guard let payload = byteBuffer.readLengthPrefixedSlice(endianness: .big, as: UInt32.self) else {
                break
            }

            try frames.append(decodePayload(Data(payload.readableBytesView)))
        }

        buffer = Data(byteBuffer.readableBytesView)
        return frames
    }

    private static func requestID(for frame: NetworkAudioStreamFrame) -> String {
        switch frame {
            case let .handshake(handshake):
                handshake.requestID
            case let .audio(frame):
                frame.requestID
        }
    }
}
