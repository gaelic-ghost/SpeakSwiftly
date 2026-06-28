@preconcurrency import AVFoundation
import Foundation
import NIOCore
import SpeakSwiftlyCore

public enum NetworkAudioPayloadFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case aac
}

public struct NetworkGeneratedAudioFrame: Codable, Sendable, Equatable {
    public let requestID: String
    public let sequenceNumber: Int
    public let sampleRate: Int
    public let channelCount: Int
    public let sourceSampleFormat: GeneratedAudioSampleFormat
    public let payloadFormat: NetworkAudioPayloadFormat
    public let payloadStreamDescription: NetworkAudioStreamDescription
    public let isFinal: Bool
    public let packetCount: Int
    public let maximumPacketSize: Int
    public let packetDescriptions: [NetworkAudioPacketDescription]
    public let payload: Data

    public init(
        requestID: String,
        sequenceNumber: Int,
        sampleRate: Int,
        channelCount: Int,
        sourceSampleFormat: GeneratedAudioSampleFormat,
        payloadFormat: NetworkAudioPayloadFormat,
        payloadStreamDescription: NetworkAudioStreamDescription,
        isFinal: Bool,
        packetCount: Int,
        maximumPacketSize: Int,
        packetDescriptions: [NetworkAudioPacketDescription],
        payload: Data,
    ) {
        self.requestID = requestID
        self.sequenceNumber = sequenceNumber
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sourceSampleFormat = sourceSampleFormat
        self.payloadFormat = payloadFormat
        self.payloadStreamDescription = payloadStreamDescription
        self.isFinal = isFinal
        self.packetCount = packetCount
        self.maximumPacketSize = maximumPacketSize
        self.packetDescriptions = packetDescriptions
        self.payload = payload
    }
}

public struct NetworkAudioStreamDescription: Codable, Sendable, Equatable {
    public let sampleRate: Double
    public let formatID: UInt32
    public let formatFlags: UInt32
    public let bytesPerPacket: UInt32
    public let framesPerPacket: UInt32
    public let bytesPerFrame: UInt32
    public let channelsPerFrame: UInt32
    public let bitsPerChannel: UInt32

    var audioStreamBasicDescription: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: formatFlags,
            mBytesPerPacket: bytesPerPacket,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channelsPerFrame,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0,
        )
    }

    public init(
        sampleRate: Double,
        formatID: UInt32,
        formatFlags: UInt32,
        bytesPerPacket: UInt32,
        framesPerPacket: UInt32,
        bytesPerFrame: UInt32,
        channelsPerFrame: UInt32,
        bitsPerChannel: UInt32,
    ) {
        self.sampleRate = sampleRate
        self.formatID = formatID
        self.formatFlags = formatFlags
        self.bytesPerPacket = bytesPerPacket
        self.framesPerPacket = framesPerPacket
        self.bytesPerFrame = bytesPerFrame
        self.channelsPerFrame = channelsPerFrame
        self.bitsPerChannel = bitsPerChannel
    }

    init(_ streamDescription: AudioStreamBasicDescription) {
        self.init(
            sampleRate: streamDescription.mSampleRate,
            formatID: streamDescription.mFormatID,
            formatFlags: streamDescription.mFormatFlags,
            bytesPerPacket: streamDescription.mBytesPerPacket,
            framesPerPacket: streamDescription.mFramesPerPacket,
            bytesPerFrame: streamDescription.mBytesPerFrame,
            channelsPerFrame: streamDescription.mChannelsPerFrame,
            bitsPerChannel: streamDescription.mBitsPerChannel,
        )
    }
}

public struct NetworkAudioPacketDescription: Codable, Sendable, Equatable {
    public let startOffset: Int64
    public let variableFramesInPacket: UInt32
    public let dataByteSize: UInt32

    public init(
        startOffset: Int64,
        variableFramesInPacket: UInt32,
        dataByteSize: UInt32,
    ) {
        self.startOffset = startOffset
        self.variableFramesInPacket = variableFramesInPacket
        self.dataByteSize = dataByteSize
    }

    init(_ packetDescription: AudioStreamPacketDescription) {
        self.init(
            startOffset: packetDescription.mStartOffset,
            variableFramesInPacket: packetDescription.mVariableFramesInPacket,
            dataByteSize: packetDescription.mDataByteSize,
        )
    }

    var audioStreamPacketDescription: AudioStreamPacketDescription {
        AudioStreamPacketDescription(
            mStartOffset: startOffset,
            mVariableFramesInPacket: variableFramesInPacket,
            mDataByteSize: dataByteSize,
        )
    }
}

public enum NetworkGeneratedAudioFrameCodec {
    public static let defaultAACBitRate = 96000

    public static func encode(_ frame: NetworkGeneratedAudioFrame) throws -> Data {
        try JSONEncoder().encode(frame)
    }

    public static func decode(_ data: Data) throws -> NetworkGeneratedAudioFrame {
        try JSONDecoder().decode(NetworkGeneratedAudioFrame.self, from: data)
    }

    public static func frame(
        chunk: GeneratedAudioChunk,
        bitRate: Int = defaultAACBitRate,
    ) throws -> NetworkGeneratedAudioFrame {
        guard chunk.sampleFormat == .float32PCM else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Network audio AAC encoding supports Float32 PCM chunks, but request '\(chunk.requestID)' provided '\(chunk.sampleFormat.rawValue)'.",
            )
        }

        let outputFormat = try aacFormat(
            sampleRate: chunk.sampleRate,
            channelCount: chunk.channelCount,
            bitRate: bitRate,
            requestID: chunk.requestID,
        )
        guard !chunk.samples.isEmpty, !chunk.isFinal else {
            return NetworkGeneratedAudioFrame(
                requestID: chunk.requestID,
                sequenceNumber: chunk.sequenceNumber,
                sampleRate: chunk.sampleRate,
                channelCount: chunk.channelCount,
                sourceSampleFormat: chunk.sampleFormat,
                payloadFormat: .aac,
                payloadStreamDescription: NetworkAudioStreamDescription(outputFormat.streamDescription.pointee),
                isFinal: chunk.isFinal,
                packetCount: 0,
                maximumPacketSize: 0,
                packetDescriptions: [],
                payload: Data(),
            )
        }

        let inputFormat = try float32PCMFormat(
            sampleRate: chunk.sampleRate,
            channelCount: chunk.channelCount,
            requestID: chunk.requestID,
            context: "AAC network encoding input",
        )
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Network audio could not create an AVAudioConverter for AAC encoding at \(chunk.sampleRate) Hz with \(chunk.channelCount) channel(s).",
            )
        }

        let inputBuffer = try pcmBuffer(from: chunk, format: inputFormat)
        let packetCapacity = AVAudioPacketCount(max(1, Int(inputBuffer.frameLength + 1023) / 1024 + 2))
        let maximumPacketSize = max(converter.maximumOutputPacketSize, 1)
        let compressedBuffer = AVAudioCompressedBuffer(
            format: outputFormat,
            packetCapacity: packetCapacity,
            maximumPacketSize: maximumPacketSize,
        )
        let inputProvider = NetworkAudioConverterInputProvider(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: compressedBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.nextBuffer(inputStatus: inputStatus)
        }
        if let conversionError {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: chunk.requestID,
                message: "Network audio AAC encoding failed for request '\(chunk.requestID)': \(conversionError.localizedDescription)",
            )
        }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: chunk.requestID,
                message: "Network audio AAC encoding stopped with unexpected AVAudioConverter status '\(status)' for request '\(chunk.requestID)'.",
            )
        }

        let packetCount = Int(compressedBuffer.packetCount)
        let payload = Data(bytes: compressedBuffer.data, count: Int(compressedBuffer.byteLength))
        let packetDescriptions = packetDescriptions(from: compressedBuffer, packetCount: packetCount)
        return NetworkGeneratedAudioFrame(
            requestID: chunk.requestID,
            sequenceNumber: chunk.sequenceNumber,
            sampleRate: chunk.sampleRate,
            channelCount: chunk.channelCount,
            sourceSampleFormat: chunk.sampleFormat,
            payloadFormat: .aac,
            payloadStreamDescription: NetworkAudioStreamDescription(outputFormat.streamDescription.pointee),
            isFinal: chunk.isFinal,
            packetCount: packetCount,
            maximumPacketSize: maximumPacketSize,
            packetDescriptions: packetDescriptions,
            payload: payload,
        )
    }

    public static func chunk(from frame: NetworkGeneratedAudioFrame) throws -> GeneratedAudioChunk {
        guard frame.payloadFormat == .aac else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: frame.requestID,
                message: "Network audio frame uses payload format '\(frame.payloadFormat.rawValue)', but this receiver supports AAC.",
            )
        }
        guard !frame.payload.isEmpty, frame.packetCount > 0 else {
            return GeneratedAudioChunk(
                requestID: frame.requestID,
                sequenceNumber: frame.sequenceNumber,
                sampleRate: frame.sampleRate,
                channelCount: frame.channelCount,
                sampleFormat: frame.sourceSampleFormat,
                samples: [],
                isFinal: frame.isFinal,
            )
        }

        let inputFormat = try audioFormat(
            from: frame.payloadStreamDescription,
            requestID: frame.requestID,
            context: "AAC network decoding input",
        )
        let outputFormat = try float32PCMFormat(
            sampleRate: frame.sampleRate,
            channelCount: frame.channelCount,
            requestID: frame.requestID,
            context: "AAC network decoding output",
        )
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: frame.requestID,
                message: "Network audio could not create an AVAudioConverter for AAC decoding at \(frame.sampleRate) Hz with \(frame.channelCount) channel(s).",
            )
        }

        let compressedBuffer = try compressedBuffer(from: frame, format: inputFormat)
        let outputFrameCapacity = AVAudioFrameCount(max(frame.packetCount * 2048, 1))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: frame.requestID,
                message: "Network audio could not allocate a Float32 PCM output buffer while decoding AAC request '\(frame.requestID)'.",
            )
        }

        let inputProvider = NetworkAudioConverterInputProvider(buffer: compressedBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.nextBuffer(inputStatus: inputStatus)
        }
        if let conversionError {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: frame.requestID,
                message: "Network audio AAC decoding failed for request '\(frame.requestID)': \(conversionError.localizedDescription)",
            )
        }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: frame.requestID,
                message: "Network audio AAC decoding stopped with unexpected AVAudioConverter status '\(status)' for request '\(frame.requestID)'.",
            )
        }

        return GeneratedAudioChunk(
            requestID: frame.requestID,
            sequenceNumber: frame.sequenceNumber,
            sampleRate: frame.sampleRate,
            channelCount: frame.channelCount,
            sampleFormat: frame.sourceSampleFormat,
            samples: samples(from: outputBuffer, channelCount: frame.channelCount),
            isFinal: frame.isFinal,
        )
    }

    private static func float32PCMFormat(
        sampleRate: Int,
        channelCount: Int,
        requestID: String,
        context: String,
    ) throws -> AVAudioFormat {
        guard sampleRate > 0, channelCount > 0 else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID,
                message: "Network audio \(context) requires a positive sample rate and channel count, but got \(sampleRate) Hz and \(channelCount) channel(s).",
            )
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channelCount),
            interleaved: false,
        ) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID,
                message: "Network audio could not create a Float32 PCM format for \(context) at \(sampleRate) Hz with \(channelCount) channel(s).",
            )
        }

        return format
    }

    private static func aacFormat(
        sampleRate: Int,
        channelCount: Int,
        bitRate: Int,
        requestID: String,
    ) throws -> AVAudioFormat {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: bitRate,
        ]
        guard let format = AVAudioFormat(settings: settings) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID,
                message: "Network audio could not create an AAC format at \(sampleRate) Hz with \(channelCount) channel(s) and \(bitRate) bps.",
            )
        }

        return format
    }

    private static func audioFormat(
        from streamDescription: NetworkAudioStreamDescription,
        requestID: String,
        context: String,
    ) throws -> AVAudioFormat {
        var audioStreamDescription = streamDescription.audioStreamBasicDescription
        guard let format = AVAudioFormat(streamDescription: &audioStreamDescription) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: requestID,
                message: "Network audio could not create an AVAudioFormat from the CoreAudio stream description for \(context).",
            )
        }

        return format
    }

    private static func pcmBuffer(from chunk: GeneratedAudioChunk, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard chunk.samples.count.isMultiple(of: chunk.channelCount) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Network audio received \(chunk.samples.count) sample(s), which is not divisible by \(chunk.channelCount) channel(s).",
            )
        }

        let frameCount = AVAudioFrameCount(chunk.samples.count / chunk.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1)) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Network audio could not allocate a Float32 PCM buffer for AAC encoding.",
            )
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Network audio could not access Float32 PCM channel storage for AAC encoding.",
            )
        }

        if chunk.channelCount == 1 {
            chunk.samples.withUnsafeBufferPointer { samples in
                if let baseAddress = samples.baseAddress {
                    channelData[0].update(from: baseAddress, count: chunk.samples.count)
                }
            }
        } else {
            for frameIndex in 0..<Int(frameCount) {
                for channelIndex in 0..<chunk.channelCount {
                    channelData[channelIndex][frameIndex] = chunk.samples[frameIndex * chunk.channelCount + channelIndex]
                }
            }
        }
        return buffer
    }

    private static func compressedBuffer(
        from frame: NetworkGeneratedAudioFrame,
        format: AVAudioFormat,
    ) throws -> AVAudioCompressedBuffer {
        let maximumPacketSize = max(frame.maximumPacketSize, 1)
        let buffer = AVAudioCompressedBuffer(
            format: format,
            packetCapacity: AVAudioPacketCount(max(frame.packetCount, 1)),
            maximumPacketSize: maximumPacketSize,
        )
        guard frame.payload.count <= buffer.byteCapacity else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: frame.requestID,
                message: "Network audio AAC payload has \(frame.payload.count) byte(s), which exceeds the compressed buffer capacity of \(buffer.byteCapacity) byte(s).",
            )
        }

        frame.payload.withUnsafeBytes { source in
            if let baseAddress = source.bindMemory(to: UInt8.self).baseAddress {
                buffer.data.assumingMemoryBound(to: UInt8.self).update(
                    from: baseAddress,
                    count: frame.payload.count,
                )
            }
        }
        buffer.byteLength = UInt32(frame.payload.count)
        buffer.packetCount = AVAudioPacketCount(frame.packetCount)
        if let packetDescriptions = buffer.packetDescriptions {
            for index in 0..<min(frame.packetDescriptions.count, frame.packetCount) {
                packetDescriptions[index] = frame.packetDescriptions[index].audioStreamPacketDescription
            }
        }
        return buffer
    }

    private static func packetDescriptions(
        from buffer: AVAudioCompressedBuffer,
        packetCount: Int,
    ) -> [NetworkAudioPacketDescription] {
        guard let packetDescriptions = buffer.packetDescriptions else {
            return []
        }

        return (0..<packetCount).map { index in
            NetworkAudioPacketDescription(packetDescriptions[index])
        }
    }

    private static func samples(from buffer: AVAudioPCMBuffer, channelCount: Int) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        var samples = [Float]()
        samples.reserveCapacity(Int(buffer.frameLength) * channelCount)
        for frameIndex in 0..<Int(buffer.frameLength) {
            for channelIndex in 0..<channelCount {
                samples.append(channelData[channelIndex][frameIndex])
            }
        }
        return samples
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

public enum NetworkAudioStreamFrame: Sendable, Equatable {
    case handshake(NetworkAudioStreamHandshake)
    case audio(NetworkGeneratedAudioFrame)
}

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

extension NetworkGeneratedAudioFrame {
    struct Header: Codable {
        let requestID: String
        let sequenceNumber: Int
        let sampleRate: Int
        let channelCount: Int
        let sourceSampleFormat: GeneratedAudioSampleFormat
        let payloadFormat: NetworkAudioPayloadFormat
        let payloadStreamDescription: NetworkAudioStreamDescription
        let isFinal: Bool
        let packetCount: Int
        let maximumPacketSize: Int
        let packetDescriptions: [NetworkAudioPacketDescription]
        let payloadByteCount: Int
    }

    var header: Header {
        Header(
            requestID: requestID,
            sequenceNumber: sequenceNumber,
            sampleRate: sampleRate,
            channelCount: channelCount,
            sourceSampleFormat: sourceSampleFormat,
            payloadFormat: payloadFormat,
            payloadStreamDescription: payloadStreamDescription,
            isFinal: isFinal,
            packetCount: packetCount,
            maximumPacketSize: maximumPacketSize,
            packetDescriptions: packetDescriptions,
            payloadByteCount: payload.count,
        )
    }

    init(header: Header, payload: Data) {
        self.init(
            requestID: header.requestID,
            sequenceNumber: header.sequenceNumber,
            sampleRate: header.sampleRate,
            channelCount: header.channelCount,
            sourceSampleFormat: header.sourceSampleFormat,
            payloadFormat: header.payloadFormat,
            payloadStreamDescription: header.payloadStreamDescription,
            isFinal: header.isFinal,
            packetCount: header.packetCount,
            maximumPacketSize: header.maximumPacketSize,
            packetDescriptions: header.packetDescriptions,
            payload: payload,
        )
    }
}

private final class NetworkAudioConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioBuffer
    private var didProvideInput = false

    init(buffer: AVAudioBuffer) {
        self.buffer = buffer
    }

    func nextBuffer(inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !didProvideInput else {
            inputStatus.pointee = .endOfStream
            return nil
        }

        didProvideInput = true
        inputStatus.pointee = .haveData
        return buffer
    }
}
