import Foundation

// MARK: - SpeakSwiftly.Player

public extension SpeakSwiftly {
    // MARK: Player Handle

    /// Manages the live playback queue and player state.
    struct Player: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the playback-control surface for this runtime.
    nonisolated var player: SpeakSwiftly.Player {
        SpeakSwiftly.Player(runtime: self)
    }
}

public extension SpeakSwiftly.Player {
    // MARK: Operations

    /// Lists the queued and active playback requests.
    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: UUID().uuidString, queueType: .playback))
    }

    /// Pauses live playback.
    func pause() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .pause))
    }

    /// Resumes live playback after a pause.
    func resume() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .resume))
    }

    /// Retrieves the current playback-state snapshot.
    func state() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .state))
    }

    /// Clears queued playback work that has not started yet.
    func clearQueue() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.clearQueue(id: UUID().uuidString))
    }

    /// Cancels one queued or active request by identifier.
    func cancelRequest(_ requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.cancelRequest(id: UUID().uuidString, requestID: requestID))
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Lifecycle

    /// Stops the runtime and cancels any outstanding work that cannot complete cleanly.
    func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down.",
        )

        for activeGeneration in activeGenerations.values {
            activeGeneration.task.cancel()
        }
        for activeGeneration in activeGenerations.values {
            await activeGeneration.task.value
        }

        await failQueuedRequests(with: cancellationError)
        await failWaitingPlaybackRequests(with: cancellationError)
        let cancelledPlaybackJobs = await playbackController.shutdown()
        for job in cancelledPlaybackJobs {
            job.continuation.finish(throwing: cancellationError)
            await completePlaybackJob(job, result: .failure(cancellationError))
        }
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(generationQueueDepth())])
    }
}
