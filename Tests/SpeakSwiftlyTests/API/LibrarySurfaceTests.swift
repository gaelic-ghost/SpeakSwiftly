import Foundation
import Testing
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Runtime Construction

@Test func publicLibrarySurfaceConstructsRuntimeFromLiftoff() async {
    _ = await SpeakSwiftly.liftoff()
}

@Test func publicLibrarySurfaceConstructsTopLevelNormalizer() {
    let persistenceURL = URL(fileURLWithPath: "/tmp/speakswiftly-test-profiles.json")
    let normalizer = SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
    _ = normalizer
}

@Test func publicLibrarySurfaceConstructsConfiguration() {
    let configuration = SpeakSwiftly.Configuration(speechBackend: .marvis)
    #expect(configuration.speechBackend == .marvis)
    #expect(configuration.textNormalizer == nil)
}

@Test func publicConfigurationRoundTripsToDisk() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let persistenceURL = rootURL.appendingPathComponent("configuration.json")
    let configuration = SpeakSwiftly.Configuration(speechBackend: .marvis)

    try configuration.save(to: persistenceURL)
    let loaded = try SpeakSwiftly.Configuration.load(from: persistenceURL)

    #expect(loaded.speechBackend == configuration.speechBackend)
    #expect(loaded.textNormalizer == nil)
}

@Test func publicConfigurationLoadThrowsTypedErrorWhenFileIsMissing() throws {
    let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("missing-configuration.json")

    #expect(throws: SpeakSwiftly.Configuration.LoadError.self) {
        try SpeakSwiftly.Configuration.load(from: missingURL)
    }
}

@Test func publicConfigurationCanCarryATextNormalizer() {
    let normalizer = SpeakSwiftly.Normalizer()
    let configuration = SpeakSwiftly.Configuration(
        speechBackend: .marvis,
        textNormalizer: normalizer
    )

    #expect(configuration.speechBackend == .marvis)
    #expect(configuration.textNormalizer != nil)
}

// MARK: - Runtime Helpers

@Test func publicLibrarySurfaceExposesQueueingHelpers() {
    let speak: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, String?, TextForSpeech.Context?, TextForSpeech.SourceFormat?) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfileName,
        textContext,
        sourceFormat in
        await generate.speech(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            textContext: textContext,
            sourceFormat: sourceFormat
        )
    }
    let generateAudio: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, String?, TextForSpeech.Context?, TextForSpeech.SourceFormat?) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfileName,
        textContext,
        sourceFormat in
        await generate.audio(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            textContext: textContext,
            sourceFormat: sourceFormat
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
    let liftoffWithDefaults: @Sendable () async -> SpeakSwiftly.Runtime = {
        await SpeakSwiftly.liftoff()
    }
    let liftoffWithConfiguration: @Sendable (SpeakSwiftly.Configuration) async -> SpeakSwiftly.Runtime = { configuration in
        await SpeakSwiftly.liftoff(configuration: configuration)
    }
    let profile: @Sendable (SpeakSwiftly.Normalizer, String) async -> TextForSpeech.Profile? = { normalizer, id in
        await normalizer.profile(id: id)
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
    let effectiveProfile: @Sendable (SpeakSwiftly.Normalizer, String?) async -> TextForSpeech.Profile = { normalizer, id in
        await normalizer.effectiveProfile(id: id)
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
    let removeProfileObject: @Sendable (SpeakSwiftly.Normalizer, String) async throws -> Void = { normalizer, id in
        try await normalizer.removeProfile(id: id)
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
        profileID in
        try await normalizer.addReplacement(replacement, toStoredProfileID: profileID)
    }
    let replaceActiveReplacement: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacement in
        try await normalizer.replaceReplacement(replacement)
    }
    let replaceStoredReplacement: @Sendable (SpeakSwiftly.Normalizer, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacement,
        profileID in
        try await normalizer.replaceReplacement(replacement, inStoredProfileID: profileID)
    }
    let removeActiveReplacement: @Sendable (SpeakSwiftly.Normalizer, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacementID in
        try await normalizer.removeReplacement(id: replacementID)
    }
    let removeStoredReplacement: @Sendable (SpeakSwiftly.Normalizer, String, String) async throws -> TextForSpeech.Profile = {
        normalizer,
        replacementID,
        profileID in
        try await normalizer.removeReplacement(id: replacementID, fromStoredProfileID: profileID)
    }
    let createProfile: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name, String, SpeakSwiftly.Vibe, String, String?) async -> SpeakSwiftly.RequestHandle = {
        voices,
        profileName,
        text,
        vibe,
        voiceDescription,
        outputPath in
        await voices.create(
            design: profileName,
            from: text,
            vibe: vibe,
            voice: voiceDescription,
            outputPath: outputPath
        )
    }
    let createClone: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name, URL, SpeakSwiftly.Vibe, String?) async -> SpeakSwiftly.RequestHandle = {
        voices,
        profileName,
        referenceAudioURL,
        vibe,
        transcript in
        await voices.create(
            clone: profileName,
            from: referenceAudioURL,
            vibe: vibe,
            transcript: transcript
        )
    }
    let profiles: @Sendable (SpeakSwiftly.Voices) async -> SpeakSwiftly.RequestHandle = { voices in
        await voices.list()
    }
    let removeProfile: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle = { voices, profileName in
        await voices.delete(named: profileName)
    }
    let generatedFile: @Sendable (SpeakSwiftly.Artifacts, String) async -> SpeakSwiftly.RequestHandle = { artifacts, artifactID in
        await artifacts.file(id: artifactID)
    }
    let generatedFiles: @Sendable (SpeakSwiftly.Artifacts) async -> SpeakSwiftly.RequestHandle = { artifacts in
        await artifacts.files()
    }
    let generateBatch: @Sendable (SpeakSwiftly.Generate, [SpeakSwiftly.BatchItem], SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle = {
        generate,
        items,
        profileName in
        await generate.batch(items, with: profileName)
    }
    let generatedBatch: @Sendable (SpeakSwiftly.Artifacts, String) async -> SpeakSwiftly.RequestHandle = { artifacts, batchID in
        await artifacts.batch(id: batchID)
    }
    let generatedBatches: @Sendable (SpeakSwiftly.Artifacts) async -> SpeakSwiftly.RequestHandle = { artifacts in
        await artifacts.batches()
    }
    let expireGenerationJob: @Sendable (SpeakSwiftly.Jobs, String) async -> SpeakSwiftly.RequestHandle = { jobs, jobID in
        await jobs.expire(id: jobID)
    }
    let generationJob: @Sendable (SpeakSwiftly.Jobs, String) async -> SpeakSwiftly.RequestHandle = { jobs, jobID in
        await jobs.job(id: jobID)
    }
    let generationJobs: @Sendable (SpeakSwiftly.Jobs) async -> SpeakSwiftly.RequestHandle = { jobs in
        await jobs.list()
    }
    let generationQueue: @Sendable (SpeakSwiftly.Jobs) async -> SpeakSwiftly.RequestHandle = { jobs in
        await jobs.generationQueue()
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
        await player.list()
    }
    let playbackPause: @Sendable (SpeakSwiftly.Player) async -> SpeakSwiftly.RequestHandle = { player in
        await player.pause()
    }
    let clearQueue: @Sendable (SpeakSwiftly.Player) async -> SpeakSwiftly.RequestHandle = { player in
        await player.clearQueue()
    }
    let cancelRequest: @Sendable (SpeakSwiftly.Player, String) async -> SpeakSwiftly.RequestHandle = { player, requestID in
        await player.cancelRequest(requestID)
    }
    let statusEvents: @Sendable (SpeakSwiftly.Runtime) async -> AsyncStream<SpeakSwiftly.StatusEvent> = { runtime in
        await runtime.statusEvents()
    }

    _ = speak
    _ = generateAudio
    _ = generateHandle
    _ = playerHandle
    _ = voicesHandle
    _ = jobsHandle
    _ = artifactsHandle
    _ = normalizer
    _ = makeNormalizer
    _ = liftoffWithDefaults
    _ = liftoffWithConfiguration
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
    let successActiveRequests: KeyPath<SpeakSwiftly.Success, [SpeakSwiftly.ActiveRequest]?> = \.activeRequests

    _ = speechBackend
    _ = residentState
    _ = successStatus
    _ = successSpeechBackend
    _ = successActiveRequests
}
