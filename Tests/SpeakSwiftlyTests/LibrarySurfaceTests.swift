import Testing
import SpeakSwiftlyCore

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.makeLiveRuntime()
}

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let queueSpeech: @Sendable (WorkerRuntime, String, String, SpeechNormalizationContext?, String) async -> String = {
        runtime,
        text,
        profileName,
        normalizationContext,
        id in
        await runtime.queueSpeech(
            text: text,
            profileName: profileName,
            as: .live,
            normalizationContext: normalizationContext,
            id: id
        )
    }
    let queueSpeechHandle: @Sendable (WorkerRuntime, String, String, SpeechNormalizationContext?, String) async -> WorkerRequestHandle = {
        runtime,
        text,
        profileName,
        normalizationContext,
        id in
        await runtime.queueSpeechHandle(
            text: text,
            profileName: profileName,
            as: .live,
            normalizationContext: normalizationContext,
            id: id
        )
    }
    let createProfile: @Sendable (WorkerRuntime, String, String, String, String?, String) async -> String = {
        runtime,
        profileName,
        text,
        voiceDescription,
        outputPath,
        id in
        await runtime.createProfile(
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            id: id
        )
    }
    let createProfileHandle: @Sendable (WorkerRuntime, String, String, String, String?, String) async -> WorkerRequestHandle = {
        runtime,
        profileName,
        text,
        voiceDescription,
        outputPath,
        id in
        await runtime.createProfileHandle(
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            id: id
        )
    }
    let listProfiles: @Sendable (WorkerRuntime, String) async -> String = { runtime, id in
        await runtime.listProfiles(id: id)
    }
    let listProfilesHandle: @Sendable (WorkerRuntime, String) async -> WorkerRequestHandle = { runtime, id in
        await runtime.listProfilesHandle(id: id)
    }
    let removeProfile: @Sendable (WorkerRuntime, String, String) async -> String = { runtime, profileName, id in
        await runtime.removeProfile(profileName: profileName, id: id)
    }
    let removeProfileHandle: @Sendable (WorkerRuntime, String, String) async -> WorkerRequestHandle = { runtime, profileName, id in
        await runtime.removeProfileHandle(profileName: profileName, id: id)
    }
    let listGenerationQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.listQueue(.generation)
    }
    let listGenerationQueueHandle: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.listQueueHandle(.generation)
    }
    let listPlaybackQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.listQueue(.playback)
    }
    let listPlaybackQueueHandle: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.listQueueHandle(.playback)
    }
    let playbackPause: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.playback(.pause)
    }
    let playbackPauseHandle: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.playbackHandle(.pause)
    }
    let clearQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.clearQueue()
    }
    let clearQueueHandle: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.clearQueueHandle()
    }
    let cancelRequest: @Sendable (WorkerRuntime, String) async -> String = { runtime, id in
        await runtime.cancelRequest(with: id)
    }
    let cancelRequestHandle: @Sendable (WorkerRuntime, String) async -> WorkerRequestHandle = { runtime, id in
        await runtime.cancelRequestHandle(with: id)
    }
    let statusEvents: @Sendable (WorkerRuntime) async -> AsyncStream<WorkerStatusEvent> = { runtime in
        await runtime.statusEvents()
    }

    _ = queueSpeech
    _ = queueSpeechHandle
    _ = createProfile
    _ = createProfileHandle
    _ = listProfiles
    _ = listProfilesHandle
    _ = removeProfile
    _ = removeProfileHandle
    _ = listGenerationQueue
    _ = listGenerationQueueHandle
    _ = listPlaybackQueue
    _ = listPlaybackQueueHandle
    _ = playbackPause
    _ = playbackPauseHandle
    _ = clearQueue
    _ = clearQueueHandle
    _ = cancelRequest
    _ = cancelRequestHandle
    _ = statusEvents
}

@Test func publicWorkerRequestHandleExposesStableMetadata() {
    let operationName: KeyPath<WorkerRequestHandle, String> = \.operationName
    let profileName: KeyPath<WorkerRequestHandle, String?> = \.profileName
    let events: KeyPath<WorkerRequestHandle, AsyncThrowingStream<WorkerRequestStreamEvent, Error>> = \.events

    _ = operationName
    _ = profileName
    _ = events
}
