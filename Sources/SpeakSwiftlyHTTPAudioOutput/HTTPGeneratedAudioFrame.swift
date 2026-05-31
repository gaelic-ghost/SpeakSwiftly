import Foundation
import SpeakSwiftlyCore

public struct HTTPGeneratedAudioFrame: Codable, Sendable, Equatable {
    public let header: HTTPGeneratedAudioFrameHeader
    public let payload: Data

    public var contentType: String {
        "application/octet-stream"
    }

    public var metadataHeaders: [(name: String, value: String)] {
        header.httpHeaders
    }

    public init(chunk: GeneratedAudioChunk) {
        header = HTTPGeneratedAudioFrameHeader(chunk: chunk)
        payload = Self.encodeFloat32Samples(chunk.samples)
    }

    private static func encodeFloat32Samples(_ samples: [Float]) -> Data {
        var littleEndianBits = samples.map { $0.bitPattern.littleEndian }
        return Data(bytes: &littleEndianBits, count: littleEndianBits.count * MemoryLayout<UInt32>.size)
    }

    private static func decodeFloat32Samples(_ data: Data, expectedByteCount: Int, requestID: String) throws -> [Float] {
        guard data.count == expectedByteCount else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID,
                message: "HTTP audio frame payload has \(data.count) byte(s), but its metadata declares \(expectedByteCount) byte(s). The response body may be truncated or paired with the wrong frame header.",
            )
        }
        guard data.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID,
                message: "HTTP audio frame payload has \(data.count) byte(s), which cannot be decoded as complete little-endian Float32 PCM samples.",
            )
        }
        guard !data.isEmpty else {
            return []
        }

        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map { offset in
                let value = UInt32(bytes[offset])
                    | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16
                    | UInt32(bytes[offset + 3]) << 24
                return Float(bitPattern: value)
            }
        }
    }

    public func decodedSamples() throws -> [Float] {
        try Self.decodeFloat32Samples(payload, expectedByteCount: header.payloadByteCount, requestID: header.requestID)
    }
}

public struct HTTPGeneratedAudioFrameHeader: Codable, Sendable, Equatable {
    public let requestID: String
    public let sequenceNumber: Int
    public let sampleRate: Int
    public let channelCount: Int
    public let sampleFormat: GeneratedAudioSampleFormat
    public let isFinal: Bool
    public let payloadByteCount: Int

    public init(chunk: GeneratedAudioChunk) {
        requestID = chunk.requestID
        sequenceNumber = chunk.sequenceNumber
        sampleRate = chunk.sampleRate
        channelCount = chunk.channelCount
        sampleFormat = chunk.sampleFormat
        isFinal = chunk.isFinal
        payloadByteCount = chunk.samples.count * MemoryLayout<Float>.size
    }

    public var httpHeaders: [(name: String, value: String)] {
        [
            ("X-SpeakSwiftly-Request-ID", requestID),
            ("X-SpeakSwiftly-Sequence", String(sequenceNumber)),
            ("X-SpeakSwiftly-Sample-Rate", String(sampleRate)),
            ("X-SpeakSwiftly-Channel-Count", String(channelCount)),
            ("X-SpeakSwiftly-Sample-Format", sampleFormat.rawValue),
            ("X-SpeakSwiftly-Final", isFinal ? "true" : "false"),
            ("Content-Length", String(payloadByteCount)),
        ]
    }
}
