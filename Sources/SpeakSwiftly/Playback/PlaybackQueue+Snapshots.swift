import Foundation

extension PlaybackQueue {
    func workerStateSnapshot() async -> SpeakSwiftly.WorkerPlaybackStateSnapshot {
        let activeRequest = activeRequestSummary()
        let telemetry = coordinationTelemetrySnapshot()
        let driverState = await driver.state()
        return SpeakSwiftly.WorkerPlaybackStateSnapshot(
            state: resolvedPlaybackState(driverState: driverState, activeRequest: activeRequest),
            activeRequest: activeRequest,
            isStableForConcurrentGeneration: telemetry.isStableForConcurrentGeneration,
            isRebuffering: telemetry.isRebuffering,
            stableBufferedAudioMS: telemetry.stableBufferedAudioMS,
            stableBufferTargetMS: telemetry.stableBufferTargetMS,
        )
    }

    func stateSnapshot(sequence: Int, capturedAt: Date) async -> SpeakSwiftly.PlaybackSnapshot {
        await workerStateSnapshot().playbackSnapshot(
            sequence: sequence,
            capturedAt: capturedAt,
            queuedRequests: queuedRequestSummaries(),
        )
    }

    func resolvedPlaybackState(
        driverState: PlaybackState,
        activeRequest: ActiveWorkerRequestSummary? = nil,
    ) -> PlaybackState {
        let resolvedActiveRequest = activeRequest ?? activeRequestSummary()
        guard resolvedActiveRequest != nil else {
            return .idle
        }

        if driverState == .paused {
            return .paused
        }

        return .playing
    }
}
