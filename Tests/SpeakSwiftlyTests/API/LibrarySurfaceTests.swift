import Foundation
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
    let normalizer: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Normalizer = { runtime in
        runtime.normalizer
    }
    let profile: @Sendable (SpeakSwiftly.Normalizer, String) async -> TextForSpeech.Profile? = { normalizer, name in
        await normalizer.profile(named: name)
    }
    let profilesList: @Sendable (SpeakSwiftly.Normalizer) async -> [TextForSpeech.Profile] = { normalizer in
        await normalizer.profiles()
    }
    let activeProfile: @Sendable (SpeakSwiftly.Normalizer) async -> TextForSpeech.Profile = { normalizer in
        await normalizer.activeProfile()
    }
    let baseProfile: @Sendable (SpeakSwiftly.Normalizer) async -> TextForSpeech.Profile = { normalizer in
        await normalizer.baseProfile()
    }
    let effectiveProfile: @Sendable (SpeakSwiftly.Normalizer, String?) async -> TextForSpeech.Profile = { normalizer, name in
        await normalizer.effectiveProfile(named: name)
    }
    let persistenceURL: @Sendable (SpeakSwiftly.Normalizer) async -> URL? = { normalizer in
        await normalizer.persistenceURL()
    }
    let loadProfiles: @Sendable (SpeakSwiftly.Normalizer) async throws -> Void = { normalizer in
        try await normalizer.loadProfiles()
    }
    let saveProfiles: @Sendable (SpeakSwiftly.Normalizer) async throws -> Void = { normalizer in
        try await normalizer.saveProfiles()
    }
    let createProfileObject: @Sendable (SpeakSwiftly.Normalizer, String, String, [TextForSpeech.Replacement]) async throws -> TextForSpeech.Profile = {
        normalizer,
        id,
        name,
        replacements in
        try await normalizer.createProfile(id: id, named: name, replacements: replacements)
    }
    let storeProfile: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Profile) async throws -> Void = { normalizer, profile in
        try await normalizer.storeProfile(profile)
    }
    let useProfile: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Profile) async throws -> Void = { normalizer, profile in
        try await normalizer.useProfile(profile)
    }
    let removeProfileObject: @Sendable (SpeakSwiftly.Normalizer, String) async throws -> Void = { normalizer, name in
        try await normalizer.removeProfile(named: name)
    }
    let reset: @Sendable (SpeakSwiftly.Normalizer) async throws -> Void = { normalizer in
        try await normalizer.reset()
    }
    let addActiveReplacement: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacement in
        try await normalizer.addReplacement(replacement)
    }
    let addStoredReplacement: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacement,
        name in
        try await normalizer.addReplacement(replacement, toStoredProfileNamed: name)
    }
    let replaceActiveReplacement: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacement in
        try await normalizer.replaceReplacement(replacement)
    }
    let replaceStoredReplacement: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacement,
        name in
        try await normalizer.replaceReplacement(replacement, inStoredProfileNamed: name)
    }
    let removeActiveReplacement: @Sendable (SpeakSwiftly.Normalizer, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacementID in
        try await normalizer.removeReplacement(id: replacementID)
    }
    let removeStoredReplacement: @Sendable (SpeakSwiftly.Normalizer, String, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacementID,
        name in
        try await normalizer.removeReplacement(id: replacementID, fromStoredProfileNamed: name)
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
    let createClone: @Sendable (SpeakSwiftly.Runtime, String, URL, String?, String) async -> SpeakSwiftly.RequestHandle = {
        runtime,
        profileName,
        referenceAudioURL,
        transcript,
        id in
        await runtime.createClone(
            named: profileName,
            from: referenceAudioURL,
            transcript: transcript,
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
    _ = normalizer
    _ = createProfile
    _ = createClone
    _ = profiles
    _ = removeProfile
    _ = profile
    _ = profilesList
    _ = activeProfile
    _ = baseProfile
    _ = effectiveProfile
    _ = persistenceURL
    _ = loadProfiles
    _ = saveProfiles
    _ = createProfileObject
    _ = storeProfile
    _ = useProfile
    _ = removeProfileObject
    _ = reset
    _ = addActiveReplacement
    _ = addStoredReplacement
    _ = replaceActiveReplacement
    _ = replaceStoredReplacement
    _ = removeActiveReplacement
    _ = removeStoredReplacement
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
