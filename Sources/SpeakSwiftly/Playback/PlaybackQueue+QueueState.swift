extension PlaybackQueue {
    func enqueue(_ request: LiveSpeechRequestState) {
        let playbackState = LiveSpeechPlaybackState(
            request: request,
            execution: .make(requestID: request.id),
        )
        jobs[playbackState.id] = playbackState
        queue.append(playbackState.id)
    }

    func setGenerationTask(_ task: Task<Void, Never>?, for requestID: String) {
        jobs[requestID]?.execution.generationTask = task
    }

    func playbackState(for requestID: String) -> LiveSpeechPlaybackState? {
        jobs[requestID]
    }

    func jobCount() -> Int {
        jobs.count
    }

    func activeRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let requestID = activePlayback?.requestID, let playbackState = jobs[requestID] else { return nil }

        return ActiveWorkerRequestSummary(
            id: requestID,
            kind: playbackState.request.kind,
            voiceProfile: playbackState.request.voiceProfile,
            requestContext: playbackState.request.requestContext,
        )
    }

    func hasActivePlayback() -> Bool {
        activePlayback != nil
    }

    func queuedRequestSummaries() -> [QueuedWorkerRequestSummary] {
        let waitingQueue = queue.filter { $0 != activePlayback?.requestID }
        return waitingQueue.enumerated().compactMap { offset, requestID -> QueuedWorkerRequestSummary? in
            guard let playbackState = jobs[requestID] else { return nil }

            return QueuedWorkerRequestSummary(
                id: requestID,
                kind: playbackState.request.kind,
                voiceProfile: playbackState.request.voiceProfile,
                requestContext: playbackState.request.requestContext,
                queuePosition: offset + 1,
            )
        }
    }

    func clearQueued(excluding protectedRequestIDs: Set<String>) -> [LiveSpeechPlaybackState] {
        let waitingRequestIDs = queue.filter { !protectedRequestIDs.contains($0) }
        return waitingRequestIDs.compactMap { requestID in
            let playbackState = jobs.removeValue(forKey: requestID)
            queue.removeAll { $0 == requestID }
            return playbackState
        }
    }

    func cancel(requestID: String, cancelGenerationTask: Bool = true) async -> LiveSpeechPlaybackState? {
        guard let playbackState = jobs[requestID] else { return nil }

        if cancelGenerationTask {
            playbackState.execution.generationTask?.cancel()
        }
        playbackState.execution.playbackTask?.cancel()
        queue.removeAll { $0 == requestID }
        jobs.removeValue(forKey: requestID)

        if activePlayback?.requestID == requestID {
            activePlayback = nil
            await driver.stop()
        }

        return playbackState
    }

    func discard(requestID: String) -> LiveSpeechPlaybackState? {
        queue.removeAll { $0 == requestID }
        return jobs.removeValue(forKey: requestID)
    }

    func shutdown() async -> [LiveSpeechPlaybackState] {
        let activeTask = activePlayback?.task
        activePlayback = nil
        activeTask?.cancel()

        for playbackState in jobs.values {
            playbackState.execution.generationTask?.cancel()
            playbackState.execution.playbackTask?.cancel()
        }

        let cancelledJobs = Array(jobs.values)
        jobs.removeAll()
        queue.removeAll()
        await driver.stop()
        return cancelledJobs
    }
}
