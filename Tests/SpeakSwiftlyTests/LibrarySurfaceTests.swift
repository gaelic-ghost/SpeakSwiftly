import Testing
import SpeakSwiftlyCore

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.makeLiveRuntime()
}

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let queueSpeech: @Sendable (WorkerRuntime, String, String, String) async -> String = { runtime, text, profileName, id in
        await runtime.queueSpeech(text: text, profileName: profileName, as: .live, id: id)
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
    let listProfiles: @Sendable (WorkerRuntime, String) async -> String = { runtime, id in
        await runtime.listProfiles(id: id)
    }
    let removeProfile: @Sendable (WorkerRuntime, String, String) async -> String = { runtime, profileName, id in
        await runtime.removeProfile(profileName: profileName, id: id)
    }
    let listGenerationQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.listQueue(.generation)
    }
    let listPlaybackQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.listQueue(.playback)
    }
    let playbackPause: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.playback(.pause)
    }
    let clearQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.clearQueue()
    }
    let cancelRequest: @Sendable (WorkerRuntime, String) async -> String = { runtime, id in
        await runtime.cancelRequest(with: id)
    }
    let statusEvents: @Sendable (WorkerRuntime) async -> AsyncStream<WorkerStatusEvent> = { runtime in
        await runtime.statusEvents()
    }
    let submit: @Sendable (WorkerRuntime, WorkerRequest) async -> WorkerRequestHandle = { runtime, request in
        await runtime.submit(request)
    }

    _ = queueSpeech
    _ = createProfile
    _ = listProfiles
    _ = removeProfile
    _ = listGenerationQueue
    _ = listPlaybackQueue
    _ = playbackPause
    _ = clearQueue
    _ = cancelRequest
    _ = statusEvents
    _ = submit
}
