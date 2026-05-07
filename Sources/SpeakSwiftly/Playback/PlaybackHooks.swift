struct PlaybackHooks {
    let handleEvent: @Sendable (PlaybackEvent, LiveSpeechRequestState) async -> Void
    let handleEnvironmentEvent: @Sendable (PlaybackEnvironmentEvent, ActiveWorkerRequestSummary?) async -> Void
    let logEngineReady: @Sendable (LiveSpeechRequestState, Double) async -> Void
    let logFinished: @Sendable (LiveSpeechRequestState, PlaybackSummary, Double) async -> Void
    let completeJob: @Sendable (LiveSpeechRequestState, Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>) async -> Void
    let resumeQueue: @Sendable () async -> Void
}
