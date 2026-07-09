import Foundation

// MARK: - Type-Erased Playback Driver

final class AnyPlaybackDriver: @unchecked Sendable {
    private let prepareImpl: @Sendable (_ sampleRate: Double) async throws -> Bool
    private let playImpl: @Sendable (
        _ sampleRate: Double,
        _ text: String,
        _ tuningProfile: PlaybackTuningProfile,
        _ stream: AsyncThrowingStream<[Float], Error>,
        _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void,
    ) async throws -> PlaybackSummary
    private let stopImpl: @Sendable () async -> Void
    private let pauseImpl: @Sendable () async -> PlaybackState
    private let resumeImpl: @Sendable () async -> PlaybackState
    private let stateImpl: @Sendable () async -> PlaybackState
    private let bindEnvironmentEventsImpl: @Sendable (
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?,
    ) async -> Void

    init(
        prepare: @escaping @Sendable (_ sampleRate: Double) async throws -> Bool,
        play: @escaping @Sendable (
            _ sampleRate: Double,
            _ text: String,
            _ tuningProfile: PlaybackTuningProfile,
            _ stream: AsyncThrowingStream<[Float], Error>,
            _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void,
        ) async throws -> PlaybackSummary,
        stop: @escaping @Sendable () async -> Void,
        pause: @escaping @Sendable () async -> PlaybackState,
        resume: @escaping @Sendable () async -> PlaybackState,
        state: @escaping @Sendable () async -> PlaybackState,
        bindEnvironmentEvents: @escaping @Sendable (
            _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?,
        ) async -> Void = { _ in },
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
            play: { sampleRate, text, tuningProfile, stream, onEvent in
                try await controller.play(
                    sampleRate: sampleRate,
                    text: text,
                    tuningProfile: tuningProfile,
                    stream: stream,
                    onEvent: onEvent,
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
            },
        )
    }

    static func silent(traceEnabled: Bool = false) -> AnyPlaybackDriver {
        AnyPlaybackDriver(
            prepare: { _ in true },
            play: { sampleRate, text, tuningProfile, stream, onEvent in
                let thresholds = PlaybackThresholdController(text: text, tuningProfile: tuningProfile).thresholds
                var pendingSampleCount = 0
                var accounting = PlaybackStreamAccounting(sampleRate: sampleRate)

                func bufferedAudioMS() -> Int {
                    Int((Double(pendingSampleCount) / sampleRate * 1000).rounded())
                }

                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }

                    pendingSampleCount += chunk.count
                    let queuedAudioAfterMS = bufferedAudioMS()
                    accounting.recordQueueDepth(queuedAudioMS: queuedAudioAfterMS)
                    let recordedChunk = accounting.recordGeneratedChunk(
                        samples: chunk,
                        thresholds: thresholds,
                        queuedAudioBeforeMS: nil,
                        queuedAudioAfterMS: queuedAudioAfterMS,
                        isRebuffering: false,
                        fadeInApplied: !accounting.hasReceivedFirstChunk,
                    )
                    if let warning = recordedChunk.qualityWarning {
                        await onEvent(.generationQualityWarning(warning))
                    }
                    if let firstSample = chunk.first, let lastSample = chunk.last {
                        accounting.recordBufferShape(
                            firstSample: firstSample,
                            lastSample: lastSample,
                            fadeInApplied: recordedChunk.fadeInApplied,
                        )
                    }

                    if let gapWarning = accounting.chunkGapWarning(for: recordedChunk, thresholds: thresholds) {
                        await onEvent(gapWarning)
                    }

                    if recordedChunk.emittedFirstChunk {
                        await onEvent(.firstChunk)
                    }

                    if !accounting.hasEmittedPrerollReady, queuedAudioAfterMS >= thresholds.startupBufferTargetMS {
                        let startupBufferedAudioMS = accounting.markPrerollReady(bufferedAudioMS: queuedAudioAfterMS)
                        await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS, thresholds: thresholds))
                    }

                    if traceEnabled {
                        await onEvent(.trace(accounting.generationQualityTrace(
                            for: recordedChunk,
                            queuedAudioBeforeMS: nil,
                            queuedAudioAfterMS: queuedAudioAfterMS,
                            isRebuffering: false,
                        )))
                        await onEvent(.trace(accounting.chunkReceivedTrace(
                            for: recordedChunk,
                            queuedAudioBeforeMS: nil,
                            queuedAudioAfterMS: queuedAudioAfterMS,
                            isRebuffering: false,
                        )))
                    }
                }

                if !accounting.hasEmittedPrerollReady, pendingSampleCount > 0 {
                    let startupBufferedAudioMS = accounting.markPrerollReady(bufferedAudioMS: bufferedAudioMS())
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS, thresholds: thresholds))
                }

                if let bufferShapeSummaryEvent = accounting.bufferShapeSummaryEvent {
                    await onEvent(bufferShapeSummaryEvent)
                }

                return accounting.summary(
                    thresholds: thresholds,
                    rebufferEventCount: 0,
                    rebufferTotalDurationMS: 0,
                    longestRebufferDurationMS: 0,
                    starvationEventCount: 0,
                    scheduleCallbackCount: accounting.chunkCount,
                    playedBackCallbackCount: accounting.chunkCount,
                    maxScheduleGapMS: nil,
                    avgScheduleGapMS: nil,
                )
            },
            stop: {},
            pause: { .idle },
            resume: { .idle },
            state: { .idle },
        )
    }

    func bindEnvironmentEvents(
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?,
    ) async {
        await bindEnvironmentEventsImpl(sink)
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        try await prepareImpl(sampleRate)
    }

    func play(
        sampleRate: Double,
        text: String,
        tuningProfile: PlaybackTuningProfile,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void,
    ) async throws -> PlaybackSummary {
        try await playImpl(sampleRate, text, tuningProfile, stream, onEvent)
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
