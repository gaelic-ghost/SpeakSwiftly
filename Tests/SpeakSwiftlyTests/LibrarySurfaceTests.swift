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
    let textProfile: @Sendable (SpeakSwiftly.Runtime, String) async -> TextForSpeech.Profile? = { runtime, name in
        await runtime.textProfile(named: name)
    }
    let textProfiles: @Sendable (SpeakSwiftly.Runtime) async -> [TextForSpeech.Profile] = { runtime in
        await runtime.textProfiles()
    }
    let activeTextProfile: @Sendable (SpeakSwiftly.Runtime) async -> TextForSpeech.Profile = { runtime in
        await runtime.activeTextProfile()
    }
    let baseTextProfile: @Sendable (SpeakSwiftly.Runtime) async -> TextForSpeech.Profile = { runtime in
        await runtime.baseTextProfile()
    }
    let effectiveTextProfile: @Sendable (SpeakSwiftly.Runtime, String?) async -> TextForSpeech.Profile = { runtime, name in
        await runtime.effectiveTextProfile(named: name)
    }
    let textProfilePersistenceURL: @Sendable (SpeakSwiftly.Runtime) async -> URL? = { runtime in
        await runtime.textProfilePersistenceURL()
    }
    let loadTextProfiles: @Sendable (SpeakSwiftly.Runtime) async throws -> Void = { runtime in
        try await runtime.loadTextProfiles()
    }
    let saveTextProfiles: @Sendable (SpeakSwiftly.Runtime) async throws -> Void = { runtime in
        try await runtime.saveTextProfiles()
    }
    let createTextProfile: @Sendable (SpeakSwiftly.Runtime, String, String, [TextForSpeech.Replacement]) async throws -> TextForSpeech.Profile = {
        runtime,
        id,
        name,
        replacements in
        try await runtime.createTextProfile(id: id, named: name, replacements: replacements)
    }
    let storeTextProfile: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Profile) async throws -> Void = { runtime, profile in
        try await runtime.storeTextProfile(profile)
    }
    let useTextProfile: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Profile) async throws -> Void = { runtime, profile in
        try await runtime.useTextProfile(profile)
    }
    let removeTextProfile: @Sendable (SpeakSwiftly.Runtime, String) async throws -> Void = { runtime, name in
        try await runtime.removeTextProfile(named: name)
    }
    let resetTextProfile: @Sendable (SpeakSwiftly.Runtime) async throws -> Void = { runtime in
        try await runtime.resetTextProfile()
    }
    let addActiveTextReplacement: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        runtime,
        replacement in
        try await runtime.addTextReplacement(replacement)
    }
    let addStoredTextReplacement: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        runtime,
        replacement,
        name in
        try await runtime.addTextReplacement(replacement, toStoredTextProfileNamed: name)
    }
    let replaceActiveTextReplacement: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        runtime,
        replacement in
        try await runtime.replaceTextReplacement(replacement)
    }
    let replaceStoredTextReplacement: @Sendable (SpeakSwiftly.Runtime, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        runtime,
        replacement,
        name in
        try await runtime.replaceTextReplacement(replacement, inStoredTextProfileNamed: name)
    }
    let removeActiveTextReplacement: @Sendable (SpeakSwiftly.Runtime, String) async throws -> TextForSpeech.Profile = {
        runtime,
        replacementID in
        try await runtime.removeTextReplacement(id: replacementID)
    }
    let removeStoredTextReplacement: @Sendable (SpeakSwiftly.Runtime, String, String) async throws -> TextForSpeech.Profile = {
        runtime,
        replacementID,
        name in
        try await runtime.removeTextReplacement(id: replacementID, fromStoredTextProfileNamed: name)
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
    _ = textProfiles
    _ = activeTextProfile
    _ = baseTextProfile
    _ = effectiveTextProfile
    _ = textProfilePersistenceURL
    _ = loadTextProfiles
    _ = saveTextProfiles
    _ = createTextProfile
    _ = storeTextProfile
    _ = useTextProfile
    _ = removeTextProfile
    _ = resetTextProfile
    _ = addActiveTextReplacement
    _ = addStoredTextReplacement
    _ = replaceActiveTextReplacement
    _ = replaceStoredTextReplacement
    _ = removeActiveTextReplacement
    _ = removeStoredTextReplacement
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
