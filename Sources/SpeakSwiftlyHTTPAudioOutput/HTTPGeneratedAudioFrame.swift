import Foundation
import SpeakSwiftlyCore

public struct HTTPGeneratedAudioFrame: Codable, Sendable, Equatable {
    public let requestID: String
    public let sequenceNumber: Int
    public let sampleRate: Int
    public let channelCount: Int
    public let sampleFormat: GeneratedAudioSampleFormat
    public let isFinal: Bool
    public let payload: Data

    public init(chunk: GeneratedAudioChunk) {
        requestID = chunk.requestID
        sequenceNumber = chunk.sequenceNumber
        sampleRate = chunk.sampleRate
        channelCount = chunk.channelCount
        sampleFormat = chunk.sampleFormat
        isFinal = chunk.isFinal
        payload = Self.encodeFloat32Samples(chunk.samples)
    }

    private static func encodeFloat32Samples(_ samples: [Float]) -> Data {
        var littleEndianBits = samples.map { $0.bitPattern.littleEndian }
        return Data(bytes: &littleEndianBits, count: littleEndianBits.count * MemoryLayout<UInt32>.size)
    }

    private static func decodeFloat32Samples(_ data: Data) -> [Float] {
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

    public func decodedSamples() -> [Float] {
        Self.decodeFloat32Samples(payload)
    }
}
