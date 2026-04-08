import Foundation
import Testing
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Runtime Construction

@Test func publicLibrarySurfaceConstructsLiveRuntime() async {
    _ = await SpeakSwiftly.live()
}

@Test func publicLibrarySurfaceConstructsTopLevelNormalizer() {
    let persistenceURL = URL(fileURLWithPath: "/tmp/speakswiftly-test-profiles.json")
    let normalizer = SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
    _ = normalizer
}

@Test func publicLibrarySurfaceConstructsConfiguration() {
    let configuration = SpeakSwiftly.Configuration(speechBackend: .marvis)
    #expect(configuration.speechBackend == .marvis)
}

@Test func publicConfigurationRoundTripsToDisk() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let persistenceURL = rootURL.appendingPathComponent("configuration.json")
    let configuration = SpeakSwiftly.Configuration(speechBackend: .marvis)

    try configuration.save(to: persistenceURL)
    let loaded = try SpeakSwiftly.Configuration.load(from: persistenceURL)

    #expect(loaded == configuration)
}

// MARK: - Runtime Helpers

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let speak: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, String?, TextForSpeech.Context?, TextForSpeech.SourceFormat?, String) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfileName,
        textContext,
        sourceFormat,
        id in
        await generate.speak(
            text: text,
            with: profileName,
            as: .live,
            textProfileName: textProfileName,
            textContext: textContext,
            sourceFormat: sourceFormat,
            id: id
        )
    }
    let speakFile: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, String?, TextForSpeech.Context?, TextForSpeech.SourceFormat?, String) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfileName,
        textContext,
        sourceFormat,
        id in
        await generate.speak(
            text: text,
            with: profileName,
            as: .file,
            textProfileName: textProfileName,
            textContext: textContext,
            sourceFormat: sourceFormat,
            id: id
        )
    }
    let generateHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Generate = { runtime in
        runtime.generate
    }
    let playerHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Player = { runtime in
        runtime.player
    }
    let voicesHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Voices = { runtime in
        runtime.voices
    }
    let jobsHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Jobs = { runtime in
        runtime.jobs
    }
    let artifactsHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Artifacts = { runtime in
        runtime.artifacts
    }
    let normalizer: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Normalizer = { runtime in
        runtime.normalizer
    }
    let makeNormalizer: @Sendable (URL?) -> SpeakSwiftly.Normalizer = { persistenceURL in
        SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
    }
    let liveWithNormalizer: @Sendable (SpeakSwiftly.Normalizer) async -> SpeakSwiftly.Runtime = { normalizer in
        await SpeakSwiftly.live(normalizer: normalizer)
    }
    let liveWithConfiguration: @Sendable (SpeakSwiftly.Configuration) async -> SpeakSwiftly.Runtime = { configuration in
        await SpeakSwiftly.live(configuration: configuration)
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
    let createProfile: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name, String, SpeakSwiftly.Vibe, String, String?, String) async -> SpeakSwiftly.RequestHandle = {
        voices,
        profileName,
        text,
        vibe,
        voiceDescription,
        outputPath,
        id in
        await voices.create(
            design: profileName,
            from: text,
            vibe: vibe,
            voice: voiceDescription,
            outputPath: outputPath,
            id: id
        )
    }
    let createClone: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name, URL, SpeakSwiftly.Vibe, String?, String) async -> SpeakSwiftly.RequestHandle = {
        voices,
        profileName,
        referenceAudioURL,
        vibe,
        transcript,
        id in
        await voices.create(
            clone: profileName,
            from: referenceAudioURL,
            vibe: vibe,
            transcript: transcript,
            id: id
        )
    }
    let profiles: @Sendable (SpeakSwiftly.Voices, String) async -> SpeakSwiftly.RequestHandle = { voices, id in
        await voices.list(id: id)
    }
    let removeProfile: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name, String) async -> SpeakSwiftly.RequestHandle = { voices, profileName, id in
        await voices.delete(named: profileName, id: id)
    }
    let generatedFile: @Sendable (SpeakSwiftly.Artifacts, String, String) async -> SpeakSwiftly.RequestHandle = { artifacts, artifactID, requestID in
        await artifacts.file(id: artifactID, requestID: requestID)
    }
    let generatedFiles: @Sendable (SpeakSwiftly.Artifacts, String) async -> SpeakSwiftly.RequestHandle = { artifacts, requestID in
        await artifacts.files(id: requestID)
    }
    let generateBatch: @Sendable (SpeakSwiftly.Generate, [SpeakSwiftly.BatchItem], SpeakSwiftly.Name, String) async -> SpeakSwiftly.RequestHandle = {
        generate,
        items,
        profileName,
        id in
        await generate.batch(items, with: profileName, id: id)
    }
    let generatedBatch: @Sendable (SpeakSwiftly.Artifacts, String, String) async -> SpeakSwiftly.RequestHandle = { artifacts, batchID, requestID in
        await artifacts.batch(id: batchID, requestID: requestID)
    }
    let generatedBatches: @Sendable (SpeakSwiftly.Artifacts, String) async -> SpeakSwiftly.RequestHandle = { artifacts, requestID in
        await artifacts.batches(id: requestID)
    }
    let expireGenerationJob: @Sendable (SpeakSwiftly.Jobs, String, String) async -> SpeakSwiftly.RequestHandle = { jobs, jobID, requestID in
        await jobs.expire(id: jobID, requestID: requestID)
    }
    let generationJob: @Sendable (SpeakSwiftly.Jobs, String, String) async -> SpeakSwiftly.RequestHandle = { jobs, jobID, requestID in
        await jobs.job(id: jobID, requestID: requestID)
    }
    let generationJobs: @Sendable (SpeakSwiftly.Jobs, String) async -> SpeakSwiftly.RequestHandle = { jobs, requestID in
        await jobs.list(id: requestID)
    }
    let generationQueue: @Sendable (SpeakSwiftly.Player) async -> SpeakSwiftly.RequestHandle = { player in
        await player.generationQueue()
    }
    let status: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.status()
    }
    let switchSpeechBackend: @Sendable (SpeakSwiftly.Runtime, SpeakSwiftly.SpeechBackend) async -> SpeakSwiftly.RequestHandle = {
        runtime,
        speechBackend in
        await runtime.switchSpeechBackend(to: speechBackend)
    }
    let reloadModels: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.reloadModels()
    }
    let unloadModels: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.unloadModels()
    }
    let playbackQueue: @Sendable (SpeakSwiftly.Player) async -> SpeakSwiftly.RequestHandle = { player in
        await player.playbackQueue()
    }
    let playbackPause: @Sendable (SpeakSwiftly.Player) async -> SpeakSwiftly.RequestHandle = { player in
        await player.pause()
    }
    let clearQueue: @Sendable (SpeakSwiftly.Player) async -> SpeakSwiftly.RequestHandle = { player in
        await player.clearQueue()
    }
    let cancelRequest: @Sendable (SpeakSwiftly.Player, String) async -> SpeakSwiftly.RequestHandle = { player, id in
        await player.cancelRequest(id)
    }
    let statusEvents: @Sendable (SpeakSwiftly.Runtime) async -> AsyncStream<SpeakSwiftly.StatusEvent> = { runtime in
        await runtime.statusEvents()
    }

    _ = speak
    _ = speakFile
    _ = generateHandle
    _ = playerHandle
    _ = voicesHandle
    _ = jobsHandle
    _ = artifactsHandle
    _ = normalizer
    _ = makeNormalizer
    _ = liveWithNormalizer
    _ = liveWithConfiguration
    _ = createProfile
    _ = createClone
    _ = profiles
    _ = removeProfile
    _ = generatedFile
    _ = generatedFiles
    _ = generateBatch
    _ = generatedBatch
    _ = generatedBatches
    _ = expireGenerationJob
    _ = generationJob
    _ = generationJobs
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
    _ = status
    _ = switchSpeechBackend
    _ = reloadModels
    _ = unloadModels
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

@Test func publicGeneratedFileSurfaceExposesStableMetadata() {
    let artifactID: KeyPath<SpeakSwiftly.GeneratedFile, String> = \.artifactID
    let createdAt: KeyPath<SpeakSwiftly.GeneratedFile, Date> = \.createdAt
    let profileName: KeyPath<SpeakSwiftly.GeneratedFile, String> = \.profileName
    let textProfileName: KeyPath<SpeakSwiftly.GeneratedFile, String?> = \.textProfileName
    let sampleRate: KeyPath<SpeakSwiftly.GeneratedFile, Int> = \.sampleRate
    let filePath: KeyPath<SpeakSwiftly.GeneratedFile, String> = \.filePath

    _ = artifactID
    _ = createdAt
    _ = profileName
    _ = textProfileName
    _ = sampleRate
    _ = filePath
}

@Test func publicStatusSurfaceExposesStableMetadata() {
    let speechBackend: KeyPath<SpeakSwiftly.StatusEvent, SpeakSwiftly.SpeechBackend> = \.speechBackend
    let residentState: KeyPath<SpeakSwiftly.StatusEvent, SpeakSwiftly.ResidentModelState> = \.residentState
    let successStatus: KeyPath<SpeakSwiftly.Success, SpeakSwiftly.StatusEvent?> = \.status
    let successSpeechBackend: KeyPath<SpeakSwiftly.Success, SpeakSwiftly.SpeechBackend?> = \.speechBackend

    _ = speechBackend
    _ = residentState
    _ = successStatus
    _ = successSpeechBackend
}
