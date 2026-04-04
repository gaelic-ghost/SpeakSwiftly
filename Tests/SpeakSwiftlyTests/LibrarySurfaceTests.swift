import Testing
import SpeakSwiftlyCore
import TextForSpeechCore

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.live()
}

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let speak: @Sendable (WorkerRuntime, String, String, SpeechNormalizationContext?, String) async -> WorkerRequestHandle = {
        runtime,
        text,
        profileName,
        normalizationContext,
        id in
        await runtime.speak(
            text: text,
            with: profileName,
            as: .live,
            context: normalizationContext,
            id: id
        )
    }
    let createProfile: @Sendable (WorkerRuntime, String, String, String, String?, String) async -> WorkerRequestHandle = {
        runtime,
        profileName,
        text,
        voiceDescription,
        outputPath,
        id in
        await runtime.createProfile(
            named: profileName,
            from: text,
            voice: voiceDescription,
            outputPath: outputPath,
            id: id
        )
    }
    let profiles: @Sendable (WorkerRuntime, String) async -> WorkerRequestHandle = { runtime, id in
        await runtime.profiles(id: id)
    }
    let removeProfile: @Sendable (WorkerRuntime, String, String) async -> WorkerRequestHandle = { runtime, profileName, id in
        await runtime.removeProfile(named: profileName, id: id)
    }
    let generationQueue: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.queue(.generation)
    }
    let playbackQueue: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.queue(.playback)
    }
    let playbackPause: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.playback(.pause)
    }
    let clearQueue: @Sendable (WorkerRuntime) async -> WorkerRequestHandle = { runtime in
        await runtime.clearQueue()
    }
    let cancelRequest: @Sendable (WorkerRuntime, String) async -> WorkerRequestHandle = { runtime, id in
        await runtime.cancelRequest(id)
    }
    let statusEvents: @Sendable (WorkerRuntime) async -> AsyncStream<WorkerStatusEvent> = { runtime in
        await runtime.statusEvents()
    }

    _ = speak
    _ = createProfile
    _ = profiles
    _ = removeProfile
    _ = generationQueue
    _ = playbackQueue
    _ = playbackPause
    _ = clearQueue
    _ = cancelRequest
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
