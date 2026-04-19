import Foundation

final class PlaybackExecutionState: @unchecked Sendable {
    let stream: AsyncThrowingStream<[Float], any Swift.Error>
    let continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation
    var sampleRate: Double?
    var generationTask: Task<Void, Never>?
    var playbackTask: Task<Void, Never>?

    init(
        stream: AsyncThrowingStream<[Float], any Swift.Error>,
        continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation,
    ) {
        self.stream = stream
        self.continuation = continuation
    }

    static func make(requestID: String) -> PlaybackExecutionState {
        var continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation?
        let stream = AsyncThrowingStream<[Float], any Swift.Error> { continuation = $0 }
        guard let continuation else {
            fatalError(
                "SpeakSwiftly could not create a playback execution stream for request '\(requestID)'. AsyncThrowingStream did not provide its continuation during playback-state creation.",
            )
        }

        return PlaybackExecutionState(
            stream: stream,
            continuation: continuation,
        )
    }
}

final class LiveSpeechPlaybackState: @unchecked Sendable {
    let request: LiveSpeechRequestState
    let execution: PlaybackExecutionState

    init(
        request: LiveSpeechRequestState,
        execution: PlaybackExecutionState,
    ) {
        self.request = request
        self.execution = execution
    }

    var id: String {
        request.id
    }
}
