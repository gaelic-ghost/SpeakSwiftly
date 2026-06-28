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

        let buffer = try monoFloat32PCMBuffer(samples: samples, sampleRate: sampleRate, formatName: "WAV")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private static func writeM4A(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard sampleRate > 0 else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not encode an M4A file because the generated audio sample rate was \(sampleRate) Hz.",
            )
        }

        let buffer = try monoFloat32PCMBuffer(samples: samples, sampleRate: sampleRate, formatName: "M4A")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private static func monoFloat32PCMBuffer(
        samples: [Float],
        sampleRate: Int,
        formatName: String,
    ) throws -> AVAudioPCMBuffer {
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false,
        ) else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not create a Float32 PCM processing format for \(formatName) encoding at \(sampleRate) Hz.",
            )
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: AVAudioFrameCount(max(samples.count, 1)),
        ) else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not allocate an audio buffer for \(samples.count) generated sample(s) while encoding \(formatName) output.",
            )
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData else {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: "SpeakSwiftly could not access Float32 PCM channel storage while encoding \(formatName) output.",
            )
        }

        for index in samples.indices {
            channelData[0][index] = samples[index]
        }
        return buffer
    }
}

public enum GeneratedAudioFileOutputError: Error, Sendable, Equatable {
    case invalidAudio(message: String)
}
