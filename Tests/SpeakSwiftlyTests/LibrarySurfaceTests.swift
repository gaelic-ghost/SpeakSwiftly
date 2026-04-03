import Testing
import SpeakSwiftlyCore

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.makeLiveRuntime()
}

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let liveSubmit: @Sendable (WorkerRuntime, String, String, String) async -> String = { runtime, text, profileName, id in
        await runtime.speakLive(text: text, profileName: profileName, id: id)
    }
    let backgroundSubmit: @Sendable (WorkerRuntime, String, String, String) async -> String = { runtime, text, profileName, id in
        await runtime.speakLiveBackground(text: text, profileName: profileName, id: id)
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
    let listQueue: @Sendable (WorkerRuntime) async -> String = { runtime in
        await runtime.listQueue()
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

    _ = liveSubmit
    _ = backgroundSubmit
    _ = createProfile
    _ = listProfiles
    _ = removeProfile
    _ = listQueue
    _ = clearQueue
    _ = cancelRequest
    _ = statusEvents
    _ = submit
}
