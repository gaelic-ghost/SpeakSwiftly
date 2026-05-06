import Foundation

public extension SpeakSwiftly {
    // MARK: Playback Handle

    /// Manages the live playback queue and player state.
    struct Playback: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the playback-control surface for this runtime.
    nonisolated var playback: SpeakSwiftly.Playback {
        SpeakSwiftly.Playback(runtime: self)
    }
}

public extension SpeakSwiftly.Playback {
    // MARK: Operations

    /// Subscribes to sequenced playback-state updates.
    func updates() async -> AsyncStream<SpeakSwiftly.PlaybackUpdate> {
        await runtime.playbackUpdates()
    }

    /// Returns a point-in-time read of live playback state and queued playback work.
    func snapshot() async -> SpeakSwiftly.PlaybackSnapshot {
        await runtime.playbackSnapshot()
    }

    /// Pauses live playback.
    func pause() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .pause))
    }

    /// Resumes live playback after a pause.
    func resume() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: UUID().uuidString, action: .resume))
    }

    /// Clears queued playback work that has not started yet.
    func clearQueue() async -> SpeakSwiftly.RequestHandle {
        await runtime.clearQueue(.playback)
    }

    /// Cancels one queued or active request by identifier.
    func cancelRequest(_ requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.cancelRequest(id: UUID().uuidString, requestID: requestID, queueType: nil))
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
        for playbackState in cancelledPlaybackJobs {
            playbackState.execution.continuation.finish(throwing: cancellationError)
            await completePlaybackJob(playbackState.request, result: .failure(cancellationError))
        }
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(generationQueueDepth())])
    }
}
