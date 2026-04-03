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

    _ = liveSubmit
    _ = backgroundSubmit
}
