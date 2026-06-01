@preconcurrency import AVFoundation
import Foundation
import SpeakSwiftlyCore

public enum LocalPlaybackAudioOutput {
    public static func sampleChunks(
        from chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
    ) -> AsyncThrowingStream<[Float], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in chunks {
                        guard !chunk.isFinal else {
                            continue
                        }

                        continuation.yield(chunk.samples)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@MainActor
public final class LocalGeneratedAudioPlayer {
    public typealias SampleSink = @Sendable (GeneratedAudioChunk) async throws -> Void

    private let sampleSink: SampleSink?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingFormat: AVAudioFormat?

    public init(sampleSink: SampleSink? = nil) {
        self.sampleSink = sampleSink
    }

    public func play(
        chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
    ) async throws {
        if let sampleSink {
            try await playWithSampleSink(chunks: chunks, sampleSink: sampleSink)
            return
        }

        try await playWithAudioEngine(chunks: chunks)
    }

    public func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        streamingFormat = nil
    }

    private func playWithSampleSink(
        chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
        sampleSink: SampleSink,
    ) async throws {
        for try await chunk in chunks {
            guard !chunk.isFinal else {
                return
            }

            try await sampleSink(chunk)
        }
    }

    private func playWithAudioEngine(
        chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
    ) async throws {
        do {
            for try await chunk in chunks {
                guard !chunk.isFinal else {
                    return
                }

                try prepareIfNeeded(for: chunk)
                try schedule(chunk)
            }
        } catch {
            stop()
            throw error
        }
    }

    private func prepareIfNeeded(for chunk: GeneratedAudioChunk) throws {
        guard chunk.sampleFormat == .float32PCM else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback supports float32 PCM chunks, but request '\(chunk.requestID)' provided '\(chunk.sampleFormat.rawValue)'.",
            )
        }
        guard chunk.channelCount > 0 else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback requires at least one channel for request '\(chunk.requestID)'.",
            )
        }

        if let streamingFormat,
           Int(streamingFormat.sampleRate) == chunk.sampleRate,
           Int(streamingFormat.channelCount) == chunk.channelCount {
            if playerNode?.isPlaying == false {
                playerNode?.play()
            }
            return
        }

        stop()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(chunk.sampleRate),
            channels: AVAudioChannelCount(chunk.channelCount),
            interleaved: false,
        ) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback could not create an AVAudioFormat for request '\(chunk.requestID)' at \(chunk.sampleRate) Hz with \(chunk.channelCount) channel(s).",
            )
        }

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        node.play()
        audioEngine = engine
        playerNode = node
        streamingFormat = format
    }

    private func schedule(_ chunk: GeneratedAudioChunk) throws {
        guard !chunk.samples.isEmpty else {
            return
        }
        guard let format = streamingFormat, let playerNode else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback could not schedule request '\(chunk.requestID)' because the audio engine was not prepared.",
            )
        }
        guard chunk.samples.count.isMultiple(of: chunk.channelCount) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback received \(chunk.samples.count) sample(s) for request '\(chunk.requestID)', which is not divisible by \(chunk.channelCount) channel(s).",
            )
        }

        let frameCount = AVAudioFrameCount(chunk.samples.count / chunk.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback could not allocate a PCM buffer for request '\(chunk.requestID)'.",
            )
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw GeneratedAudioOutputError.invalidChunk(
                requestID: chunk.requestID,
                message: "Local generated-audio playback could not access PCM channel storage for request '\(chunk.requestID)'.",
            )
        }

        if chunk.channelCount == 1 {
            channelData[0].update(from: chunk.samples, count: chunk.samples.count)
        } else {
            for frameIndex in 0..<Int(frameCount) {
                for channelIndex in 0..<chunk.channelCount {
                    channelData[channelIndex][frameIndex] = chunk.samples[frameIndex * chunk.channelCount + channelIndex]
                }
            }
        }
        playerNode.scheduleBuffer(buffer)
    }
}
