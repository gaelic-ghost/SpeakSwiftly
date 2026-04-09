import Foundation

// MARK: - Type-Erased Playback Controller

final class AnyPlaybackController: @unchecked Sendable {
    private let prepareImpl: @Sendable (_ sampleRate: Double) async throws -> Bool
    private let playImpl: @Sendable (
        _ sampleRate: Double,
        _ text: String,
        _ stream: AsyncThrowingStream<[Float], Error>,
        _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary
    private let stopImpl: @Sendable () async -> Void
    private let pauseImpl: @Sendable () async -> PlaybackState
    private let resumeImpl: @Sendable () async -> PlaybackState
    private let stateImpl: @Sendable () async -> PlaybackState
    private let bindEnvironmentEventsImpl: @Sendable (
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?
    ) async -> Void

    init(
        prepare: @escaping @Sendable (_ sampleRate: Double) async throws -> Bool,
        play: @escaping @Sendable (
            _ sampleRate: Double,
            _ text: String,
            _ stream: AsyncThrowingStream<[Float], Error>,
            _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
        ) async throws -> PlaybackSummary,
        stop: @escaping @Sendable () async -> Void,
        pause: @escaping @Sendable () async -> PlaybackState,
        resume: @escaping @Sendable () async -> PlaybackState,
        state: @escaping @Sendable () async -> PlaybackState,
        bindEnvironmentEvents: @escaping @Sendable (
            _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?
        ) async -> Void = { _ in }
    ) {
        prepareImpl = prepare
        playImpl = play
        stopImpl = stop
        pauseImpl = pause
        resumeImpl = resume
        stateImpl = state
        bindEnvironmentEventsImpl = bindEnvironmentEvents
    }

    convenience init(_ controller: AudioPlaybackDriver) {
        self.init(
            prepare: { sampleRate in
                try await controller.prepare(sampleRate: sampleRate)
            },
            play: { sampleRate, text, stream, onEvent in
                try await controller.play(
                    sampleRate: sampleRate,
                    text: text,
                    stream: stream,
                    onEvent: onEvent
                )
            },
            stop: {
                await controller.stop()
            },
            pause: {
                await controller.pause()
            },
            resume: {
                await controller.resume()
            },
            state: {
                await controller.state()
            },
            bindEnvironmentEvents: { sink in
                await controller.setEnvironmentEventSink(sink)
            }
        )
    }

    func bindEnvironmentEvents(
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?
    ) async {
        await bindEnvironmentEventsImpl(sink)
    }

    static func silent(traceEnabled: Bool = false) -> AnyPlaybackController {
        AnyPlaybackController(
            prepare: { _ in true },
            play: { sampleRate, text, stream, onEvent in
                let startedAt = Date()
                let thresholds = PlaybackThresholdController(text: text).thresholds
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
                        if gapMS >= thresholds.chunkGapWarningMS {
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

                    if !emittedPrerollReady, bufferedAudioMS() >= thresholds.startupBufferTargetMS {
                        emittedPrerollReady = true
                        startupBufferedAudioMS = bufferedAudioMS()
                        minQueuedAudioMS = startupBufferedAudioMS
                        timeToPrerollReadyMS = milliseconds(since: startedAt)
                        await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: thresholds))
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
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: thresholds))
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
                    thresholds: thresholds,
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
            stop: {},
            pause: { .idle },
            resume: { .idle },
            state: { .idle }
        )
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        try await prepareImpl(sampleRate)
    }

    func play(
        sampleRate: Double,
        text: String,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary {
        try await playImpl(sampleRate, text, stream, onEvent)
    }

    func stop() async {
        await stopImpl()
    }

    func pause() async -> PlaybackState {
        await pauseImpl()
    }

    func resume() async -> PlaybackState {
        await resumeImpl()
    }

    func state() async -> PlaybackState {
        await stateImpl()
    }
}
