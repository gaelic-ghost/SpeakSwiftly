@preconcurrency import AVFoundation
import Foundation
import SpeakSwiftlyAudioSupport

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

        let buffer = try outputBuffer(samples: samples, sampleRate: sampleRate, formatName: "WAV")
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

        let buffer = try outputBuffer(samples: samples, sampleRate: sampleRate, formatName: "M4A")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private static func outputBuffer(
        samples: [Float],
        sampleRate: Int,
        formatName: String,
    ) throws -> AVAudioPCMBuffer {
        do {
            let processingFormat = try GeneratedAudioPCM.float32Format(
                sampleRate: Double(sampleRate),
                channelCount: 1,
                context: "\(formatName) file encoding",
            )
            return try GeneratedAudioPCM.buffer(
                from: samples,
                format: processingFormat,
                sourceChannelCount: 1,
                context: "\(formatName) file encoding",
            )
        } catch let error as GeneratedAudioPCMError {
            throw GeneratedAudioFileOutputError.invalidAudio(
                message: error.localizedDescription,
            )
        }
    }
}

public enum GeneratedAudioFileOutputError: Error, Sendable, Equatable {
    case invalidAudio(message: String)
}
