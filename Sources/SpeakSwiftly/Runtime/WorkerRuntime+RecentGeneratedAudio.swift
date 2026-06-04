import Foundation

extension SpeakSwiftly.Runtime {
    func beginRecentGeneratedAudioCapture(
        requestID: String,
        text: String,
        voiceProfileName: String,
        retentionPolicy: SpeakSwiftly.RecentGeneratedAudioRetentionPolicy = .recentCache,
    ) async -> String? {
        guard await recentGeneratedAudioStore.isCaptureEnabled() else {
            return nil
        }

        let metadata = SpeakSwiftly.RecentGeneratedAudioMetadata(
            requestID: requestID,
            textPreview: recentGeneratedAudioTextPreview(for: text),
            voiceProfileName: voiceProfileName,
            createdAt: dependencies.now(),
            retentionPolicy: retentionPolicy,
        )
        await recentGeneratedAudioStore.begin(metadata)
        return metadata.id
    }

    func recordRecentGeneratedAudioChunk(_ chunk: SpeakSwiftly.GeneratedAudioChunk, recentAudioID: String?) async {
        guard let recentAudioID else { return }

        do {
            try await recentGeneratedAudioStore.append(chunk, to: recentAudioID)
        } catch {
            await failRecentGeneratedAudioCapture(recentAudioID: recentAudioID, error: error)
            await logEvent(
                "recent_generated_audio_capture_failed",
                requestID: chunk.requestID,
                details: [
                    "recent_audio_id": .string(recentAudioID),
                    "error": .string(error.localizedDescription),
                ],
            )
        }
    }

    func finishRecentGeneratedAudioCapture(recentAudioID: String?) async {
        guard let recentAudioID else { return }

        await recentGeneratedAudioStore.finish(
            id: recentAudioID,
            completedAt: dependencies.now(),
        )
    }

    func failRecentGeneratedAudioCapture(recentAudioID: String?, error: any Swift.Error) async {
        guard let recentAudioID else { return }

        await recentGeneratedAudioStore.fail(
            id: recentAudioID,
            message: error.localizedDescription,
            completedAt: dependencies.now(),
        )
    }

    func recentGeneratedAudioSnapshot() async -> SpeakSwiftly.RecentGeneratedAudioSnapshot {
        await recentGeneratedAudioStore.snapshot()
    }

    func recentGeneratedAudioChunks(for id: String) async -> [SpeakSwiftly.GeneratedAudioChunk] {
        await recentGeneratedAudioStore.chunks(for: id)
    }

    func replayRecentGeneratedAudio(
        recentAudioID: String,
        mode: SpeakSwiftly.RecentGeneratedAudioReplayMode,
        requestContext: SpeakSwiftly.RequestContext?,
        requestID: String = UUID().uuidString,
    ) async -> SpeakSwiftly.RequestHandle {
        let item = await recentGeneratedAudioStore.item(id: recentAudioID)
        let request = WorkerRequest.replayRecentAudio(
            id: requestID,
            recentAudioID: recentAudioID,
            text: item?.textPreview ?? "Recent generated audio replay",
            profileName: item?.voiceProfileName ?? defaultVoiceProfileName,
            requestContext: requestContext,
        )
        ensureRequestBroker(for: request)
        let handle = makeRequestHandle(for: request)

        guard await recentGeneratedAudioStore.isCaptureEnabled() else {
            await failRecentGeneratedAudioReplay(
                request,
                code: .invalidRequest,
                message: "Replay request '\(requestID)' cannot play recent generated audio because recentGeneratedAudioLimit is 0, so SpeakSwiftly is not capturing recent generated audio in memory.",
            )
            return handle
        }
        guard let item else {
            await failRecentGeneratedAudioReplay(
                request,
                code: .requestNotFound,
                message: "Replay request '\(requestID)' could not find recent generated audio item '\(recentAudioID)'. The item may have been cleared or evicted from the recent cache.",
            )
            return handle
        }
        guard item.bufferState == .complete else {
            await failRecentGeneratedAudioReplay(
                request,
                code: .invalidRequest,
                message: "Replay request '\(requestID)' cannot play recent generated audio item '\(recentAudioID)' because the item is '\(item.bufferState.rawValue)', not 'complete'.",
            )
            return handle
        }
        guard mode != .interruptCurrent else {
            await failRecentGeneratedAudioReplay(
                request,
                code: .invalidRequest,
                message: "Replay request '\(requestID)' asked to interrupt current playback, but recent generated audio replay currently supports enqueueing after current playback only.",
            )
            return handle
        }

        let chunks = await recentGeneratedAudioStore.chunks(for: recentAudioID)
        let playableChunks = chunks.filter { !$0.isFinal && !$0.samples.isEmpty }
        guard let sampleRate = item.sampleRate ?? playableChunks.first?.sampleRate,
              !playableChunks.isEmpty else {
            await failRecentGeneratedAudioReplay(
                request,
                code: .invalidRequest,
                message: "Replay request '\(requestID)' cannot play recent generated audio item '\(recentAudioID)' because no in-memory PCM chunks are available. Regenerate the speech or replay from a retained artifact once artifact-backed replay is enabled.",
            )
            return handle
        }

        let speechRequest = makeRecentGeneratedAudioReplayState(
            request: request,
            item: item,
        )
        await playbackQueue.enqueue(speechRequest, replayMode: mode)
        if let playbackState = await playbackQueue.playbackState(for: requestID) {
            playbackState.execution.sampleRate = Double(sampleRate)
            let playbackFeedTask = Task {
                do {
                    for chunk in playableChunks {
                        try Task.checkCancellation()
                        playbackState.execution.continuation.yield(chunk.samples)
                    }
                    playbackState.execution.continuation.finish()
                } catch {
                    playbackState.execution.continuation.finish(throwing: error)
                }
            }
            await playbackQueue.setGenerationTask(playbackFeedTask, for: requestID)
        }

        let acknowledgement = SpeakSwiftly.RequestAcknowledgement(
            id: requestID,
            kind: request.requestKind,
            generationJob: nil,
        )
        await yieldRequestEvent(.acknowledged(acknowledgement), for: requestID)
        await emit(WorkerSuccessResponse(id: requestID))
        await logRequestEvent(
            "recent_generated_audio_replay_queued",
            requestID: requestID,
            op: request.opName,
            profileName: item.voiceProfileName,
            details: [
                "recent_audio_id": .string(recentAudioID),
                "chunk_count": .int(playableChunks.count),
                "mode": .string(mode.rawValue),
            ],
        )
        await publishPlaybackUpdate(eventFromSnapshot: { snapshot in
            .queueChanged(
                activeRequest: snapshot.activeRequest,
                queuedRequests: snapshot.queuedRequests,
            )
        })
        await playbackQueue.startNextIfPossible()
        return handle
    }

    func replayRecentGeneratedAudioAll(
        mode: SpeakSwiftly.RecentGeneratedAudioReplayMode,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async -> [SpeakSwiftly.RequestHandle] {
        let snapshot = await recentGeneratedAudioStore.snapshot()
        let completeItems = snapshot.items.filter { $0.bufferState == .complete }
        let insertsAheadOfExistingQueue = mode == .enqueueNext || mode == .enqueueAfterCurrent
        let replayItems = insertsAheadOfExistingQueue ? Array(completeItems.reversed()) : completeItems

        var handles = [SpeakSwiftly.RequestHandle]()
        handles.reserveCapacity(completeItems.count)
        for item in replayItems {
            let handle = await replayRecentGeneratedAudio(
                recentAudioID: item.id,
                mode: mode,
                requestContext: requestContext,
            )
            handles.append(handle)
        }

        if insertsAheadOfExistingQueue {
            handles.reverse()
        }
        return handles
    }

    func clearRecentGeneratedAudio() async {
        await recentGeneratedAudioStore.clear()
    }

    private func makeRecentGeneratedAudioReplayState(
        request: WorkerRequest,
        item: SpeakSwiftly.RecentGeneratedAudioItem,
    ) -> LiveSpeechRequestState {
        let textFeatures = SpeakSwiftly.DeepTrace.features(
            originalText: item.textPreview,
            normalizedText: item.textPreview,
        )
        let textSections = SpeakSwiftly.DeepTrace.sections(originalText: item.textPreview)
        let cadenceProfile = PlaybackConfiguration.residentStreamingCadenceProfile(
            speechBackend: speechBackend,
        )
        return LiveSpeechRequestState(
            request: request,
            normalizedText: item.textPreview,
            normalizedLiveChunks: nil,
            textFeatures: textFeatures,
            textSections: textSections,
            playbackTuningProfile: .standard,
            residentStreamingCadenceProfile: cadenceProfile,
            residentStreamingInterval: PlaybackConfiguration.residentStreamingInterval(
                for: speechBackend,
                cadenceProfile: cadenceProfile,
            ),
        )
    }

    private func failRecentGeneratedAudioReplay(
        _ request: WorkerRequest,
        code: WorkerErrorCode,
        message: String,
    ) async {
        let error = WorkerError(code: code, message: message)
        await failRequestStream(for: request.id, error: error)
        await emitFailure(id: request.id, error: error)
    }

    private func recentGeneratedAudioTextPreview(for text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > 160 else {
            return normalized
        }

        return String(normalized.prefix(157)) + "..."
    }
}
