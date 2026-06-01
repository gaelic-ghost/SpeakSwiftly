@preconcurrency import AVFoundation
import Foundation

public enum GeneratedAudioFileEncoder {
    public static func encodedAudioData(
        samples: [Float],
        sampleRate: Int,
        format: GeneratedAudioFileFormat,
        fileManager: FileManager = .default,
    ) throws -> Data {
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let url = tempDirectory.appendingPathComponent(format.fileName)
        try write(samples: samples, sampleRate: sampleRate, format: format, to: url)
        return try Data(contentsOf: url)
    }

    public static func write(
        samples: [Float],
        sampleRate: Int,
        format: GeneratedAudioFileFormat,
        to url: URL,
    ) throws {
        switch format {
            case .wav:
                try writeWAV(samples: samples, sampleRate: sampleRate, to: url)
            case .m4a:
                try writeM4A(samples: samples, sampleRate: sampleRate, to: url)
        }
    }

    private static func writeWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard sampleRate > 0 else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not encode a WAV file because the generated audio sample rate was \(sampleRate) Hz.",
            )
        }

        var data = Data()
        let bytesPerSample = 2
        let channelCount = 1
        let sampleDataByteCount = samples.count * bytesPerSample
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + sampleDataByteCount))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channelCount))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bytesPerSample * 8))
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(sampleDataByteCount))

        for sample in samples {
            let clamped = min(max(sample, -1), 1)
            let scaled = Int16((clamped * Float(Int16.max)).rounded())
            data.appendInt16LE(scaled)
        }

        try data.write(to: url, options: .atomic)
    }

    private static func writeM4A(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard sampleRate > 0 else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not encode an M4A file because the generated audio sample rate was \(sampleRate) Hz.",
            )
        }
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false,
        ) else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not create a Float32 PCM processing format for M4A encoding at \(sampleRate) Hz.",
            )
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: AVAudioFrameCount(max(samples.count, 1)),
        ) else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not allocate an audio buffer for \(samples.count) generated sample(s) while encoding M4A output.",
            )
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            for index in samples.indices {
                channelData[0][index] = samples[index]
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }
}

public enum GeneratedAudioFileOutputError: Error, Sendable, Equatable {
    case invalidAudio(message: String)
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    mutating func appendInt16LE(_ value: Int16) {
        append(contentsOf: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }
}
