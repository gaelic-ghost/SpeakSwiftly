import Testing
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Runtime Construction

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.live()
}

// MARK: - Runtime Helpers

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let speak: @Sendable (SpeakSwiftly.Runtime, String, String, String?, TextForSpeech.Context?, String) async -> SpeakSwiftly.RequestHandle = {
        runtime,
        text,
        profileName,
        textProfileName,
        textContext,
        id in
        await runtime.speak(
            text: text,
            with: profileName,
            as: .live,
            textProfileName: textProfileName,
            textContext: textContext,
            id: id
        )
    }
    let textProfile: @Sendable (SpeakSwiftly.Runtime, String) async -> TextForSpeech.Profile? = { runtime, name in
        await runtime.textProfile(named: name)
    }
    let textProfileSnapshot: @Sendable (SpeakSwiftly.Runtime, String?) async -> TextForSpeech.Profile = { runtime, name in
        await runtime.textProfileSnapshot(named: name)
    }
    let storeTextProfile: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Profile) async -> Void = { runtime, profile in
        await runtime.storeTextProfile(profile)
    }
    let useTextProfile: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Profile) async -> Void = { runtime, profile in
        await runtime.useTextProfile(profile)
    }
    let removeTextProfile: @Sendable (SpeakSwiftly.Runtime, String) async -> Void = { runtime, name in
        await runtime.removeTextProfile(named: name)
    }
    let resetTextProfile: @Sendable (SpeakSwiftly.Runtime) async -> Void = { runtime in
        await runtime.resetTextProfile()
    }
    let createProfile: @Sendable (SpeakSwiftly.Runtime, String, String, String, String?, String) async -> SpeakSwiftly.RequestHandle = {
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
    let profiles: @Sendable (SpeakSwiftly.Runtime, String) async -> SpeakSwiftly.RequestHandle = { runtime, id in
        await runtime.profiles(id: id)
    }
    let removeProfile: @Sendable (SpeakSwiftly.Runtime, String, String) async -> SpeakSwiftly.RequestHandle = { runtime, profileName, id in
        await runtime.removeProfile(named: profileName, id: id)
    }
    let generationQueue: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.queue(.generation)
    }
    let playbackQueue: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.queue(.playback)
    }
    let playbackPause: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.playback(.pause)
    }
    let clearQueue: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.clearQueue()
    }
    let cancelRequest: @Sendable (SpeakSwiftly.Runtime, String) async -> SpeakSwiftly.RequestHandle = { runtime, id in
        await runtime.cancelRequest(id)
    }
    let statusEvents: @Sendable (SpeakSwiftly.Runtime) async -> AsyncStream<SpeakSwiftly.StatusEvent> = { runtime in
        await runtime.statusEvents()
    }

    _ = speak
    _ = createProfile
    _ = profiles
    _ = removeProfile
    _ = textProfile
    _ = textProfileSnapshot
    _ = storeTextProfile
    _ = useTextProfile
    _ = removeTextProfile
    _ = resetTextProfile
    _ = generationQueue
    _ = playbackQueue
    _ = playbackPause
    _ = clearQueue
    _ = cancelRequest
    _ = statusEvents
}

// MARK: - Handle Metadata

@Test func publicWorkerRequestHandleExposesStableMetadata() {
    let operation: KeyPath<SpeakSwiftly.RequestHandle, String> = \.operation
    let profileName: KeyPath<SpeakSwiftly.RequestHandle, String?> = \.profileName
    let events: KeyPath<SpeakSwiftly.RequestHandle, AsyncThrowingStream<SpeakSwiftly.RequestEvent, any Swift.Error>> = \.events

    _ = operation
    _ = profileName
    _ = events
}
