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
    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: UUID().uuidString, queueType: .playback))
    }

    func pause() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .pause))
    }

    func resume() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .resume))
    }

    func state() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .state))
    }

    func clearQueue() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.clearQueue(id: UUID().uuidString))
    }

    func cancelRequest(_ requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.cancelRequest(id: UUID().uuidString, requestID: requestID))
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
