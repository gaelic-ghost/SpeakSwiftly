import AVFoundation
import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS

// MARK: - Model Client

private final class UnsafeSpeechGenerationModelBox: @unchecked Sendable {
    let model: any SpeechGenerationModel

    init(model: any SpeechGenerationModel) {
        self.model = model
    }
}

final class AnySpeechModel: @unchecked Sendable {
    private let sampleRateValue: Int
    private let generateImpl: @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?
    ) async throws -> [Float]
    private let generateSamplesStreamImpl: @Sendable (
        _ text: String,
        _ voice: String?,
        _ refAudio: MLXArray?,
        _ refText: String?,
        _ language: String?,
        _ streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error>

    var sampleRate: Int {
        sampleRateValue
    }

    init(
        sampleRate: Int,
        generate: @escaping @Sendable (
            _ text: String,
            _ voice: String?,
            _ refAudio: MLXArray?,
            _ refText: String?,
            _ language: String?
        ) async throws -> [Float],
        generateSamplesStream: @escaping @Sendable (
            _ text: String,
            _ voice: String?,
            _ refAudio: MLXArray?,
            _ refText: String?,
            _ language: String?,
            _ streamingInterval: Double
        ) -> AsyncThrowingStream<[Float], Error>
    ) {
        sampleRateValue = sampleRate
        generateImpl = generate
        generateSamplesStreamImpl = generateSamplesStream
    }

    convenience init(model: any SpeechGenerationModel) {
        let box = UnsafeSpeechGenerationModelBox(model: model)

        self.init(
            sampleRate: box.model.sampleRate,
            generate: { text, voice, refAudio, refText, language in
                try await box.model.generate(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: nil
                ).asArray(Float.self)
            },
            generateSamplesStream: { text, voice, refAudio, refText, language, streamingInterval in
                box.model.generateSamplesStream(
                    text: text,
                    voice: voice,
                    refAudio: refAudio,
                    refText: refText,
                    language: language,
                    generationParameters: nil,
                    streamingInterval: streamingInterval
                )
            }
        )
    }

    func generate(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?
    ) async throws -> [Float] {
        try await generateImpl(text, voice, refAudio, refText, language)
    }

    func generateSamplesStream(
        text: String,
        voice: String?,
        refAudio: MLXArray?,
        refText: String?,
        language: String?,
        streamingInterval: Double
    ) -> AsyncThrowingStream<[Float], Error> {
        generateSamplesStreamImpl(text, voice, refAudio, refText, language, streamingInterval)
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

final class AnyPlaybackController: @unchecked Sendable {
    private let playImpl: @Sendable (
        _ sampleRate: Double,
        _ stream: AsyncThrowingStream<[Float], Error>,
        _ onFirstChunk: @escaping @Sendable () async -> Void
    ) async throws -> Void
    private let stopImpl: @Sendable () async -> Void

    init(
        play: @escaping @Sendable (
            _ sampleRate: Double,
            _ stream: AsyncThrowingStream<[Float], Error>,
            _ onFirstChunk: @escaping @Sendable () async -> Void
        ) async throws -> Void,
        stop: @escaping @Sendable () async -> Void
    ) {
        playImpl = play
        stopImpl = stop
    }

    convenience init(_ controller: PlaybackController) {
        self.init(
            play: { sampleRate, stream, onFirstChunk in
                try await controller.play(
                    sampleRate: sampleRate,
                    stream: stream,
                    onFirstChunk: onFirstChunk
                )
            },
            stop: {
                await controller.stop()
            }
        )
    }

    func play(
        sampleRate: Double,
        stream: AsyncThrowingStream<[Float], Error>,
        onFirstChunk: @escaping @Sendable () async -> Void
    ) async throws {
        try await playImpl(sampleRate, stream, onFirstChunk)
    }

    func stop() async {
        await stopImpl()
    }
}

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
    let makePlaybackController: @MainActor @Sendable () -> AnyPlaybackController
    let writeWAV: @Sendable (_ samples: [Float], _ sampleRate: Int, _ url: URL) throws -> Void
    let loadAudioSamples: @Sendable (_ url: URL, _ sampleRate: Int) throws -> MLXArray?
    let writeStdout: @Sendable (Data) throws -> Void
    let writeStderr: @Sendable (String) -> Void
    let now: @Sendable () -> Date

    static func live(fileManager: FileManager = .default) -> WorkerDependencies {
        WorkerDependencies(
            fileManager: fileManager,
            loadResidentModel: { try await ModelFactory.loadResidentModel() },
            loadProfileModel: { try await ModelFactory.loadProfileModel() },
            makePlaybackController: { AnyPlaybackController(PlaybackController()) },
            writeWAV: { samples, sampleRate, url in
                try AudioUtils.writeWavFile(samples: samples, sampleRate: sampleRate, fileURL: url)
            },
            loadAudioSamples: { url, sampleRate in
                let (_, audio) = try MLXAudioCore.loadAudioArray(from: url, sampleRate: sampleRate)
                return audio
            },
            writeStdout: { data in
                try FileHandle.standardOutput.write(contentsOf: data)
            },
            writeStderr: { message in
                do {
                    try FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
                } catch {
                    fputs(message + "\n", stderr)
                }
            },
            now: Date.init
        )
    }
}
