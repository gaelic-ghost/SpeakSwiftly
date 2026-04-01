import AVFoundation
import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS

// MARK: - Model Client

final class AnySpeechModel: @unchecked Sendable {
    let model: any SpeechGenerationModel

    var sampleRate: Int {
        model.sampleRate
    }

    init(model: any SpeechGenerationModel) {
        self.model = model
    }

    func generate(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?
    ) async throws -> [Float] {
        try await model.generate(
            text: text,
            voice: voice,
            refAudio: refAudio,
            refText: refText,
            language: language,
            generationParameters: nil
        ).asArray(Float.self)
    }

    func generateSamplesStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        model.generateSamplesStream(
            text: text,
            voice: voice,
            refAudio: refAudio,
            refText: refText,
            language: language,
            generationParameters: nil,
            streamingInterval: streamingInterval
        )
    }
}

enum ModelFactory {
    static let residentModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    static let profileModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

    static func loadResidentModel() async throws -> AnySpeechModel {
        try await loadModel(modelRepo: residentModelRepo)
    }

    static func loadProfileModel() async throws -> AnySpeechModel {
        try await loadModel(modelRepo: profileModelRepo)
    }

    private static func loadModel(modelRepo: String) async throws -> AnySpeechModel {
        let model = try await TTS.loadModel(modelRepo: modelRepo)
        return AnySpeechModel(model: model)
    }
}

// MARK: - Playback

@MainActor
final class PlaybackController {
    private let player: AudioPlayer

    init(player: AudioPlayer = AudioPlayer()) {
        self.player = player
    }

    func play(
        sampleRate: Double,
        stream: AsyncThrowingStream<[Float], Error>,
        onFirstChunk: @escaping @Sendable () async -> Void
    ) async throws {
        let streamFinished = AsyncStream<Void>.makeStream()
        let previousCallback = player.onDidFinishStreaming
        player.onDidFinishStreaming = {
            previousCallback?()
            streamFinished.continuation.yield(())
            streamFinished.continuation.finish()
        }

        player.startStreaming(sampleRate: sampleRate)

        var emittedFirstChunk = false

        do {
            for try await chunk in stream {
                guard !chunk.isEmpty else { continue }

                if !emittedFirstChunk {
                    emittedFirstChunk = true
                    await onFirstChunk()
                }

                player.scheduleAudioChunk(chunk)
            }

            player.finishStreamingInput()
            for await _ in streamFinished.stream {
                break
            }
        } catch {
            player.stopStreaming()
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback failed while scheduling generated audio into the local audio player. \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        player.stop()
    }
}

// MARK: - Dependencies

struct WorkerDependencies {
    let fileManager: FileManager
    let loadResidentModel: @Sendable () async throws -> AnySpeechModel
    let loadProfileModel: @Sendable () async throws -> AnySpeechModel
    let playbackController: @MainActor () -> PlaybackController
    let writeWAV: @Sendable (_ samples: [Float], _ sampleRate: Int, _ url: URL) throws -> Void
    let loadAudioSamples: @Sendable (_ url: URL, _ sampleRate: Int) throws -> MLXArray
    let now: @Sendable () -> Date

    static func live(fileManager: FileManager = .default) -> WorkerDependencies {
        WorkerDependencies(
            fileManager: fileManager,
            loadResidentModel: { try await ModelFactory.loadResidentModel() },
            loadProfileModel: { try await ModelFactory.loadProfileModel() },
            playbackController: { PlaybackController() },
            writeWAV: { samples, sampleRate, url in
                try AudioUtils.writeWavFile(samples: samples, sampleRate: sampleRate, fileURL: url)
            },
            loadAudioSamples: { url, sampleRate in
                let (_, audio) = try MLXAudioCore.loadAudioArray(from: url, sampleRate: sampleRate)
                return audio
            },
            now: Date.init
        )
    }
}
