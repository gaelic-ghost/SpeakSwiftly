@preconcurrency import AppKit
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import TextForSpeech

// MARK: - AudioPlaybackDriver

@MainActor
final class AudioPlaybackDriver {
    enum PlaybackConfiguration {
        static let minimumDrainTimeout: Duration = .seconds(5)
        static let drainTimeoutPaddingMS = 3000
        static let drainProgressCheckIntervalMS = 500
        static let drainProgressStallTimeoutMS = 8000
        static let environmentInstabilityWindowMS = 8000
        static let recoveryStabilizationDelayMS = 900
        static let recoveryMaximumAttempts = 3
        static let lowQueueThresholdMS = 100
        static let channels: AVAudioChannelCount = 1
        static let interJobBoopDurationMS = 90
        static let interJobBoopFrequencyHz = 1176.0
        static let interJobBoopAmplitude: Float = 0.14
        static let interJobBoopFadeMS = 10
        static let interJobBoopTimeout: Duration = .seconds(2)

        static func drainTimeout(forQueuedAudioMS queuedAudioMS: Int) -> Duration {
            let paddedQueuedAudioMS = queuedAudioMS + drainTimeoutPaddingMS
            return max(minimumDrainTimeout, .milliseconds(paddedQueuedAudioMS))
        }
    }

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingFormat: AVAudioFormat?
    private var engineSampleRate: Double?
    private var nextRequestID: UInt64 = 0
    private let traceEnabled: Bool
    private var engineConfigurationObserver: NSObjectProtocol?
    private var workspaceObservers = [NSObjectProtocol]()
    private var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain,
    )
    private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    private var lastEnvironmentInstabilityAt: Date?
    private var recoveryTask: Task<Void, Never>?
    private var isSystemSleeping = false
    private var isScreenSleeping = false
    private var isSessionActive = true
    private var playbackRecoveryReason: AudioPlaybackRecoveryReason?
    private var playbackRecoveryAttempt = 0
    private var routingArbitration = AVAudioRoutingArbiter.shared
    private var activeRequestState: AudioPlaybackRequestState?
    private var activeEventSink: (@Sendable (PlaybackEvent) async -> Void)?
    private var activeRuntimeFailure: WorkerError?
    private var lastObservedOutputDeviceDescription: String?
    private var playbackState: PlaybackState = .idle
    private var isPlaybackPausedManually = false
    private var environmentEventSink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?
    private var shouldPlayInterJobBoop = false

    private var isPlaybackRecoveryActive: Bool {
        playbackRecoveryReason != nil || isSystemSleeping
    }

    private var shouldSuppressDrainProgressTimeout: Bool {
        if isPlaybackRecoveryActive || isScreenSleeping || !isSessionActive {
            return true
        }
        guard let lastEnvironmentInstabilityAt else { return false }

        return Date().timeIntervalSince(lastEnvironmentInstabilityAt) * 1000
            <= Double(PlaybackConfiguration.environmentInstabilityWindowMS)
    }

    init(traceEnabled: Bool = false) {
        self.traceEnabled = traceEnabled
        lastObservedOutputDeviceDescription = currentDefaultOutputDeviceDescription()
        installEngineConfigurationObserver()
        installWorkspaceObservers()
        installDefaultOutputDeviceObserver()
    }

    func setEnvironmentEventSink(
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?,
    ) {
        environmentEventSink = sink
        guard let sink else { return }

        Task {
            await sink(PlaybackEnvironmentEvent.outputDeviceObserved(currentDevice: lastObservedOutputDeviceDescription))
        }
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        let needsSetup = audioEngine == nil || playerNode == nil || engineSampleRate != sampleRate
        if needsSetup {
            try await rebuildEngine(sampleRate: sampleRate)
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
        text: String,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void,
    ) async throws -> PlaybackSummary {
        _ = try await prepare(sampleRate: sampleRate)
        try await playInterJobBoopIfNeeded(sampleRate: sampleRate)

        let startedAt = Date()
        let requestID = nextRequestID
        nextRequestID += 1
        let state = AudioPlaybackRequestState(requestID: requestID, text: text)
        activeRequestState = state
        activeEventSink = onEvent
        activeRuntimeFailure = nil
        playbackState = .idle
        defer {
            activeRequestState = nil
            activeEventSink = nil
            activeRuntimeFailure = nil
            playbackState = .idle
            isPlaybackPausedManually = false
        }
        var emittedFirstChunk = false
        var emittedPrerollReady = false
        var startedPlayback = false
        var chunkCount = 0
        var sampleCount = 0
        var startupBufferedAudioMS: Int?
        var timeToFirstChunkMS: Int?
        var timeToPrerollReadyMS: Int?
        var lastChunkReceivedAt: Date?
        var interChunkGapTotalMS = 0
        var interChunkGapCount = 0
        var maxInterChunkGapMS: Int?
        var lastScheduleAt: Date?
        var scheduleGapTotalMS = 0
        var scheduleGapCount = 0
        var maxScheduleGapMS: Int?
        var lastPreparedTrailingSample: Float?

        func bufferedAudioMS() -> Int {
            state.queuedAudioMS(sampleRate: sampleRate)
        }

        func scheduleQueuedBuffer(
            _ queuedBuffer: AudioPlaybackRequestState.QueuedBuffer,
        ) async throws {
            try throwIfActivePlaybackInterrupted()
            let queuedAudioBeforeMS = state.queuedAudioMS(sampleRate: sampleRate)
            let scheduledAt = Date()
            let scheduleGapMS: Int?
            if let lastScheduleAt {
                let gapMS = milliseconds(since: lastScheduleAt)
                scheduleGapMS = gapMS
                maxScheduleGapMS = max(maxScheduleGapMS ?? gapMS, gapMS)
                scheduleGapTotalMS += gapMS
                scheduleGapCount += 1
                if startedPlayback,
                   let bufferIndex = queuedBuffer.bufferIndex,
                   gapMS >= state.thresholdsController.thresholds.scheduleGapWarningMS {
                    await onEvent(
                        .scheduleGapWarning(
                            gapMS: gapMS,
                            bufferIndex: bufferIndex,
                            queuedAudioMS: queuedAudioBeforeMS,
                        ),
                    )
                }
            } else {
                scheduleGapMS = nil
            }
            lastScheduleAt = scheduledAt
            let currentBufferIndex = queuedBuffer.bufferIndex ?? 0
            let currentEngineGeneration = queuedBuffer.engineGeneration ?? state.engineGeneration

            let leadingAbs = Double(abs(queuedBuffer.firstSample))
            let trailingAbs = Double(abs(queuedBuffer.lastSample))
            state.maxLeadingAbsAmplitude = max(state.maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
            state.maxTrailingAbsAmplitude = max(state.maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
            if queuedBuffer.fadeInApplied {
                state.fadeInChunkCount += 1
            }
            if let lastTrailingSample = state.lastTrailingSample {
                let jump = Double(abs(queuedBuffer.firstSample - lastTrailingSample))
                state.maxBoundaryDiscontinuity = max(state.maxBoundaryDiscontinuity ?? jump, jump)
            }
            state.lastTrailingSample = queuedBuffer.lastSample

            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: sampleRate)
            let queuedAudioAfterMS = state.queuedAudioMS(sampleRate: sampleRate)
            if traceEnabled {
                await onEvent(
                    .trace(
                        PlaybackTraceEvent(
                            name: "buffer_scheduled",
                            chunkIndex: queuedBuffer.chunkIndex,
                            bufferIndex: currentBufferIndex,
                            sampleCount: queuedBuffer.frameCount,
                            durationMS: Int((Double(queuedBuffer.frameCount) / sampleRate * 1000).rounded()),
                            queuedAudioBeforeMS: queuedAudioBeforeMS,
                            queuedAudioAfterMS: queuedAudioAfterMS,
                            gapMS: scheduleGapMS,
                            isRebuffering: state.isRebuffering,
                            fadeInApplied: queuedBuffer.fadeInApplied,
                        ),
                    ),
                )
            }
            scheduleBuffer(queuedBuffer.pcmBuffer, callbackType: .dataPlayedBack) { callbackType in
                guard callbackType == .dataPlayedBack else { return }

                Task { @MainActor in
                    guard requestID + 1 == self.nextRequestID else { return }
                    guard
                        state.completeQueuedBuffer(
                            bufferIndex: currentBufferIndex,
                            engineGeneration: currentEngineGeneration,
                        ) != nil
                    else {
                        return
                    }

                    state.playedBackCallbackCount += 1
                    state.recordQueuedAudioDepth(sampleRate: sampleRate)

                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if self.traceEnabled {
                        await onEvent(
                            .trace(
                                PlaybackTraceEvent(
                                    name: "buffer_played_back",
                                    chunkIndex: queuedBuffer.chunkIndex,
                                    bufferIndex: currentBufferIndex,
                                    sampleCount: queuedBuffer.frameCount,
                                    durationMS: Int((Double(queuedBuffer.frameCount) / sampleRate * 1000).rounded()),
                                    queuedAudioBeforeMS: nil,
                                    queuedAudioAfterMS: currentQueuedAudioMS,
                                    gapMS: nil,
                                    isRebuffering: state.isRebuffering,
                                    fadeInApplied: queuedBuffer.fadeInApplied,
                                ),
                            ),
                        )
                    }
                    if !state.generationFinished, currentQueuedAudioMS <= 0 {
                        state.starvationEventCount += 1
                        state.thresholdsController.recordStarvation()
                        if !state.isRebuffering {
                            state.isRebuffering = true
                            state.rebufferEventCount += 1
                            state.thresholdsController.recordRebuffer()
                            let now = Date()
                            state.rebufferStartedAt = now
                            state.recentRebufferStartTimes.append(now)
                            state.recentRebufferStartTimes.removeAll {
                                now.timeIntervalSince($0) * 1000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                            }
                            await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                        }
                        await onEvent(.starved)
                        return
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= state.thresholdsController.thresholds.lowWaterTargetMS,
                       !state.isRebuffering {
                        state.isRebuffering = true
                        state.rebufferEventCount += 1
                        state.thresholdsController.recordRebuffer()
                        let now = Date()
                        state.rebufferStartedAt = now
                        state.recentRebufferStartTimes.append(now)
                        state.recentRebufferStartTimes.removeAll {
                            now.timeIntervalSince($0) * 1000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                        }
                        self.playerNode?.pause()
                        await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                        if !state.emittedRebufferThrashWarning,
                           state.recentRebufferStartTimes.count >= PlaybackMetricsConfiguration.rebufferThrashWarningCount {
                            state.emittedRebufferThrashWarning = true
                            await onEvent(
                                .rebufferThrashWarning(
                                    rebufferEventCount: state.rebufferEventCount,
                                    windowMS: PlaybackMetricsConfiguration.rebufferThrashWindowMS,
                                ),
                            )
                        }
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= PlaybackConfiguration.lowQueueThresholdMS,
                       !state.emittedLowQueueWarning {
                        state.emittedLowQueueWarning = true
                        await onEvent(.queueDepthLow(queuedAudioMS: currentQueuedAudioMS))
                    } else if currentQueuedAudioMS > PlaybackConfiguration.lowQueueThresholdMS {
                        state.emittedLowQueueWarning = false
                    }

                    if state.isRebuffering,
                       currentQueuedAudioMS >= state.thresholdsController.thresholds.resumeBufferTargetMS || state.generationFinished {
                        if !self.isPlaybackPausedManually {
                            self.playerNode?.play()
                        }
                        state.isRebuffering = false
                        if let rebufferStartedAt = state.rebufferStartedAt {
                            let durationMS = milliseconds(since: rebufferStartedAt)
                            state.rebufferTotalDurationMS += durationMS
                            state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                            state.rebufferStartedAt = nil
                        }
                        await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                    }

                    if state.generationFinished, currentQueuedAudioMS == 0 {
                        state.drainContinuation?.resume()
                        state.drainContinuation = nil
                    }
                }
            }
        }

        func scheduleQueuedBuffersIfPossible() async throws {
            guard !isPlaybackRecoveryActive else { return }

            let queuedBuffers = state.reserveQueuedBufferIndicesForCurrentGeneration()
            for queuedBuffer in queuedBuffers {
                try throwIfActivePlaybackInterrupted()
                try await scheduleQueuedBuffer(queuedBuffer)
            }
        }

        do {
            for try await chunk in stream {
                try throwIfActivePlaybackInterrupted()
                guard !chunk.isEmpty else { continue }

                let now = Date()
                let chunkDurationMS = Int((Double(chunk.count) / sampleRate * 1000).rounded())
                let interChunkGapMS: Int?
                chunkCount += 1
                sampleCount += chunk.count
                if let lastChunkReceivedAt {
                    let gapMS = milliseconds(since: lastChunkReceivedAt)
                    interChunkGapMS = gapMS
                    maxInterChunkGapMS = max(maxInterChunkGapMS ?? gapMS, gapMS)
                    interChunkGapTotalMS += gapMS
                    interChunkGapCount += 1
                    state.thresholdsController.recordChunk(durationMS: chunkDurationMS, interChunkGapMS: gapMS)
                    if startedPlayback, gapMS >= state.thresholdsController.thresholds.chunkGapWarningMS {
                        await onEvent(.chunkGapWarning(gapMS: gapMS, chunkIndex: chunkCount))
                    }
                } else {
                    interChunkGapMS = nil
                    state.thresholdsController.recordChunk(durationMS: chunkDurationMS, interChunkGapMS: nil)
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
                                durationMS: chunkDurationMS,
                                queuedAudioBeforeMS: bufferedAudioMS(),
                                queuedAudioAfterMS: nil,
                                gapMS: interChunkGapMS,
                                isRebuffering: state.isRebuffering,
                                fadeInApplied: !emittedFirstChunk,
                            ),
                        ),
                    )
                }
                if let buffer = makePCMBuffer(
                    from: chunk,
                    sampleRate: sampleRate,
                    previousTrailingSample: lastPreparedTrailingSample,
                    applyFadeIn: !emittedFirstChunk,
                ) {
                    lastPreparedTrailingSample = buffer.lastSample
                    state.enqueueBuffer(
                        buffer.buffer,
                        frameCount: buffer.frameCount,
                        firstSample: buffer.firstSample,
                        lastSample: buffer.lastSample,
                        fadeInApplied: buffer.fadeInApplied,
                        chunkIndex: chunkCount,
                    )
                    if startedPlayback {
                        try await scheduleQueuedBuffersIfPossible()
                        if state.isRebuffering {
                            let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                            if currentQueuedAudioMS >= state.thresholdsController.thresholds.resumeBufferTargetMS {
                                if !isPlaybackPausedManually, !isPlaybackRecoveryActive {
                                    playerNode?.play()
                                }
                                state.isRebuffering = false
                                if let rebufferStartedAt = state.rebufferStartedAt {
                                    let durationMS = milliseconds(since: rebufferStartedAt)
                                    state.rebufferTotalDurationMS += durationMS
                                    state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                                    state.rebufferStartedAt = nil
                                }
                                await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                            }
                        }
                    }
                }

                if !emittedFirstChunk {
                    emittedFirstChunk = true
                    timeToFirstChunkMS = milliseconds(since: startedAt)
                    await onEvent(.firstChunk)
                }

                if !startedPlayback, bufferedAudioMS() >= state.thresholdsController.thresholds.startupBufferTargetMS {
                    startupBufferedAudioMS = bufferedAudioMS()
                    startedPlayback = true
                    emittedPrerollReady = true
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    if !isPlaybackPausedManually {
                        playbackState = .playing
                    }
                    try await scheduleQueuedBuffersIfPossible()
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: state.thresholdsController.thresholds))
                }
            }

            state.generationFinished = true
            if startedPlayback, state.isRebuffering {
                let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                if !isPlaybackPausedManually {
                    playerNode?.play()
                }
                state.isRebuffering = false
                if let rebufferStartedAt = state.rebufferStartedAt {
                    let durationMS = milliseconds(since: rebufferStartedAt)
                    state.rebufferTotalDurationMS += durationMS
                    state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                    state.rebufferStartedAt = nil
                }
                await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
            }
            if !startedPlayback, !state.queuedBuffers.isEmpty {
                startupBufferedAudioMS = bufferedAudioMS()
                startedPlayback = true
                try await scheduleQueuedBuffersIfPossible()
                if state.isRebuffering {
                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if !isPlaybackPausedManually, !isPlaybackRecoveryActive {
                        playerNode?.play()
                    }
                    state.isRebuffering = false
                    if let rebufferStartedAt = state.rebufferStartedAt {
                        let durationMS = milliseconds(since: rebufferStartedAt)
                        state.rebufferTotalDurationMS += durationMS
                        state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                        state.rebufferStartedAt = nil
                    }
                    await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                }
                if !isPlaybackPausedManually {
                    playbackState = .playing
                }
            }

            if !emittedPrerollReady, chunkCount > 0 {
                emittedPrerollReady = true
                startupBufferedAudioMS = startupBufferedAudioMS ?? state.queuedAudioMS(sampleRate: sampleRate)
                timeToPrerollReadyMS = milliseconds(since: startedAt)
                await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: state.thresholdsController.thresholds))
            }

            try throwIfActivePlaybackInterrupted()
            try await waitForPlaybackDrain(
                state: state,
                sampleRate: sampleRate,
            )
            if let maxBoundaryDiscontinuity = state.maxBoundaryDiscontinuity,
               let maxLeadingAbsAmplitude = state.maxLeadingAbsAmplitude,
               let maxTrailingAbsAmplitude = state.maxTrailingAbsAmplitude {
                await onEvent(
                    .bufferShapeSummary(
                        maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                        maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                        maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                        fadeInChunkCount: state.fadeInChunkCount,
                    ),
                )
            }
            let timeFromPrerollReadyToDrainMS: Int? = if let timeToPrerollReadyMS {
                max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
            } else {
                nil
            }

            resetPlayerNodeForNextRequest()
            shouldPlayInterJobBoop = true

            return PlaybackSummary(
                thresholds: state.thresholdsController.thresholds,
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
                starvationEventCount: state.starvationEventCount,
                scheduleCallbackCount: state.scheduleCallbackCount,
                playedBackCallbackCount: state.playedBackCallbackCount,
                maxInterChunkGapMS: maxInterChunkGapMS,
                avgInterChunkGapMS: interChunkGapCount == 0 ? nil : interChunkGapTotalMS / interChunkGapCount,
                maxScheduleGapMS: maxScheduleGapMS,
                avgScheduleGapMS: scheduleGapCount == 0 ? nil : scheduleGapTotalMS / scheduleGapCount,
                maxBoundaryDiscontinuity: state.maxBoundaryDiscontinuity,
                maxLeadingAbsAmplitude: state.maxLeadingAbsAmplitude,
                maxTrailingAbsAmplitude: state.maxTrailingAbsAmplitude,
                fadeInChunkCount: state.fadeInChunkCount,
            )
        } catch is CancellationError {
            resetPlayerNodeForNextRequest()
            shouldPlayInterJobBoop = false
            throw CancellationError()
        } catch {
            resetPlayerNodeForNextRequest()
            shouldPlayInterJobBoop = false
            if let workerError = error as? WorkerError {
                throw workerError
            }

            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback failed while scheduling generated audio into the local audio player. \(error.localizedDescription)",
            )
        }
    }

    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        tearDownPlaybackHardware(leavingArbitration: true)
        playbackRecoveryReason = nil
        playbackRecoveryAttempt = 0
        lastEnvironmentInstabilityAt = nil
        playbackState = .idle
        isPlaybackPausedManually = false
        shouldPlayInterJobBoop = false
        routingArbitration.leave()
    }

    func pause() -> PlaybackState {
        guard activeRequestState != nil else {
            playbackState = .idle
            return playbackState
        }

        playerNode?.pause()
        isPlaybackPausedManually = true
        playbackState = .paused
        return playbackState
    }

    func resume() -> PlaybackState {
        guard let activeRequestState else {
            playbackState = .idle
            return playbackState
        }

        isPlaybackPausedManually = false
        let queuedAudioMS = activeRequestState.queuedAudioMS(sampleRate: engineSampleRate ?? 24000)
        if !activeRequestState.isRebuffering
            || queuedAudioMS >= activeRequestState.thresholdsController.thresholds.resumeBufferTargetMS
            || activeRequestState.generationFinished {
            playerNode?.play()
        }
        playbackState = .playing
        return playbackState
    }

    func state() -> PlaybackState {
        playbackState
    }

    // MARK: - Drain Handling

    private func waitForPlaybackDrain(
        state: AudioPlaybackRequestState,
        sampleRate: Double,
    ) async throws {
        let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
        if currentQueuedAudioMS == 0 {
            return
        }
        let drainTimeout = PlaybackConfiguration.drainTimeout(forQueuedAudioMS: currentQueuedAudioMS)

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
                try await Task.sleep(for: drainTimeout)
                throw WorkerError(
                    code: .audioPlaybackTimeout,
                    message: "Live playback timed out after generated audio finished because the local audio player did not report drain completion within \(drainTimeout.components.seconds) seconds.",
                )
            }
            group.addTask {
                var lastPlayedBackCallbackCount = await MainActor.run {
                    state.playedBackCallbackCount
                }
                var lastProgressAt = Date()

                while true {
                    try await Task.sleep(for: .milliseconds(PlaybackConfiguration.drainProgressCheckIntervalMS))
                    let snapshot = await MainActor.run {
                        (
                            playedBackCallbackCount: state.playedBackCallbackCount,
                            queuedAudioMS: state.queuedAudioMS(sampleRate: sampleRate),
                            isPausedManually: self.isPlaybackPausedManually,
                        )
                    }

                    if snapshot.queuedAudioMS == 0 {
                        return
                    }
                    if await MainActor.run(body: { self.shouldSuppressDrainProgressTimeout }) {
                        lastProgressAt = Date()
                        continue
                    }
                    if snapshot.isPausedManually {
                        lastProgressAt = Date()
                        continue
                    }
                    if snapshot.playedBackCallbackCount != lastPlayedBackCallbackCount {
                        lastPlayedBackCallbackCount = snapshot.playedBackCallbackCount
                        lastProgressAt = Date()
                        continue
                    }

                    let stalledForMS = Int((Date().timeIntervalSince(lastProgressAt) * 1000).rounded())
                    if stalledForMS >= PlaybackConfiguration.drainProgressStallTimeoutMS {
                        throw WorkerError(
                            code: .audioPlaybackTimeout,
                            message: "Live playback stalled after generated audio finished because the local audio player stopped reporting drain progress for \(PlaybackConfiguration.drainProgressStallTimeoutMS / 1000) seconds while \(snapshot.queuedAudioMS) ms of audio remained queued.",
                        )
                    }
                }
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Engine Management

    private func rebuildEngine(sampleRate: Double) async throws {
        tearDownPlaybackHardware(leavingArbitration: true)
        try await beginRoutingArbitration()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels,
        )

        guard let format else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback could not create an AVAudioFormat for sample rate \(sampleRate).",
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
    }

    private func tearDownPlaybackHardware(leavingArbitration: Bool) {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        streamingFormat = nil
        engineSampleRate = nil
        if leavingArbitration {
            routingArbitration.leave()
        }
    }

    private func beginRoutingArbitration() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routingArbitration.begin(category: .playback) { _, error in
                if let error {
                    continuation.resume(
                        throwing: WorkerError(
                            code: .audioPlaybackFailed,
                            message: "SpeakSwiftly could not begin macOS audio routing arbitration before starting local playback. \(error.localizedDescription)",
                        ),
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // MARK: - System Observers

    private func installEngineConfigurationObserver() {
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let engine = audioEngine else { return }

                let engineIsRunning = engine.isRunning
                markEnvironmentInstability()
                if let environmentEventSink {
                    await environmentEventSink(.engineConfigurationChanged(engineIsRunning: engineIsRunning))
                }
                if let activeEventSink {
                    await activeEventSink(.engineConfigurationChanged(engineIsRunning: engineIsRunning))
                }
                beginPlaybackRecovery(reason: .engineConfigurationChange)
            }
        }
    }

    private func installWorkspaceObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemSleepStateChange(isSleeping: true)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemSleepStateChange(isSleeping: false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenSleepStateChange(isSleeping: true)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenSleepStateChange(isSleeping: false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSessionActivityChange(isActive: false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSessionActivityChange(isActive: true)
                }
            },
        )
    }

    private func installDefaultOutputDeviceObserver() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDefaultOutputDeviceChange()
            }
        }
        defaultOutputDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputDeviceAddress,
            DispatchQueue.main,
            listener,
        )
    }

    private func handleDefaultOutputDeviceChange() {
        let previousDevice = lastObservedOutputDeviceDescription
        let currentDevice = currentDefaultOutputDeviceDescription()
        guard previousDevice != currentDevice else { return }

        lastObservedOutputDeviceDescription = currentDevice
        markEnvironmentInstability()

        if let environmentEventSink {
            Task {
                await environmentEventSink(
                    .outputDeviceChanged(previousDevice: previousDevice, currentDevice: currentDevice),
                )
            }
        }

        if let activeEventSink {
            Task {
                await activeEventSink(
                    .outputDeviceChanged(previousDevice: previousDevice, currentDevice: currentDevice),
                )
            }
        }

        beginPlaybackRecovery(reason: .outputDeviceChange)
    }

    private func handleSystemSleepStateChange(isSleeping: Bool) {
        isSystemSleeping = isSleeping
        markEnvironmentInstability()
        emitEnvironmentEvent(.systemSleepStateChanged(isSleeping: isSleeping))

        guard activeRequestState != nil else { return }

        if isSleeping {
            playerNode?.pause()
            return
        }

        beginPlaybackRecovery(reason: .systemWake)
    }

    private func handleScreenSleepStateChange(isSleeping: Bool) {
        isScreenSleeping = isSleeping
        markEnvironmentInstability()
        emitEnvironmentEvent(.screenSleepStateChanged(isSleeping: isSleeping))
    }

    private func handleSessionActivityChange(isActive: Bool) {
        isSessionActive = isActive
        markEnvironmentInstability()
        emitEnvironmentEvent(.sessionActivityChanged(isActive: isActive))
    }

    private func emitEnvironmentEvent(_ event: PlaybackEnvironmentEvent) {
        guard let environmentEventSink else { return }

        Task {
            await environmentEventSink(event)
        }
    }

    private func markEnvironmentInstability() {
        lastEnvironmentInstabilityAt = Date()
    }

    private func beginPlaybackRecovery(reason: AudioPlaybackRecoveryReason) {
        guard let activeRequestState else { return }
        guard activeRuntimeFailure == nil else { return }
        guard !isSystemSleeping || reason == .systemWake else { return }

        recoveryTask?.cancel()
        playbackRecoveryReason = reason
        playbackRecoveryAttempt = 0
        activeRequestState.markQueuedBuffersForReschedule()
        playerNode?.pause()
        emitEnvironmentEvent(
            .recoveryStateChanged(
                reason: reason.rawValue,
                stage: "scheduled",
                attempt: nil,
                currentDevice: lastObservedOutputDeviceDescription,
            ),
        )

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await performPlaybackRecovery(reason: reason)
        }
    }

    private func performPlaybackRecovery(reason: AudioPlaybackRecoveryReason) async {
        guard let activeRequestState else {
            playbackRecoveryReason = nil
            return
        }
        guard let sampleRate = engineSampleRate else {
            interruptActivePlayback(
                with: WorkerError(
                    code: .audioPlaybackFailed,
                    message: "SpeakSwiftly could not recover local playback after a \(reason.rawValue) event because the active playback sample rate was no longer available.",
                ),
            )
            return
        }

        while playbackRecoveryAttempt < PlaybackConfiguration.recoveryMaximumAttempts {
            playbackRecoveryAttempt += 1
            let attempt = playbackRecoveryAttempt
            emitEnvironmentEvent(
                .recoveryStateChanged(
                    reason: reason.rawValue,
                    stage: "attempting",
                    attempt: attempt,
                    currentDevice: lastObservedOutputDeviceDescription,
                ),
            )

            do {
                try await Task.sleep(for: .milliseconds(PlaybackConfiguration.recoveryStabilizationDelayMS))
                try Task.checkCancellation()
                try await rebuildEngine(sampleRate: sampleRate)
                activeRequestState.markQueuedBuffersForReschedule()
                try await rescheduleActiveRequestBuffers(activeRequestState)
                if !isPlaybackPausedManually,
                   !activeRequestState.isRebuffering,
                   !isSystemSleeping {
                    playerNode?.play()
                }
                playbackRecoveryReason = nil
                playbackRecoveryAttempt = 0
                emitEnvironmentEvent(
                    .recoveryStateChanged(
                        reason: reason.rawValue,
                        stage: "recovered",
                        attempt: attempt,
                        currentDevice: lastObservedOutputDeviceDescription,
                    ),
                )
                return
            } catch is CancellationError {
                return
            } catch {
                markEnvironmentInstability()
                emitEnvironmentEvent(
                    .recoveryStateChanged(
                        reason: reason.rawValue,
                        stage: "attempt_failed",
                        attempt: attempt,
                        currentDevice: lastObservedOutputDeviceDescription,
                    ),
                )
            }
        }

        interruptActivePlayback(
            with: WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback could not recover after macOS reported a \(reason.rawValue) event. SpeakSwiftly attempted to rebuild the audio engine \(PlaybackConfiguration.recoveryMaximumAttempts) times, but the output route never stabilized enough to resume the active request.",
            ),
        )
    }

    private func rescheduleActiveRequestBuffers(_ state: AudioPlaybackRequestState) async throws {
        let queuedBuffers = state.reserveQueuedBufferIndicesForCurrentGeneration()
        for queuedBuffer in queuedBuffers {
            try throwIfActivePlaybackInterrupted()
            scheduleBuffer(queuedBuffer.pcmBuffer, callbackType: .dataPlayedBack) { [weak self] callbackType in
                guard callbackType == .dataPlayedBack else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard state.completeQueuedBuffer(
                        bufferIndex: queuedBuffer.bufferIndex ?? 0,
                        engineGeneration: queuedBuffer.engineGeneration ?? state.engineGeneration,
                    ) != nil else {
                        return
                    }

                    state.playedBackCallbackCount += 1
                    state.recordQueuedAudioDepth(sampleRate: engineSampleRate ?? 24000)
                    if state.generationFinished, state.queuedSampleCount == 0 {
                        state.drainContinuation?.resume()
                        state.drainContinuation = nil
                    }
                }
            }
            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: engineSampleRate ?? 24000)
        }
    }

    // MARK: - Interruption Handling

    private func interruptActivePlayback(with error: WorkerError) {
        guard activeRequestState != nil else { return }
        guard activeRuntimeFailure == nil else { return }

        activeRuntimeFailure = error
        shouldPlayInterJobBoop = false
        stop()
        activeRequestState?.drainContinuation?.resume(throwing: error)
        activeRequestState?.drainContinuation = nil
    }

    private func throwIfActivePlaybackInterrupted() throws {
        if let activeRuntimeFailure {
            throw activeRuntimeFailure
        }
    }

    // MARK: - Device Inspection

    private func currentDefaultOutputDeviceDescription() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &dataSize,
            &deviceID,
        )

        guard deviceStatus == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.stride)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let nameStatus = withUnsafeMutablePointer(to: &deviceName) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                UnsafeMutableRawPointer(pointer),
            )
        }

        if nameStatus == noErr {
            let name = "\(deviceName)"
            if !name.isEmpty {
                return "\(name) [\(deviceID)]"
            }
        }

        return "AudioObjectID \(deviceID)"
    }

    // MARK: - Buffer Preparation

    private func makePCMBuffer(
        from samples: [Float],
        sampleRate: Double,
        previousTrailingSample: Float?,
        applyFadeIn: Bool,
    ) -> (buffer: AVAudioPCMBuffer, frameCount: Int, firstSample: Float, lastSample: Float, fadeInApplied: Bool)? {
        guard let format = streamingFormat ?? AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels,
        ) else {
            return nil
        }

        let processedSamples = shapePlaybackSamples(
            samples,
            sampleRate: format.sampleRate,
            previousTrailingSample: previousTrailingSample,
            applyFadeIn: applyFadeIn,
        )
        guard let firstSample = processedSamples.first, let lastSample = processedSamples.last else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(processedSamples.count),
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(processedSamples.count)
        if let channelData = buffer.floatChannelData {
            processedSamples.withUnsafeBufferPointer { src in
                guard let baseAddress = src.baseAddress else {
                    return
                }

                channelData[0].update(from: baseAddress, count: processedSamples.count)
            }
        }

        return (
            buffer: buffer,
            frameCount: Int(buffer.frameLength),
            firstSample: firstSample,
            lastSample: lastSample,
            fadeInApplied: applyFadeIn,
        )
    }

    private func scheduleBuffer(
        _ buffer: AVAudioPCMBuffer,
        callbackType: AVAudioPlayerNodeCompletionCallbackType,
        completion: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void,
    ) {
        playerNode?.scheduleBuffer(
            buffer,
            completionCallbackType: callbackType,
            completionHandler: completion,
        )
    }

    // MARK: - Inter-Job Boop

    private func playInterJobBoopIfNeeded(sampleRate: Double) async throws {
        guard shouldPlayInterJobBoop else { return }

        shouldPlayInterJobBoop = false

        guard
            let buffer = makePCMBuffer(
                from: makeInterJobBoopSamples(sampleRate: sampleRate),
                sampleRate: sampleRate,
                previousTrailingSample: nil,
                applyFadeIn: false,
            )?.buffer
        else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "SpeakSwiftly could not synthesize the short inter-job playback boop buffer for sample rate \(sampleRate).",
            )
        }

        if playerNode?.isPlaying == false {
            playerNode?.play()
        }

        let playbackTask = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                scheduleBuffer(buffer, callbackType: .dataPlayedBack) { callbackType in
                    guard callbackType == .dataPlayedBack else { return }

                    continuation.resume()
                }
            }
        }
        defer { playbackTask.cancel() }

        let timeoutTask = Task {
            try await Task.sleep(for: PlaybackConfiguration.interJobBoopTimeout)
            throw WorkerError(
                code: .audioPlaybackTimeout,
                message: "SpeakSwiftly timed out while trying to play the short inter-job playback boop before the next live request could begin.",
            )
        }
        defer { timeoutTask.cancel() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await playbackTask.value }
            group.addTask { try await timeoutTask.value }

            _ = try await group.next()
            group.cancelAll()
        }

        if let environmentEventSink {
            await environmentEventSink(
                .interJobBoopPlayed(
                    durationMS: PlaybackConfiguration.interJobBoopDurationMS,
                    frequencyHz: PlaybackConfiguration.interJobBoopFrequencyHz,
                    sampleRate: sampleRate,
                ),
            )
        }
    }
}
