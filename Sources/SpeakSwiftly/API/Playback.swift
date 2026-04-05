import Foundation

// MARK: - Playback API

public extension SpeakSwiftly.Runtime {
    func queue(
        _ queueType: SpeakSwiftly.Queue,
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.listQueue(id: requestID, queueType: queueType))
    }

    func playback(
        _ action: SpeakSwiftly.PlaybackAction,
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.playback(id: requestID, action: action))
    }

    func clearQueue(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await submit(.clearQueue(id: requestID))
    }

    func cancelRequest(
        _ id: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.cancelRequest(id: requestID, requestID: id))
    }

    func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down."
        )

        if let activeGeneration {
            self.activeGeneration = nil
            activeGeneration.task.cancel()
            failRequestStream(for: activeGeneration.request.id, error: cancellationError)
            requestAcceptedAt.removeValue(forKey: activeGeneration.request.id)
            await emitFailure(id: activeGeneration.request.id, error: cancellationError)
        }

        if let activePlayback {
            self.activePlayback = nil
            activePlayback.task.cancel()
        }

        await failQueuedRequests(with: cancellationError)
        await failWaitingPlaybackRequests(with: cancellationError)
        await playbackController.stop()
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(await generationQueueDepth())])
    }
}
