import Foundation

extension SpeakSwiftly.Runtime {
    func beginRecentGeneratedAudioCapture(
        requestID: String,
        text: String,
        voiceProfileName: String,
        retentionPolicy: SpeakSwiftly.RecentGeneratedAudioRetentionPolicy = .recentCache,
    ) async -> String {
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

    func recordRecentGeneratedAudioChunk(_ chunk: SpeakSwiftly.GeneratedAudioChunk, recentAudioID: String) async {
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

    func finishRecentGeneratedAudioCapture(recentAudioID: String) async {
        await recentGeneratedAudioStore.finish(
            id: recentAudioID,
            completedAt: dependencies.now(),
        )
    }

    func failRecentGeneratedAudioCapture(recentAudioID: String, error: any Swift.Error) async {
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

    func clearRecentGeneratedAudio() async {
        await recentGeneratedAudioStore.clear()
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
