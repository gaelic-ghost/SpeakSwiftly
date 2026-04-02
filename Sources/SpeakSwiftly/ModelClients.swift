import AVFoundation
import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS

// MARK: - Model Client

private enum WorkerEnvironment {
    static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
}

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

enum PlaybackEvent: Sendable {
    case firstChunk
    case prerollReady
}

private let playbackPrerollChunkTarget = 3

struct PlaybackSummary: Sendable {
    let chunkCount: Int
    let sampleCount: Int
    let prerollChunkCount: Int
    let timeToFirstChunkMS: Int?
    let timeToPrerollReadyMS: Int?
    let timeFromPrerollReadyToDrainMS: Int?
}

final class AnyPlaybackController: @unchecked Sendable {
    private let playImpl: @Sendable (
        _ sampleRate: Double,
        _ stream: AsyncThrowingStream<[Float], Error>,
        _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary
    private let stopImpl: @Sendable () async -> Void

    init(
        play: @escaping @Sendable (
            _ sampleRate: Double,
            _ stream: AsyncThrowingStream<[Float], Error>,
            _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
        ) async throws -> PlaybackSummary,
        stop: @escaping @Sendable () async -> Void
    ) {
        playImpl = play
        stopImpl = stop
    }

    convenience init(_ controller: PlaybackController) {
        self.init(
            play: { sampleRate, stream, onEvent in
                try await controller.play(
                    sampleRate: sampleRate,
                    stream: stream,
                    onEvent: onEvent
                )
            },
            stop: {
                await controller.stop()
            }
        )
    }

    static func silent() -> AnyPlaybackController {
        AnyPlaybackController(
            play: { _, stream, onEvent in
                let startedAt = Date()
                var emittedFirstChunk = false
                var emittedPrerollReady = false
                var chunkCount = 0
                var sampleCount = 0
                var prerollChunkCount = 0
                var timeToFirstChunkMS: Int?
                var timeToPrerollReadyMS: Int?

                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }
                    chunkCount += 1
                    sampleCount += chunk.count

                    if !emittedFirstChunk {
                        emittedFirstChunk = true
                        timeToFirstChunkMS = milliseconds(since: startedAt)
                        await onEvent(.firstChunk)
                    }

                    if !emittedPrerollReady, chunkCount >= playbackPrerollChunkTarget {
                        emittedPrerollReady = true
                        prerollChunkCount = chunkCount
                        timeToPrerollReadyMS = milliseconds(since: startedAt)
                        await onEvent(.prerollReady)
                    }
                }

                if emittedFirstChunk, !emittedPrerollReady {
                    emittedPrerollReady = true
                    prerollChunkCount = chunkCount
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    await onEvent(.prerollReady)
                }

                let timeFromPrerollReadyToDrainMS: Int?
                if let timeToPrerollReadyMS {
                    timeFromPrerollReadyToDrainMS = max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
                } else {
                    timeFromPrerollReadyToDrainMS = nil
                }

                return PlaybackSummary(
                    chunkCount: chunkCount,
                    sampleCount: sampleCount,
                    prerollChunkCount: prerollChunkCount,
                    timeToFirstChunkMS: timeToFirstChunkMS,
                    timeToPrerollReadyMS: timeToPrerollReadyMS,
                    timeFromPrerollReadyToDrainMS: timeFromPrerollReadyToDrainMS
                )
            },
            stop: {}
        )
    }

    func play(
        sampleRate: Double,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary {
        try await playImpl(sampleRate, stream, onEvent)
    }

    func stop() async {
        await stopImpl()
    }
}

@MainActor
final class PlaybackController {
    private enum PlaybackConfiguration {
        static let drainTimeout: Duration = .seconds(5)
    }

    private let player: AudioPlayer

    init(player: AudioPlayer = AudioPlayer()) {
        self.player = player
    }

    func play(
        sampleRate: Double,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary {
        let streamFinished = AsyncStream<Void>.makeStream()
        let previousCallback = player.onDidFinishStreaming
        let startedAt = Date()
        var bufferedChunks = [[Float]]()
        var startedPlayback = false
        var emittedFirstChunk = false
        var chunkCount = 0
        var sampleCount = 0
        var prerollChunkCount = 0
        var timeToFirstChunkMS: Int?
        var timeToPrerollReadyMS: Int?
        defer { player.onDidFinishStreaming = previousCallback }
        player.onDidFinishStreaming = {
            previousCallback?()
            streamFinished.continuation.yield(())
            streamFinished.continuation.finish()
        }

        do {
            for try await chunk in stream {
                guard !chunk.isEmpty else { continue }
                chunkCount += 1
                sampleCount += chunk.count

                if !emittedFirstChunk {
                    emittedFirstChunk = true
                    timeToFirstChunkMS = milliseconds(since: startedAt)
                    await onEvent(.firstChunk)
                }

                if !startedPlayback {
                    bufferedChunks.append(chunk)

                    if bufferedChunks.count >= playbackPrerollChunkTarget {
                        player.startStreaming(sampleRate: sampleRate)
                        startedPlayback = true
                        prerollChunkCount = bufferedChunks.count
                        timeToPrerollReadyMS = milliseconds(since: startedAt)
                        await onEvent(.prerollReady)

                        for bufferedChunk in bufferedChunks {
                            player.scheduleAudioChunk(bufferedChunk)
                        }
                        bufferedChunks.removeAll(keepingCapacity: true)
                    }
                } else {
                    player.scheduleAudioChunk(chunk)
                }
            }

            if !startedPlayback {
                player.startStreaming(sampleRate: sampleRate)
                startedPlayback = true

                if !bufferedChunks.isEmpty {
                    prerollChunkCount = bufferedChunks.count
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    await onEvent(.prerollReady)

                    for bufferedChunk in bufferedChunks {
                        player.scheduleAudioChunk(bufferedChunk)
                    }
                    bufferedChunks.removeAll(keepingCapacity: true)
                }
            }

            player.finishStreamingInput()
            try await waitForPlaybackDrain(streamFinished.stream)
            let timeFromPrerollReadyToDrainMS: Int?
            if let timeToPrerollReadyMS {
                timeFromPrerollReadyToDrainMS = max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
            } else {
                timeFromPrerollReadyToDrainMS = nil
            }

            return PlaybackSummary(
                chunkCount: chunkCount,
                sampleCount: sampleCount,
                prerollChunkCount: prerollChunkCount,
                timeToFirstChunkMS: timeToFirstChunkMS,
                timeToPrerollReadyMS: timeToPrerollReadyMS,
                timeFromPrerollReadyToDrainMS: timeFromPrerollReadyToDrainMS
            )
        } catch is CancellationError {
            player.stopStreaming()
            throw CancellationError()
        } catch {
            player.stopStreaming()
            if let workerError = error as? WorkerError {
                throw workerError
            }

            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback failed while scheduling generated audio into the local audio player. \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        player.stop()
    }

    private func waitForPlaybackDrain(_ stream: AsyncStream<Void>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in stream {
                    break
                }
            }
            group.addTask {
                try await Task.sleep(for: PlaybackConfiguration.drainTimeout)
                throw WorkerError(
                    code: .audioPlaybackTimeout,
                    message: "Live playback timed out after generated audio finished because the local audio player did not report drain completion within \(PlaybackConfiguration.drainTimeout.components.seconds) seconds."
                )
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }
}

private func milliseconds(since start: Date) -> Int {
    Int((Date().timeIntervalSince(start) * 1_000).rounded())
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
        let environment = ProcessInfo.processInfo.environment

        return WorkerDependencies(
            fileManager: fileManager,
            loadResidentModel: { try await ModelFactory.loadResidentModel() },
            loadProfileModel: { try await ModelFactory.loadProfileModel() },
            makePlaybackController: {
                if environment[WorkerEnvironment.silentPlayback] == "1" {
                    return .silent()
                }

                return AnyPlaybackController(PlaybackController())
            },
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
