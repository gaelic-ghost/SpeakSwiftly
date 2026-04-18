@preconcurrency import AVFoundation
import Foundation
import TextForSpeech

// MARK: - Environment Recovery

extension AudioPlaybackDriver {
    func installEngineConfigurationObserver() {
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

    func handleObservedOutputDeviceChange(currentDevice: String?) {
        let previousDevice = lastObservedOutputDeviceDescription
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

    func handleSystemSleepStateChange(isSleeping: Bool) {
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

    func handleScreenSleepStateChange(isSleeping: Bool) {
        isScreenSleeping = isSleeping
        markEnvironmentInstability()
        emitEnvironmentEvent(.screenSleepStateChanged(isSleeping: isSleeping))
    }

    func handleSessionActivityChange(isActive: Bool) {
        isSessionActive = isActive
        markEnvironmentInstability()
        emitEnvironmentEvent(.sessionActivityChanged(isActive: isActive))
    }

    func handleInterruptionStateChange(isInterrupted: Bool, shouldResume: Bool?) {
        markEnvironmentInstability()
        emitEnvironmentEvent(
            .interruptionStateChanged(
                isInterrupted: isInterrupted,
                shouldResume: shouldResume,
            ),
        )

        guard activeRequestState != nil else { return }

        if isInterrupted {
            playerNode?.pause()
            return
        }

        guard shouldResume != false else { return }

        beginPlaybackRecovery(reason: .audioSessionInterruption)
    }

    func emitEnvironmentEvent(_ event: PlaybackEnvironmentEvent) {
        guard let environmentEventSink else { return }

        Task {
            await environmentEventSink(event)
        }
    }

    func markEnvironmentInstability() {
        lastEnvironmentInstabilityAt = Date()
    }

    func beginPlaybackRecovery(reason: AudioPlaybackRecoveryReason) {
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

    func performPlaybackRecovery(reason: AudioPlaybackRecoveryReason) async {
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

        while playbackRecoveryAttempt < AudioPlaybackConfiguration.recoveryMaximumAttempts {
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
                try await Task.sleep(for: .milliseconds(AudioPlaybackConfiguration.recoveryStabilizationDelayMS))
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
                message: "Live playback could not recover after the playback environment reported a \(reason.rawValue) event. SpeakSwiftly attempted to rebuild the audio engine \(AudioPlaybackConfiguration.recoveryMaximumAttempts) times, but the active route never stabilized enough to resume the request.",
            ),
        )
    }

    func rescheduleActiveRequestBuffers(_ state: AudioPlaybackRequestState) async throws {
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
                        state.resumeDrainContinuation()
                    }
                }
            }
            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: engineSampleRate ?? 24000)
        }
    }
}
