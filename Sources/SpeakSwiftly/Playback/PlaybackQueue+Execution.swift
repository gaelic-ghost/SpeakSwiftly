extension PlaybackQueue {
    func startNextIfPossible() async {
        guard activePlayback == nil else { return }
        guard let requestID = queue.first, let playbackState = jobs[requestID] else { return }
        guard let sampleRate = playbackState.execution.sampleRate else { return }
        guard let hooks else { return }

        let task = Task {
            await self.runPlayback(for: playbackState, sampleRate: sampleRate, hooks: hooks)
        }
        activePlayback = ActivePlayback(requestID: requestID, task: task)
        activePlaybackIsStableForConcurrentGeneration = false
        activePlaybackStableBufferedAudioMS = nil
        activePlaybackStableBufferTargetMS = nil
        activePlaybackConcurrentGenerationTargetMS = nil
        activePlaybackFragileOverlapWindowProgress = nil
        activePlaybackIsRebuffering = false
        playbackState.execution.playbackTask = task
    }

    private func runPlayback(
        for playbackState: LiveSpeechPlaybackState,
        sampleRate: Double,
        hooks: PlaybackHooks,
    ) async {
        let result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>

        do {
            let playbackEngineWasPrepared = try await driver.prepare(sampleRate: sampleRate)
            if playbackEngineWasPrepared {
                await hooks.logEngineReady(playbackState.request, sampleRate)
            }
            let playbackSummary = try await driver.play(
                sampleRate: sampleRate,
                text: playbackState.request.normalizedText,
                tuningProfile: playbackState.request.playbackTuningProfile,
                stream: playbackState.execution.stream,
            ) { event in
                await self.recordConcurrencyEvent(event, for: playbackState.id)
                await hooks.handleEvent(event, playbackState.request)
            }
            await hooks.logFinished(playbackState.request, playbackSummary, sampleRate)
            result = .success(SpeakSwiftly.Runtime.WorkerSuccessPayload(id: playbackState.id))
        } catch is CancellationError {
            result = .failure(
                WorkerError(
                    code: .requestCancelled,
                    message: "Request '\(playbackState.id)' was cancelled before it could complete.",
                ),
            )
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Live playback failed for request '\(playbackState.id)' due to an unexpected internal error. \(error.localizedDescription)",
                ),
            )
        }

        await finishPlayback(requestID: playbackState.id, result: result, hooks: hooks)
    }

    private func finishPlayback(
        requestID: String,
        result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>,
        hooks: PlaybackHooks,
    ) async {
        guard activePlayback?.requestID == requestID else { return }

        activePlayback = nil
        activePlaybackIsStableForConcurrentGeneration = false
        activePlaybackStableBufferedAudioMS = nil
        activePlaybackStableBufferTargetMS = nil
        activePlaybackConcurrentGenerationTargetMS = nil
        activePlaybackFragileOverlapWindowProgress = nil
        activePlaybackIsRebuffering = false
        queue.removeAll { $0 == requestID }

        guard let playbackState = jobs.removeValue(forKey: requestID) else {
            await startNextIfPossible()
            return
        }

        playbackState.execution.generationTask = nil
        playbackState.execution.playbackTask = nil
        await hooks.completeJob(playbackState.request, result)
        await hooks.resumeQueue()
    }
}
