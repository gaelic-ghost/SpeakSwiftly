@preconcurrency import AVFoundation
import Darwin
import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS

// MARK: - Model Client

private enum WorkerEnvironment {
    static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
    static let playbackTrace = "SPEAKSWIFTLY_PLAYBACK_TRACE"
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
    case prerollReady(startupBufferedAudioMS: Int)
    case queueDepthLow(queuedAudioMS: Int)
    case rebufferStarted(queuedAudioMS: Int)
    case rebufferResumed(bufferedAudioMS: Int)
    case chunkGapWarning(gapMS: Int, chunkIndex: Int)
    case scheduleGapWarning(gapMS: Int, bufferIndex: Int, queuedAudioMS: Int)
    case rebufferThrashWarning(rebufferEventCount: Int, windowMS: Int)
    case bufferShapeSummary(
        maxBoundaryDiscontinuity: Double,
        maxLeadingAbsAmplitude: Double,
        maxTrailingAbsAmplitude: Double,
        fadeInChunkCount: Int
    )
    case trace(PlaybackTraceEvent)
    case starved
}

struct PlaybackTraceEvent: Sendable {
    let name: String
    let chunkIndex: Int?
    let bufferIndex: Int?
    let sampleCount: Int?
    let durationMS: Int?
    let queuedAudioBeforeMS: Int?
    let queuedAudioAfterMS: Int?
    let gapMS: Int?
    let isRebuffering: Bool?
    let fadeInApplied: Bool?
}

enum PlaybackMetricsConfiguration {
    static let startupBufferTargetMS = 360
    static let lowWaterTargetMS = 140
    static let chunkGapWarningMS = 450
    static let scheduleGapWarningMS = 180
    static let rebufferThrashWarningCount = 3
    static let rebufferThrashWindowMS = 2_000
}

struct PlaybackSummary: Sendable {
    let chunkCount: Int
    let sampleCount: Int
    let startupBufferedAudioMS: Int?
    let timeToFirstChunkMS: Int?
    let timeToPrerollReadyMS: Int?
    let timeFromPrerollReadyToDrainMS: Int?
    let minQueuedAudioMS: Int?
    let maxQueuedAudioMS: Int?
    let avgQueuedAudioMS: Int?
    let queueDepthSampleCount: Int
    let rebufferEventCount: Int
    let rebufferTotalDurationMS: Int
    let longestRebufferDurationMS: Int
    let starvationEventCount: Int
    let scheduleCallbackCount: Int
    let playedBackCallbackCount: Int
    let maxInterChunkGapMS: Int?
    let avgInterChunkGapMS: Int?
    let maxScheduleGapMS: Int?
    let avgScheduleGapMS: Int?
    let maxBoundaryDiscontinuity: Double?
    let maxLeadingAbsAmplitude: Double?
    let maxTrailingAbsAmplitude: Double?
    let fadeInChunkCount: Int
}

struct RuntimeMemorySnapshot: Sendable {
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
    let mlxCacheLimitBytes: Int?
    let mlxMemoryLimitBytes: Int?
}

final class AnyPlaybackController: @unchecked Sendable {
    private let prepareImpl: @Sendable (_ sampleRate: Double) async throws -> Bool
    private let playImpl: @Sendable (
        _ sampleRate: Double,
        _ stream: AsyncThrowingStream<[Float], Error>,
        _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary
    private let stopImpl: @Sendable () async -> Void

    init(
        prepare: @escaping @Sendable (_ sampleRate: Double) async throws -> Bool,
        play: @escaping @Sendable (
            _ sampleRate: Double,
            _ stream: AsyncThrowingStream<[Float], Error>,
            _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
        ) async throws -> PlaybackSummary,
        stop: @escaping @Sendable () async -> Void
    ) {
        prepareImpl = prepare
        playImpl = play
        stopImpl = stop
    }

    convenience init(_ controller: PlaybackController) {
        self.init(
            prepare: { sampleRate in
                try await controller.prepare(sampleRate: sampleRate)
            },
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

    static func silent(traceEnabled: Bool = false) -> AnyPlaybackController {
        AnyPlaybackController(
            prepare: { _ in true },
            play: { sampleRate, stream, onEvent in
                let startedAt = Date()
                var emittedFirstChunk = false
                var emittedPrerollReady = false
                var chunkCount = 0
                var sampleCount = 0
                var startupBufferedAudioMS: Int?
                var timeToFirstChunkMS: Int?
                var timeToPrerollReadyMS: Int?
                var minQueuedAudioMS: Int?
                var maxQueuedAudioMS: Int?
                var queueDepthTotalMS = 0
                var queueDepthSampleCount = 0
                var maxInterChunkGapMS: Int?
                var interChunkGapTotalMS = 0
                var interChunkGapCount = 0
                var maxBoundaryDiscontinuity: Double?
                var maxLeadingAbsAmplitude: Double?
                var maxTrailingAbsAmplitude: Double?
                var fadeInChunkCount = 0
                let starvationEventCount = 0
                var pendingSampleCount = 0
                var lastChunkAt: Date?
                var previousTrailingSample: Float?

                func bufferedAudioMS() -> Int {
                    Int((Double(pendingSampleCount) / sampleRate * 1_000).rounded())
                }

                func recordQueueDepth() {
                    let queuedAudioMS = bufferedAudioMS()
                    minQueuedAudioMS = min(minQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
                    maxQueuedAudioMS = max(maxQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
                    queueDepthTotalMS += queuedAudioMS
                    queueDepthSampleCount += 1
                }

                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }
                    let now = Date()
                    chunkCount += 1
                    sampleCount += chunk.count
                    pendingSampleCount += chunk.count
                    recordQueueDepth()

                    if let lastChunkAt {
                        let gapMS = milliseconds(since: lastChunkAt)
                        maxInterChunkGapMS = max(maxInterChunkGapMS ?? gapMS, gapMS)
                        interChunkGapTotalMS += gapMS
                        interChunkGapCount += 1
                        if gapMS >= PlaybackMetricsConfiguration.chunkGapWarningMS {
                            await onEvent(.chunkGapWarning(gapMS: gapMS, chunkIndex: chunkCount))
                        }
                    }
                    lastChunkAt = now

                    if let firstSample = chunk.first, let lastSample = chunk.last {
                        let leadingAbs = Double(abs(firstSample))
                        let trailingAbs = Double(abs(lastSample))
                        maxLeadingAbsAmplitude = max(maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
                        maxTrailingAbsAmplitude = max(maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
                        if let previousTrailingSample {
                            let jump = Double(abs(firstSample - previousTrailingSample))
                            maxBoundaryDiscontinuity = max(maxBoundaryDiscontinuity ?? jump, jump)
                        }
                        previousTrailingSample = lastSample
                    }

                    if !emittedFirstChunk {
                        emittedFirstChunk = true
                        fadeInChunkCount = 1
                        timeToFirstChunkMS = milliseconds(since: startedAt)
                        await onEvent(.firstChunk)
                    }

                    if !emittedPrerollReady, bufferedAudioMS() >= PlaybackMetricsConfiguration.startupBufferTargetMS {
                        emittedPrerollReady = true
                        startupBufferedAudioMS = bufferedAudioMS()
                        minQueuedAudioMS = startupBufferedAudioMS
                        timeToPrerollReadyMS = milliseconds(since: startedAt)
                        await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0))
                    }

                    if traceEnabled {
                        await onEvent(
                            .trace(
                                PlaybackTraceEvent(
                                    name: "chunk_received",
                                    chunkIndex: chunkCount,
                                    bufferIndex: nil,
                                    sampleCount: chunk.count,
                                    durationMS: Int((Double(chunk.count) / sampleRate * 1_000).rounded()),
                                    queuedAudioBeforeMS: nil,
                                    queuedAudioAfterMS: bufferedAudioMS(),
                                    gapMS: maxInterChunkGapMS,
                                    isRebuffering: false,
                                    fadeInApplied: chunkCount == 1
                                )
                            )
                        )
                    }
                }

                if !emittedPrerollReady, pendingSampleCount > 0 {
                    emittedPrerollReady = true
                    startupBufferedAudioMS = bufferedAudioMS()
                    minQueuedAudioMS = startupBufferedAudioMS
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0))
                }

                let timeFromPrerollReadyToDrainMS: Int?
                if let timeToPrerollReadyMS {
                    timeFromPrerollReadyToDrainMS = max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
                } else {
                    timeFromPrerollReadyToDrainMS = nil
                }

                if let maxBoundaryDiscontinuity, let maxLeadingAbsAmplitude, let maxTrailingAbsAmplitude {
                    await onEvent(
                        .bufferShapeSummary(
                            maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                            maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                            maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                            fadeInChunkCount: fadeInChunkCount
                        )
                    )
                }

                return PlaybackSummary(
                    chunkCount: chunkCount,
                    sampleCount: sampleCount,
                    startupBufferedAudioMS: startupBufferedAudioMS,
                    timeToFirstChunkMS: timeToFirstChunkMS,
                    timeToPrerollReadyMS: timeToPrerollReadyMS,
                    timeFromPrerollReadyToDrainMS: timeFromPrerollReadyToDrainMS,
                    minQueuedAudioMS: minQueuedAudioMS,
                    maxQueuedAudioMS: maxQueuedAudioMS,
                    avgQueuedAudioMS: queueDepthSampleCount == 0 ? nil : queueDepthTotalMS / queueDepthSampleCount,
                    queueDepthSampleCount: queueDepthSampleCount,
                    rebufferEventCount: 0,
                    rebufferTotalDurationMS: 0,
                    longestRebufferDurationMS: 0,
                    starvationEventCount: starvationEventCount,
                    scheduleCallbackCount: chunkCount,
                    playedBackCallbackCount: chunkCount,
                    maxInterChunkGapMS: maxInterChunkGapMS,
                    avgInterChunkGapMS: interChunkGapCount == 0 ? nil : interChunkGapTotalMS / interChunkGapCount,
                    maxScheduleGapMS: nil,
                    avgScheduleGapMS: nil,
                    maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                    maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                    maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                    fadeInChunkCount: fadeInChunkCount
                )
            },
            stop: {}
        )
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        try await prepareImpl(sampleRate)
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
    @MainActor
    private final class RequestPlaybackState {
        let requestID: UInt64
        var generationFinished = false
        var isRebuffering = false
        var scheduledSampleCount = 0
        var playedBackSampleCount = 0
        var minQueuedAudioMS: Int?
        var maxQueuedAudioMS: Int?
        var queueDepthTotalMS = 0
        var queueDepthSampleCount = 0
        var rebufferEventCount = 0
        var rebufferStartedAt: Date?
        var rebufferTotalDurationMS = 0
        var longestRebufferDurationMS = 0
        var recentRebufferStartTimes = [Date]()
        var emittedRebufferThrashWarning = false
        var starvationEventCount = 0
        var emittedLowQueueWarning = false
        var scheduleCallbackCount = 0
        var playedBackCallbackCount = 0
        var lastTrailingSample: Float?
        var maxBoundaryDiscontinuity: Double?
        var maxLeadingAbsAmplitude: Double?
        var maxTrailingAbsAmplitude: Double?
        var fadeInChunkCount = 0
        var drainContinuation: CheckedContinuation<Void, Error>?

        init(requestID: UInt64) {
            self.requestID = requestID
        }

        func queuedAudioMS(sampleRate: Double) -> Int {
            let queuedSamples = max(scheduledSampleCount - playedBackSampleCount, 0)
            return Int((Double(queuedSamples) / sampleRate * 1_000).rounded())
        }

        func recordQueuedAudioDepth(sampleRate: Double) {
            let currentQueuedAudioMS = queuedAudioMS(sampleRate: sampleRate)
            minQueuedAudioMS = min(minQueuedAudioMS ?? currentQueuedAudioMS, currentQueuedAudioMS)
            maxQueuedAudioMS = max(maxQueuedAudioMS ?? currentQueuedAudioMS, currentQueuedAudioMS)
            queueDepthTotalMS += currentQueuedAudioMS
            queueDepthSampleCount += 1
        }
    }

    private enum PlaybackConfiguration {
        static let drainTimeout: Duration = .seconds(5)
        static let lowQueueThresholdMS = 100
        static let channels: AVAudioChannelCount = 1
    }

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingFormat: AVAudioFormat?
    private var engineSampleRate: Double?
    private var nextRequestID: UInt64 = 0
    private let traceEnabled: Bool

    init(traceEnabled: Bool = false) {
        self.traceEnabled = traceEnabled
    }

    func prepare(sampleRate: Double) throws -> Bool {
        let needsSetup = audioEngine == nil || playerNode == nil || engineSampleRate != sampleRate
        if needsSetup {
            try rebuildEngine(sampleRate: sampleRate)
        } else if audioEngine?.isRunning == false {
            try audioEngine?.start()
        }

        if playerNode?.isPlaying == false {
            playerNode?.play()
        }

        return needsSetup
    }

    func play(
        sampleRate: Double,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary {
        _ = try prepare(sampleRate: sampleRate)

        let startedAt = Date()
        let requestID = nextRequestID
        nextRequestID += 1
        let state = RequestPlaybackState(requestID: requestID)
        var emittedFirstChunk = false
        var emittedPrerollReady = false
        var startedPlayback = false
        var chunkCount = 0
        var sampleCount = 0
        var startupBufferedAudioMS: Int?
        var timeToFirstChunkMS: Int?
        var timeToPrerollReadyMS: Int?
        var pendingBuffers = [
            (
                buffer: AVAudioPCMBuffer,
                frameCount: Int,
                firstSample: Float,
                lastSample: Float,
                fadeInApplied: Bool,
                chunkIndex: Int
            )
        ]()
        var pendingSampleCount = 0
        var lastChunkReceivedAt: Date?
        var interChunkGapTotalMS = 0
        var interChunkGapCount = 0
        var maxInterChunkGapMS: Int?
        var lastScheduleAt: Date?
        var scheduleGapTotalMS = 0
        var scheduleGapCount = 0
        var maxScheduleGapMS: Int?
        var bufferIndex = 0
        var lastPreparedTrailingSample: Float?

        func bufferedAudioMS() -> Int {
            Int((Double(pendingSampleCount) / sampleRate * 1_000).rounded())
        }

        func scheduleForPlayback(
            _ buffer: AVAudioPCMBuffer,
            frameCount: Int,
            firstSample: Float,
            lastSample: Float,
            fadeInApplied: Bool,
            chunkIndex: Int
        ) async {
            let queuedAudioBeforeMS = state.queuedAudioMS(sampleRate: sampleRate)
            let scheduledAt = Date()
            if let lastScheduleAt {
                let gapMS = milliseconds(since: lastScheduleAt)
                maxScheduleGapMS = max(maxScheduleGapMS ?? gapMS, gapMS)
                scheduleGapTotalMS += gapMS
                scheduleGapCount += 1
                if startedPlayback, gapMS >= PlaybackMetricsConfiguration.scheduleGapWarningMS {
                    await onEvent(
                        .scheduleGapWarning(
                            gapMS: gapMS,
                            bufferIndex: bufferIndex + 1,
                            queuedAudioMS: queuedAudioBeforeMS
                        )
                    )
                }
            }
            lastScheduleAt = scheduledAt
            bufferIndex += 1
            let currentBufferIndex = bufferIndex

            let leadingAbs = Double(abs(firstSample))
            let trailingAbs = Double(abs(lastSample))
            state.maxLeadingAbsAmplitude = max(state.maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
            state.maxTrailingAbsAmplitude = max(state.maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
            if fadeInApplied {
                state.fadeInChunkCount += 1
            }
            if let lastTrailingSample = state.lastTrailingSample {
                let jump = Double(abs(firstSample - lastTrailingSample))
                state.maxBoundaryDiscontinuity = max(state.maxBoundaryDiscontinuity ?? jump, jump)
            }
            state.lastTrailingSample = lastSample

            state.scheduledSampleCount += frameCount
            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: sampleRate)
            let queuedAudioAfterMS = state.queuedAudioMS(sampleRate: sampleRate)
            if traceEnabled {
                await onEvent(
                    .trace(
                        PlaybackTraceEvent(
                            name: "buffer_scheduled",
                            chunkIndex: chunkIndex,
                            bufferIndex: currentBufferIndex,
                            sampleCount: frameCount,
                            durationMS: Int((Double(frameCount) / sampleRate * 1_000).rounded()),
                            queuedAudioBeforeMS: queuedAudioBeforeMS,
                            queuedAudioAfterMS: queuedAudioAfterMS,
                            gapMS: maxScheduleGapMS,
                            isRebuffering: state.isRebuffering,
                            fadeInApplied: fadeInApplied
                        )
                    )
                )
            }
            scheduleBuffer(buffer, callbackType: .dataPlayedBack) { callbackType in
                guard callbackType == .dataPlayedBack else { return }
                Task { @MainActor in
                    guard requestID + 1 == self.nextRequestID else { return }

                    state.playedBackSampleCount += frameCount
                    state.playedBackCallbackCount += 1
                    state.recordQueuedAudioDepth(sampleRate: sampleRate)

                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if self.traceEnabled {
                        await onEvent(
                            .trace(
                                PlaybackTraceEvent(
                                    name: "buffer_played_back",
                                    chunkIndex: chunkIndex,
                                    bufferIndex: currentBufferIndex,
                                    sampleCount: frameCount,
                                    durationMS: Int((Double(frameCount) / sampleRate * 1_000).rounded()),
                                    queuedAudioBeforeMS: nil,
                                    queuedAudioAfterMS: currentQueuedAudioMS,
                                    gapMS: nil,
                                    isRebuffering: state.isRebuffering,
                                    fadeInApplied: fadeInApplied
                                )
                            )
                        )
                    }
                    if !state.generationFinished, currentQueuedAudioMS <= 0 {
                        state.starvationEventCount += 1
                        await onEvent(.starved)
                        return
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= PlaybackMetricsConfiguration.lowWaterTargetMS,
                       !state.isRebuffering
                    {
                        state.isRebuffering = true
                        state.rebufferEventCount += 1
                        let now = Date()
                        state.rebufferStartedAt = now
                        state.recentRebufferStartTimes.append(now)
                        state.recentRebufferStartTimes.removeAll {
                            now.timeIntervalSince($0) * 1_000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                        }
                        self.playerNode?.pause()
                        await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS))
                        if !state.emittedRebufferThrashWarning,
                           state.recentRebufferStartTimes.count >= PlaybackMetricsConfiguration.rebufferThrashWarningCount
                        {
                            state.emittedRebufferThrashWarning = true
                            await onEvent(
                                .rebufferThrashWarning(
                                    rebufferEventCount: state.rebufferEventCount,
                                    windowMS: PlaybackMetricsConfiguration.rebufferThrashWindowMS
                                )
                            )
                        }
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= PlaybackConfiguration.lowQueueThresholdMS,
                       !state.emittedLowQueueWarning
                    {
                        state.emittedLowQueueWarning = true
                        await onEvent(.queueDepthLow(queuedAudioMS: currentQueuedAudioMS))
                    } else if currentQueuedAudioMS > PlaybackConfiguration.lowQueueThresholdMS {
                        state.emittedLowQueueWarning = false
                    }

                    if state.isRebuffering,
                       (currentQueuedAudioMS >= PlaybackMetricsConfiguration.startupBufferTargetMS || state.generationFinished)
                    {
                        self.playerNode?.play()
                        state.isRebuffering = false
                        if let rebufferStartedAt = state.rebufferStartedAt {
                            let durationMS = milliseconds(since: rebufferStartedAt)
                            state.rebufferTotalDurationMS += durationMS
                            state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                            state.rebufferStartedAt = nil
                        }
                        await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS))
                    }

                    if state.generationFinished, currentQueuedAudioMS == 0 {
                        state.drainContinuation?.resume()
                        state.drainContinuation = nil
                    }
                }
            }
        }

        do {
            for try await chunk in stream {
                guard !chunk.isEmpty else { continue }
                let now = Date()
                chunkCount += 1
                sampleCount += chunk.count
                if let lastChunkReceivedAt {
                    let gapMS = milliseconds(since: lastChunkReceivedAt)
                    maxInterChunkGapMS = max(maxInterChunkGapMS ?? gapMS, gapMS)
                    interChunkGapTotalMS += gapMS
                    interChunkGapCount += 1
                    if startedPlayback, gapMS >= PlaybackMetricsConfiguration.chunkGapWarningMS {
                        await onEvent(.chunkGapWarning(gapMS: gapMS, chunkIndex: chunkCount))
                    }
                }
                lastChunkReceivedAt = now
                if traceEnabled {
                    await onEvent(
                        .trace(
                            PlaybackTraceEvent(
                                name: "chunk_received",
                                chunkIndex: chunkCount,
                                bufferIndex: nil,
                                sampleCount: chunk.count,
                                durationMS: Int((Double(chunk.count) / sampleRate * 1_000).rounded()),
                                queuedAudioBeforeMS: startedPlayback ? state.queuedAudioMS(sampleRate: sampleRate) : bufferedAudioMS(),
                                queuedAudioAfterMS: nil,
                                gapMS: maxInterChunkGapMS,
                                isRebuffering: state.isRebuffering,
                                fadeInApplied: !emittedFirstChunk
                            )
                        )
                    )
                }
                if let buffer = makePCMBuffer(
                    from: chunk,
                    sampleRate: sampleRate,
                    previousTrailingSample: lastPreparedTrailingSample,
                    applyFadeIn: !emittedFirstChunk
                ) {
                    lastPreparedTrailingSample = buffer.lastSample
                    let frameCount = buffer.frameCount
                    if startedPlayback {
                        await scheduleForPlayback(
                            buffer.buffer,
                            frameCount: frameCount,
                            firstSample: buffer.firstSample,
                            lastSample: buffer.lastSample,
                            fadeInApplied: buffer.fadeInApplied,
                            chunkIndex: chunkCount
                        )
                        if state.isRebuffering {
                            let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                            if currentQueuedAudioMS >= PlaybackMetricsConfiguration.startupBufferTargetMS {
                                playerNode?.play()
                                state.isRebuffering = false
                                if let rebufferStartedAt = state.rebufferStartedAt {
                                    let durationMS = milliseconds(since: rebufferStartedAt)
                                    state.rebufferTotalDurationMS += durationMS
                                    state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                                    state.rebufferStartedAt = nil
                                }
                                await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS))
                            }
                        }
                    } else {
                        pendingBuffers.append(
                            (
                                buffer: buffer.buffer,
                                frameCount: frameCount,
                                firstSample: buffer.firstSample,
                                lastSample: buffer.lastSample,
                                fadeInApplied: buffer.fadeInApplied,
                                chunkIndex: chunkCount
                            )
                        )
                        pendingSampleCount += frameCount
                    }
                }

                if !emittedFirstChunk {
                    emittedFirstChunk = true
                    timeToFirstChunkMS = milliseconds(since: startedAt)
                    await onEvent(.firstChunk)
                }

                if !startedPlayback, bufferedAudioMS() >= PlaybackMetricsConfiguration.startupBufferTargetMS {
                    startupBufferedAudioMS = bufferedAudioMS()

                    for pending in pendingBuffers {
                        await scheduleForPlayback(
                            pending.buffer,
                            frameCount: pending.frameCount,
                            firstSample: pending.firstSample,
                            lastSample: pending.lastSample,
                            fadeInApplied: pending.fadeInApplied,
                            chunkIndex: pending.chunkIndex
                        )
                    }

                    pendingBuffers.removeAll(keepingCapacity: true)
                    pendingSampleCount = 0
                    startedPlayback = true
                    emittedPrerollReady = true
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0))
                }
            }

            state.generationFinished = true
            if !startedPlayback, !pendingBuffers.isEmpty {
                startupBufferedAudioMS = bufferedAudioMS()

                for pending in pendingBuffers {
                    await scheduleForPlayback(
                        pending.buffer,
                        frameCount: pending.frameCount,
                        firstSample: pending.firstSample,
                        lastSample: pending.lastSample,
                        fadeInApplied: pending.fadeInApplied,
                        chunkIndex: pending.chunkIndex
                    )
                }

                pendingBuffers.removeAll(keepingCapacity: true)
                pendingSampleCount = 0
                startedPlayback = true
                if state.isRebuffering {
                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    playerNode?.play()
                    state.isRebuffering = false
                    if let rebufferStartedAt = state.rebufferStartedAt {
                        let durationMS = milliseconds(since: rebufferStartedAt)
                        state.rebufferTotalDurationMS += durationMS
                        state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                        state.rebufferStartedAt = nil
                    }
                    await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS))
                }
            }

            if !emittedPrerollReady, chunkCount > 0 {
                emittedPrerollReady = true
                startupBufferedAudioMS = startupBufferedAudioMS ?? state.queuedAudioMS(sampleRate: sampleRate)
                timeToPrerollReadyMS = milliseconds(since: startedAt)
                await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0))
            }

            try await waitForPlaybackDrain(
                state: state,
                sampleRate: sampleRate
            )
            if let maxBoundaryDiscontinuity = state.maxBoundaryDiscontinuity,
               let maxLeadingAbsAmplitude = state.maxLeadingAbsAmplitude,
               let maxTrailingAbsAmplitude = state.maxTrailingAbsAmplitude
            {
                await onEvent(
                    .bufferShapeSummary(
                        maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                        maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                        maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                        fadeInChunkCount: state.fadeInChunkCount
                    )
                )
            }
            let timeFromPrerollReadyToDrainMS: Int?
            if let timeToPrerollReadyMS {
                timeFromPrerollReadyToDrainMS = max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
            } else {
                timeFromPrerollReadyToDrainMS = nil
            }

            resetPlayerNodeForNextRequest()

            return PlaybackSummary(
                chunkCount: chunkCount,
                sampleCount: sampleCount,
                startupBufferedAudioMS: startupBufferedAudioMS,
                timeToFirstChunkMS: timeToFirstChunkMS,
                timeToPrerollReadyMS: timeToPrerollReadyMS,
                timeFromPrerollReadyToDrainMS: timeFromPrerollReadyToDrainMS,
                minQueuedAudioMS: state.minQueuedAudioMS,
                maxQueuedAudioMS: state.maxQueuedAudioMS,
                avgQueuedAudioMS: state.queueDepthSampleCount == 0 ? nil : state.queueDepthTotalMS / state.queueDepthSampleCount,
                queueDepthSampleCount: state.queueDepthSampleCount,
                rebufferEventCount: state.rebufferEventCount,
                rebufferTotalDurationMS: state.rebufferTotalDurationMS,
                longestRebufferDurationMS: state.longestRebufferDurationMS,
                starvationEventCount: state.starvationEventCount
                ,
                scheduleCallbackCount: state.scheduleCallbackCount,
                playedBackCallbackCount: state.playedBackCallbackCount,
                maxInterChunkGapMS: maxInterChunkGapMS,
                avgInterChunkGapMS: interChunkGapCount == 0 ? nil : interChunkGapTotalMS / interChunkGapCount,
                maxScheduleGapMS: maxScheduleGapMS,
                avgScheduleGapMS: scheduleGapCount == 0 ? nil : scheduleGapTotalMS / scheduleGapCount,
                maxBoundaryDiscontinuity: state.maxBoundaryDiscontinuity,
                maxLeadingAbsAmplitude: state.maxLeadingAbsAmplitude,
                maxTrailingAbsAmplitude: state.maxTrailingAbsAmplitude,
                fadeInChunkCount: state.fadeInChunkCount
            )
        } catch is CancellationError {
            resetPlayerNodeForNextRequest()
            throw CancellationError()
        } catch {
            resetPlayerNodeForNextRequest()
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
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        streamingFormat = nil
        engineSampleRate = nil
    }

    private func waitForPlaybackDrain(
        state: RequestPlaybackState,
        sampleRate: Double
    ) async throws {
        let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
        if currentQueuedAudioMS == 0 {
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        state.drainContinuation = continuation
                        if state.queuedAudioMS(sampleRate: sampleRate) == 0 {
                            state.drainContinuation?.resume()
                            state.drainContinuation = nil
                        }
                    }
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

    private func rebuildEngine(sampleRate: Double) throws {
        stop()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels
        )

        guard let format else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback could not create an AVAudioFormat for sample rate \(sampleRate)."
            )
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        node.play()

        audioEngine = engine
        playerNode = node
        streamingFormat = format
        engineSampleRate = sampleRate
    }

    private func resetPlayerNodeForNextRequest() {
        playerNode?.stop()
        playerNode?.reset()
        playerNode?.play()
    }

    private func makePCMBuffer(
        from samples: [Float],
        sampleRate: Double,
        previousTrailingSample: Float?,
        applyFadeIn: Bool
    ) -> (buffer: AVAudioPCMBuffer, frameCount: Int, firstSample: Float, lastSample: Float, fadeInApplied: Bool)? {
        guard let format = streamingFormat ?? AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels
        ) else {
            return nil
        }

        let processedSamples = shapePlaybackSamples(
            samples,
            sampleRate: format.sampleRate,
            previousTrailingSample: previousTrailingSample,
            applyFadeIn: applyFadeIn
        )
        guard let firstSample = processedSamples.first, let lastSample = processedSamples.last else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(processedSamples.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(processedSamples.count)
        if let channelData = buffer.floatChannelData {
            processedSamples.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: processedSamples.count)
            }
        }

        return (
            buffer: buffer,
            frameCount: Int(buffer.frameLength),
            firstSample: firstSample,
            lastSample: lastSample,
            fadeInApplied: applyFadeIn
        )
    }

    private func scheduleBuffer(
        _ buffer: AVAudioPCMBuffer,
        callbackType: AVAudioPlayerNodeCompletionCallbackType,
        completion: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void
    ) {
        playerNode?.scheduleBuffer(
            buffer,
            completionCallbackType: callbackType,
            completionHandler: completion
        )
    }
}

func shapePlaybackSamples(
    _ samples: [Float],
    sampleRate: Double,
    previousTrailingSample: Float?,
    applyFadeIn: Bool
) -> [Float] {
    guard !samples.isEmpty else { return [] }

    let minimumSampleValue: Float = -1
    let maximumSampleValue: Float = 1

    var processedSamples = samples.map { sample in
        if !sample.isFinite {
            return Float.zero
        }
        return min(max(sample, minimumSampleValue), maximumSampleValue)
    }

    if let previousTrailingSample, let currentLeadingSample = processedSamples.first {
        let boundaryJump = currentLeadingSample - previousTrailingSample
        if abs(boundaryJump) >= 0.08 {
            let rampSampleCount = min(max(Int(sampleRate * 0.005), 8), processedSamples.count)
            if rampSampleCount > 0 {
                let rampDivisor = Float(max(rampSampleCount - 1, 1))
                for index in 0..<rampSampleCount {
                    let progress = Float(index) / rampDivisor
                    let correction = boundaryJump * (1 - progress)
                    processedSamples[index] = min(
                        max(processedSamples[index] - correction, minimumSampleValue),
                        maximumSampleValue
                    )
                }
            }
        }
    }

    if applyFadeIn {
        let fadeInSampleCount = min(Int(sampleRate * 0.01), processedSamples.count)
        if fadeInSampleCount > 0 {
            let fadeDivisor = Float(max(fadeInSampleCount - 1, 1))
            for index in 0..<fadeInSampleCount {
                let factor = Float(index) / fadeDivisor
                processedSamples[index] *= factor
            }
        }
    }

    return processedSamples
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
    let readRuntimeMemory: @Sendable () -> RuntimeMemorySnapshot?

    static func live(fileManager: FileManager = .default) -> WorkerDependencies {
        let environment = ProcessInfo.processInfo.environment

        return WorkerDependencies(
            fileManager: fileManager,
            loadResidentModel: { try await ModelFactory.loadResidentModel() },
            loadProfileModel: { try await ModelFactory.loadProfileModel() },
            makePlaybackController: {
                if environment[WorkerEnvironment.silentPlayback] == "1" {
                    return .silent(traceEnabled: environment[WorkerEnvironment.playbackTrace] == "1")
                }

                return AnyPlaybackController(
                    PlaybackController(traceEnabled: environment[WorkerEnvironment.playbackTrace] == "1")
                )
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
            now: Date.init,
            readRuntimeMemory: currentRuntimeMemorySnapshot
        )
    }
}

private func currentRuntimeMemorySnapshot() -> RuntimeMemorySnapshot? {
    var usage = rusage_info_current()
    let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
            proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rebound)
        }
    }

    let snapshot = Memory.snapshot()
    return RuntimeMemorySnapshot(
        processResidentBytes: usageResult == 0 ? Int(usage.ri_resident_size) : nil,
        processPhysFootprintBytes: usageResult == 0 ? Int(usage.ri_phys_footprint) : nil,
        mlxActiveMemoryBytes: snapshot.activeMemory,
        mlxCacheMemoryBytes: snapshot.cacheMemory,
        mlxPeakMemoryBytes: snapshot.peakMemory,
        mlxCacheLimitBytes: Memory.cacheLimit,
        mlxMemoryLimitBytes: Memory.memoryLimit
    )
}
