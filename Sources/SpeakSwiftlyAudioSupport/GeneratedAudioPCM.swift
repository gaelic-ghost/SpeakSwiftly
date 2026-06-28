@preconcurrency import AVFoundation
import Foundation
import SpeakSwiftlyCore

public enum GeneratedAudioPCM {
    public static func float32Format(
        sampleRate: Double,
        channelCount: Int,
        interleaved: Bool = false,
        context: String,
    ) throws -> AVAudioFormat {
        guard sampleRate > 0 else {
            throw GeneratedAudioPCMError.invalidFormat(
                context: context,
                message: "The sample rate must be greater than zero, but it was \(sampleRate) Hz.",
            )
        }
        guard channelCount > 0 else {
            throw GeneratedAudioPCMError.invalidFormat(
                context: context,
                message: "The channel count must be greater than zero, but it was \(channelCount).",
            )
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: interleaved,
        ) else {
            throw GeneratedAudioPCMError.invalidFormat(
                context: context,
                message: "AVFAudio could not create a Float32 PCM format at \(sampleRate) Hz with \(channelCount) channel(s).",
            )
        }

        return format
    }

    public static func buffer(
        from samples: [Float],
        format: AVAudioFormat,
        sourceChannelCount: Int,
        context: String,
    ) throws -> AVAudioPCMBuffer {
        guard sourceChannelCount > 0 else {
            throw GeneratedAudioPCMError.invalidSamples(
                context: context,
                message: "The source channel count must be greater than zero, but it was \(sourceChannelCount).",
            )
        }
        guard Int(format.channelCount) == sourceChannelCount else {
            throw GeneratedAudioPCMError.invalidSamples(
                context: context,
                message: "The source channel count is \(sourceChannelCount), but the AVAudioFormat has \(format.channelCount) channel(s).",
            )
        }
        guard format.commonFormat == .pcmFormatFloat32 else {
            throw GeneratedAudioPCMError.invalidFormat(
                context: context,
                message: "The AVAudioFormat must use Float32 PCM samples, but it uses '\(format.commonFormat)'.",
            )
        }
        guard samples.count.isMultiple(of: sourceChannelCount) else {
            throw GeneratedAudioPCMError.invalidSamples(
                context: context,
                message: "There are \(samples.count) sample(s), which is not divisible by \(sourceChannelCount) channel(s).",
            )
        }

        let frameCount = AVAudioFrameCount(samples.count / sourceChannelCount)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: max(frameCount, 1),
        ) else {
            throw GeneratedAudioPCMError.invalidSamples(
                context: context,
                message: "AVFAudio could not allocate a PCM buffer for \(samples.count) sample(s).",
            )
        }

        buffer.frameLength = frameCount
        guard frameCount > 0 else {
            return buffer
        }
        guard let channelData = buffer.floatChannelData else {
            throw GeneratedAudioPCMError.invalidFormat(
                context: context,
                message: "AVFAudio did not expose Float32 channel storage for the PCM buffer.",
            )
        }

        if sourceChannelCount == 1 {
            samples.withUnsafeBufferPointer { source in
                if let baseAddress = source.baseAddress {
                    channelData[0].update(from: baseAddress, count: samples.count)
                }
            }
        } else {
            for frameIndex in 0..<Int(frameCount) {
                for channelIndex in 0..<sourceChannelCount {
                    channelData[channelIndex][frameIndex] = samples[frameIndex * sourceChannelCount + channelIndex]
                }
            }
        }

        return buffer
    }

    public static func buffer(
        from chunk: GeneratedAudioChunk,
        format: AVAudioFormat,
        context: String,
    ) throws -> AVAudioPCMBuffer {
        guard chunk.sampleFormat == .float32PCM else {
            throw GeneratedAudioPCMError.invalidSamples(
                context: context,
                message: "Chunk '\(chunk.requestID)' uses sample format '\(chunk.sampleFormat.rawValue)', but only Float32 PCM is supported.",
            )
        }

        return try buffer(
            from: chunk.samples,
            format: format,
            sourceChannelCount: chunk.channelCount,
            context: context,
        )
    }
}

public enum GeneratedAudioPCMError: Error, Sendable, Equatable {
    case invalidFormat(context: String, message: String)
    case invalidSamples(context: String, message: String)
}

extension GeneratedAudioPCMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case let .invalidFormat(context, message):
                "Generated audio PCM format is invalid for \(context). \(message)"
            case let .invalidSamples(context, message):
                "Generated audio PCM samples are invalid for \(context). \(message)"
        }
    }
}
