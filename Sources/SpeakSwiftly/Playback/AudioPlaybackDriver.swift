@preconcurrency import AVFoundation
import Foundation
import TextForSpeech

// MARK: - AudioPlaybackDriver

@MainActor
final class AudioPlaybackDriver {
    var audioEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    var streamingFormat: AVAudioFormat?
    var engineSampleRate: Double?
    var engineConfigurationObserver: NSObjectProtocol?
    var lastEnvironmentInstabilityAt: Date?
    var recoveryTask: Task<Void, Never>?
    var isSystemSleeping = false
    var isScreenSleeping = false
    var isSessionActive = true
    var playbackRecoveryReason: AudioPlaybackRecoveryReason?
    var playbackRecoveryAttempt = 0
    var activeRequestState: AudioPlaybackRequestState?
    var activeEventSink: (@Sendable (PlaybackEvent) async -> Void)?
    var activeRuntimeFailure: WorkerError?
    var lastObservedOutputDeviceDescription: String?
    var isPlaybackPausedManually = false
    var environmentEventSink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?
    var shouldPlayInterJobBoop = false

    let playbackEnvironment: PlaybackEnvironmentCoordinator

    private var nextRequestID: UInt64 = 0
    private let traceEnabled: Bool
    private var playbackState: PlaybackState = .idle

    var shouldSuppressDrainProgressTimeout: Bool {
        if isPlaybackRecoveryActive || isScreenSleeping || !isSessionActive {
            return true
        }
        guard let lastEnvironmentInstabilityAt else { return false }

        return Date().timeIntervalSince(lastEnvironmentInstabilityAt) * 1000
            <= Double(AudioPlaybackConfiguration.environmentInstabilityWindowMS)
    }

    private var isPlaybackRecoveryActive: Bool {
        playbackRecoveryReason != nil || isSystemSleeping
    }

    init(
        traceEnabled: Bool = false,
        playbackEnvironment: PlaybackEnvironmentCoordinator? = nil,
    ) {
        self.traceEnabled = traceEnabled
        let playbackEnvironment = playbackEnvironment ?? makeDefaultPlaybackEnvironmentCoordinator()
        self.playbackEnvironment = playbackEnvironment
        lastObservedOutputDeviceDescription = playbackEnvironment.currentOutputDeviceDescription
        installEngineConfigurationObserver()
        playbackEnvironment.installObservers(
            onSystemSleepStateChange: { [weak self] isSleeping in
                self?.handleSystemSleepStateChange(isSleeping: isSleeping)
            },
            onScreenSleepStateChange: { [weak self] isSleeping in
                self?.handleScreenSleepStateChange(isSleeping: isSleeping)
            },
            onSessionActivityChange: { [weak self] isActive in
                self?.handleSessionActivityChange(isActive: isActive)
            },
            onOutputDeviceChange: { [weak self] currentDevice in
                self?.handleObservedOutputDeviceChange(currentDevice: currentDevice)
            },
            onInterruptionStateChange: { [weak self] isInterrupted, shouldResume in
                self?.handleInterruptionStateChange(
                    isInterrupted: isInterrupted,
                    shouldResume: shouldResume,
                )
            },
        )
    }

    deinit {
        let playbackEnvironment = playbackEnvironment
        Task { @MainActor in
            playbackEnvironment.invalidate()
        }
    }

    func setEnvironmentEventSink(
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?,
    ) {
        environmentEventSink = sink
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        let needsSetup = audioEngine == nil || playerNode == nil || engineSampleRate != sampleRate
        if needsSetup {
            try await rebuildEngine(sampleRate: sampleRate)
            if let environmentEventSink {
                await environmentEventSink(
                    PlaybackEnvironmentEvent.outputDeviceObserved(
                        currentDevice: lastObservedOutputDeviceDescription,
                    ),
                )
            }
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
        tuningProfile: PlaybackTuningProfile,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void,
    ) async throws -> PlaybackSummary {
        _ = try await prepare(sampleRate: sampleRate)
        try await playInterJobBoopIfNeeded(sampleRate: sampleRate)

        let startedAt = Date()
        let requestID = nextRequestID
        nextRequestID += 1
        let state = AudioPlaybackRequestState(requestID: requestID, text: text, tuningProfile: tuningProfile)
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
                    if !state.isRebuffering {
                        state.thresholdsController.recordScheduleGapDistress(
                            gapMS: gapMS,
                            queuedAudioMS: queuedAudioBeforeMS,
                        )
                    }
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
                       currentQueuedAudioMS <= AudioPlaybackConfiguration.lowQueueThresholdMS,
                       !state.emittedLowQueueWarning {
                        state.emittedLowQueueWarning = true
                        await onEvent(.queueDepthLow(queuedAudioMS: currentQueuedAudioMS))
                    } else if currentQueuedAudioMS > AudioPlaybackConfiguration.lowQueueThresholdMS {
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
                        state.resumeDrainContinuation()
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
        tearDownPlaybackHardware(leavingPlaybackEnvironment: true)
        playbackRecoveryReason = nil
        playbackRecoveryAttempt = 0
        lastEnvironmentInstabilityAt = nil
        playbackState = .idle
        isPlaybackPausedManually = false
        shouldPlayInterJobBoop = false
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
}
