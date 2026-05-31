@testable import SpeakSwiftly
import Testing

@Test func `playback queue stops driver only after queued playback drains`() async throws {
    let playback = PlaybackSpy()
    let playbackQueue = PlaybackQueue(driver: playback.driver())
    await playbackQueue.bind(
        PlaybackHooks(
            handleEvent: { _, _ in },
            handleEnvironmentEvent: { _, _ in },
            playbackStarted: { _ in },
            playbackCompleted: { _ in },
            activeRequestChanged: {},
            queueChanged: {},
            logEngineReady: { _, _ in },
            logFinished: { _, _, _ in },
            completeJob: { _, _ in },
            resumeQueue: {},
        ),
    )

    await playbackQueue.enqueue(makePlaybackRequest(id: "req-playback-1"))
    await playbackQueue.enqueue(makePlaybackRequest(id: "req-playback-2"))
    await finishQueuedPlaybackInput(requestID: "req-playback-1", in: playbackQueue)
    await finishQueuedPlaybackInput(requestID: "req-playback-2", in: playbackQueue)

    await playbackQueue.startNextIfPossible()
    #expect(await waitUntil { playback.playCount == 1 })
    for _ in 0..<20 where await playbackQueue.hasActivePlayback() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await !playbackQueue.hasActivePlayback())
    #expect(playback.stopCount == 0)

    await playbackQueue.startNextIfPossible()
    #expect(await waitUntil { playback.playCount == 2 })
    #expect(await waitUntil { playback.stopCount == 1 })
}

private func makePlaybackRequest(id: String) -> LiveSpeechRequestState {
    let text = "Playback queue restore guard test."
    return LiveSpeechRequestState(
        request: .queueSpeech(
            id: id,
            text: text,
            profileName: "testing-profile",
            textProfileID: nil,
            jobType: .live,
            requestContext: nil,
            qwenPreModelTextChunking: nil,
        ),
        normalizedText: text,
        normalizedLiveChunks: nil,
        textFeatures: SpeakSwiftly.DeepTrace.features(originalText: text, normalizedText: text),
        textSections: SpeakSwiftly.DeepTrace.sections(originalText: text),
        playbackTuningProfile: .standard,
        residentStreamingCadenceProfile: .standard,
        residentStreamingInterval: 0.5,
    )
}

private func finishQueuedPlaybackInput(
    requestID: String,
    in playbackQueue: PlaybackQueue,
) async {
    guard let playbackState = await playbackQueue.playbackState(for: requestID) else { return }

    playbackState.execution.sampleRate = 24000
    playbackState.execution.continuation.yield([0.1, 0.2, 0.3])
    playbackState.execution.continuation.finish()
}
