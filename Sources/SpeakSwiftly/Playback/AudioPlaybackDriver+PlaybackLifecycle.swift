@preconcurrency import AVFoundation
import Foundation
import TextForSpeech

// MARK: - Playback Lifecycle

extension AudioPlaybackDriver {
    func waitForPlaybackDrain(
        state: AudioPlaybackRequestState,
        sampleRate: Double,
    ) async throws {
        let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
        if currentQueuedAudioMS == 0 {
            return
        }
        let drainTimeout = AudioPlaybackConfiguration.drainTimeout(forQueuedAudioMS: currentQueuedAudioMS)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitPlaybackDrainSignal(
                    state: state,
                    sampleRate: sampleRate,
                )
            }
            group.addTask {
                try await playbackDelay(for: drainTimeout)
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
                    try await playbackDelay(for: .milliseconds(AudioPlaybackConfiguration.drainProgressCheckIntervalMS))
                    let snapshot = await MainActor.run {
                        (
                            playedBackCallbackCount: state.playedBackCallbackCount,
                            queuedAudioMS: state.queuedAudioMS(sampleRate: sampleRate),
                            queuedBufferCount: state.queuedBuffers.count,
                            generationFinished: state.generationFinished,
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
                    if snapshot.generationFinished, snapshot.queuedBufferCount <= 1 {
                        lastProgressAt = Date()
                        continue
                    }

                    let stalledForMS = Int((Date().timeIntervalSince(lastProgressAt) * 1000).rounded())
                    if stalledForMS >= AudioPlaybackConfiguration.drainProgressStallTimeoutMS {
                        throw WorkerError(
                            code: .audioPlaybackTimeout,
                            message: "Live playback stalled after generated audio finished because the local audio player stopped reporting drain progress for \(AudioPlaybackConfiguration.drainProgressStallTimeoutMS / 1000) seconds while \(snapshot.queuedAudioMS) ms of audio remained queued.",
                        )
                    }
                }
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    func awaitPlaybackDrainSignal(
        state: AudioPlaybackRequestState,
        sampleRate: Double,
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.installDrainContinuation(
                    continuation,
                    sampleRate: sampleRate,
                )
            }
        } onCancel: {
            Task { @MainActor in
                state.resumeDrainContinuation(throwing: CancellationError())
            }
        }
    }

    func rebuildEngine(sampleRate: Double) async throws {
        tearDownPlaybackHardware(leavingPlaybackEnvironment: true)
        try await playbackEnvironment.prepareForPlaybackStart()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AudioPlaybackConfiguration.channels,
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

    func resetPlayerNodeForNextRequest() {
        playerNode?.stop()
        playerNode?.reset()
    }

    func tearDownPlaybackHardware(leavingPlaybackEnvironment: Bool) {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        streamingFormat = nil
        engineSampleRate = nil
        if leavingPlaybackEnvironment {
            playbackEnvironment.finishPlayback()
        }
    }

    func interruptActivePlayback(with error: WorkerError) {
        guard activeRequestState != nil else { return }
        guard activeRuntimeFailure == nil else { return }

        activeRuntimeFailure = error
        shouldPlayInterJobBoop = false
        stop()
        activeRequestState?.resumeDrainContinuation(throwing: error)
    }

    func throwIfActivePlaybackInterrupted() throws {
        if let activeRuntimeFailure {
            throw activeRuntimeFailure
        }
    }

    func makePCMBuffer(
        from samples: [Float],
        sampleRate: Double,
        previousTrailingSample: Float?,
        applyFadeIn: Bool,
    ) -> (buffer: AVAudioPCMBuffer, frameCount: Int, firstSample: Float, lastSample: Float, fadeInApplied: Bool)? {
        guard let format = streamingFormat ?? AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AudioPlaybackConfiguration.channels,
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

    func scheduleBuffer(
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

    func playInterJobBoopIfNeeded(sampleRate: Double) async throws {
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
            try await playbackDelay(for: AudioPlaybackConfiguration.interJobBoopTimeout)
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
                    durationMS: AudioPlaybackConfiguration.interJobBoopDurationMS,
                    frequencyHz: AudioPlaybackConfiguration.interJobBoopFrequencyHz,
                    sampleRate: sampleRate,
                ),
            )
        }
    }
}
