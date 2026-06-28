@preconcurrency import AVFoundation
import Foundation
import SpeakSwiftlyCore

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
