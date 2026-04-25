import Foundation

// MARK: - Playback Runtime Glue

extension SpeakSwiftly.Runtime {
    // MARK: - Queue Management

    func clearQueuedRequests(
        queueType: WorkerQueueType?,
        cancelledByRequestID: String,
        reason: String,
    ) async -> Int {
        let queuedJobs = if queueType == nil || queueType == .generation {
            await generationController.clearQueued()
        } else {
            [SpeechGenerationController.Job]()
        }
        let activePlaybackRequestID = await playbackController.activeRequestSummary()?.id
        let protectedRequestIDs = Set(activeGenerations.values.map(\.request.id) + [activePlaybackRequestID].compactMap { $0 })
        let waitingPlaybackJobs = if queueType == nil || queueType == .playback {
            await playbackController.clearQueued(excluding: protectedRequestIDs)
        } else {
            [LiveSpeechPlaybackState]()
        }

        let cancellation = WorkerError(
            code: .requestCancelled,
            message: "Request '\(cancelledByRequestID)' cancelled this work because \(reason).",
        )

        for job in queuedJobs {
            if job.request.requiresPlayback {
                _ = await playbackController.discard(requestID: job.request.id)
            }
            markGenerationJobFailedIfNeeded(for: job.request, error: cancellation)
            failRequestStream(for: job.request.id, error: cancellation)
            await logError(
                cancellation.message,
                requestID: job.request.id,
                details: ["failure_code": .string(cancellation.code.rawValue)],
            )
            await emitFailure(id: job.request.id, error: cancellation)
        }

        for playbackState in waitingPlaybackJobs {
            playbackState.execution.generationTask?.cancel()
            playbackState.execution.playbackTask?.cancel()
            playbackState.execution.continuation.finish(throwing: cancellation)
            await logError(
                cancellation.message,
                requestID: playbackState.id,
                details: ["failure_code": .string(cancellation.code.rawValue)],
            )
            await completePlaybackJob(playbackState.request, result: .failure(cancellation))
        }

        return queuedJobs.count + waitingPlaybackJobs.count
    }

    func failWaitingPlaybackRequests(with error: WorkerError) async {
        let activePlaybackRequestID = await playbackController.activeRequestSummary()?.id
        let protectedRequestIDs = Set(activeGenerations.values.map(\.request.id) + [activePlaybackRequestID].compactMap { $0 })
        let waitingPlaybackJobs = await playbackController.clearQueued(excluding: protectedRequestIDs)

        for playbackState in waitingPlaybackJobs {
            playbackState.execution.generationTask?.cancel()
            playbackState.execution.playbackTask?.cancel()
            playbackState.execution.continuation.finish(throwing: error)
            await completePlaybackJob(playbackState.request, result: .failure(error))
        }
    }

    func cancelRequestNow(
        _ targetRequestID: String,
        queueType: WorkerQueueType?,
        cancelledByRequestID: String,
    ) async throws -> String {
        let cancellation = WorkerError(
            code: .requestCancelled,
            message: "Request '\(targetRequestID)' was cancelled by control request '\(cancelledByRequestID)'.",
        )

        if queueType == nil || queueType == .playback,
           let playbackState = await playbackController.cancel(requestID: targetRequestID) {
            playbackState.execution.continuation.finish(throwing: cancellation)
            await completePlaybackJob(playbackState.request, result: .failure(cancellation))
            try? await startNextGenerationIfPossible()
            await playbackController.startNextIfPossible()
            return targetRequestID
        }

        guard queueType == nil || queueType == .generation else {
            throw requestNotFoundError(targetRequestID, queueType: queueType, cancelledByRequestID: cancelledByRequestID)
        }

        let cancelledGenerationTarget = await generationController.cancel(requestID: targetRequestID)

        switch cancelledGenerationTarget {
            case let .active(job):
                activeGenerations.removeValue(forKey: job.token)?.task.cancel()
                if job.request.requiresPlayback,
                   let playbackState = await playbackController.cancel(requestID: targetRequestID) {
                    playbackState.execution.continuation.finish(throwing: cancellation)
                    await completePlaybackJob(playbackState.request, result: .failure(cancellation))
                }
                markGenerationJobFailedIfNeeded(for: job.request, error: cancellation)
                failRequestStream(for: targetRequestID, error: cancellation)
                await logError(
                    cancellation.message,
                    requestID: targetRequestID,
                    details: ["failure_code": .string(cancellation.code.rawValue)],
                )
                await emitFailure(id: targetRequestID, error: cancellation)
                try? await startNextGenerationIfPossible()
                return targetRequestID
            case let .queued(job):
                if job.request.requiresPlayback {
                    _ = await playbackController.discard(requestID: job.request.id)
                }
                markGenerationJobFailedIfNeeded(for: job.request, error: cancellation)
                failRequestStream(for: targetRequestID, error: cancellation)
                await logError(
                    cancellation.message,
                    requestID: targetRequestID,
                    details: ["failure_code": .string(cancellation.code.rawValue)],
                )
                await emitFailure(id: job.request.id, error: cancellation)
                return targetRequestID
            case nil:
                break
        }

        throw requestNotFoundError(targetRequestID, queueType: queueType, cancelledByRequestID: cancelledByRequestID)
    }

    private func requestNotFoundError(
        _ targetRequestID: String,
        queueType: WorkerQueueType?,
        cancelledByRequestID: String,
    ) -> WorkerError {
        let scope = queueType.map { " in the \($0.rawValue) queue" } ?? " in the active or queued SpeakSwiftly work set"
        return WorkerError(
            code: .requestNotFound,
            message: "Control request '\(cancelledByRequestID)' could not find request '\(targetRequestID)'\(scope).",
        )
    }

    // MARK: - Playback Completion

    func completePlaybackJob(
        _ speechRequest: LiveSpeechRequestState,
        result: Result<WorkerSuccessPayload, WorkerError>,
    ) async {
        await completeRequest(request: speechRequest.request, result: result)
    }
}
