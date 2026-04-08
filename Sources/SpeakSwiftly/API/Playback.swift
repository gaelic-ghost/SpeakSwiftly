import Foundation

// MARK: - Playback API

public extension SpeakSwiftly {
    struct Player: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    nonisolated var player: SpeakSwiftly.Player {
        SpeakSwiftly.Player(runtime: self)
    }
}

public extension SpeakSwiftly.Player {
    func generationQueue(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: requestID, queueType: .generation))
    }

    func playbackQueue(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: requestID, queueType: .playback))
    }

    func pause(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: requestID, action: .pause))
    }

    func resume(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: requestID, action: .resume))
    }

    func state(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: requestID, action: .state))
    }

    func clearQueue(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.clearQueue(id: requestID))
    }

    func cancelRequest(
        _ id: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.cancelRequest(id: requestID, requestID: id))
    }
}

public extension SpeakSwiftly.Runtime {
    func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down."
        )

        if let activeGeneration {
            activeGeneration.task.cancel()
            await activeGeneration.task.value
        }

        await failQueuedRequests(with: cancellationError)
        await failWaitingPlaybackRequests(with: cancellationError)
        let cancelledPlaybackJobs = await playbackController.shutdown()
        for job in cancelledPlaybackJobs {
            job.continuation.finish(throwing: cancellationError)
            await completePlaybackJob(job, result: .failure(cancellationError))
        }
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(await generationQueueDepth())])
    }
}
