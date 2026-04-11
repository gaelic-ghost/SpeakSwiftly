import Foundation
import Testing
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Runtime Construction

@Test func publicLibrarySurfaceConstructsRuntimeFromLiftoff() async {
    _ = await SpeakSwiftly.liftoff()
}

@Test func publicLibrarySurfaceConstructsTopLevelNormalizer() throws {
    let persistenceURL = URL(fileURLWithPath: "/tmp/speakswiftly-test-profiles.json")
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
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

@Test func publicConfigurationCanCarryATextNormalizer() throws {
    let normalizer = try SpeakSwiftly.Normalizer()
    let configuration = SpeakSwiftly.Configuration(
        speechBackend: .marvis,
        textNormalizer: normalizer
    )

    #expect(configuration.speechBackend == .marvis)
    #expect(configuration.textNormalizer != nil)
}

// MARK: - Runtime Helpers

@Test func publicLibrarySurfaceExposesQueueingHelpers() throws {
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
    let profilesHandle: @Sendable (SpeakSwiftly.Normalizer) -> SpeakSwiftly.Normalizer.Profiles = { normalizer in
        normalizer.profiles
    }
    let persistenceHandle: @Sendable (SpeakSwiftly.Normalizer) -> SpeakSwiftly.Normalizer.Persistence = { normalizer in
        normalizer.persistence
    }
    let makeNormalizer: @Sendable (URL?) throws -> SpeakSwiftly.Normalizer = { persistenceURL in
        try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
    }
    let liftoffWithDefaults: @Sendable () async -> SpeakSwiftly.Runtime = {
        await SpeakSwiftly.liftoff()
    }
    let liftoffWithConfiguration: @Sendable (SpeakSwiftly.Configuration) async -> SpeakSwiftly.Runtime = { configuration in
        await SpeakSwiftly.liftoff(configuration: configuration)
    }
    let profile: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async -> TextForSpeech.Profile? = { profiles, id in
        await profiles.stored(id: id)
    }
    let profilesList: @Sendable (SpeakSwiftly.Normalizer.Profiles) async -> [TextForSpeech.Profile] = { profiles in
        await profiles.list()
    }
    let activeProfile: @Sendable (SpeakSwiftly.Normalizer.Profiles) async -> TextForSpeech.Profile? = { profiles in
        await profiles.active()
    }
    let effectiveProfile: @Sendable (SpeakSwiftly.Normalizer.Profiles, String?) async -> TextForSpeech.Profile? = { profiles, id in
        await profiles.effective(id: id)
    }
    let activeReplacements: @Sendable (SpeakSwiftly.Normalizer.Profiles) async -> [TextForSpeech.Replacement] = { profiles in
        await profiles.replacements()
    }
    let storedReplacements: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async -> [TextForSpeech.Replacement]? = { profiles, id in
        await profiles.replacements(inStoredProfileID: id)
    }
    let loadProfiles: @Sendable (SpeakSwiftly.Normalizer.Persistence) async throws -> Void = { persistence in
        try await persistence.load()
    }
    let saveProfiles: @Sendable (SpeakSwiftly.Normalizer.Persistence) async throws -> Void = { persistence in
        try await persistence.save()
    }
    let createProfileObject: @Sendable (SpeakSwiftly.Normalizer.Profiles, String, String, [TextForSpeech.Replacement]) async throws -> TextForSpeech.Profile = {
        profiles,
        id,
        name,
        replacements in
        try await profiles.create(id: id, name: name, replacements: replacements)
    }
    let storeProfile: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Profile) async throws -> Void = { profiles, profile in
        try await profiles.store(profile)
    }
    let useProfile: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Profile) async throws -> Void = { profiles, profile in
        try await profiles.use(profile)
    }
    let removeProfileObject: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> Void = { profiles, id in
        try await profiles.delete(id: id)
    }
    let reset: @Sendable (SpeakSwiftly.Normalizer.Profiles) async throws -> Void = { profiles in
        try await profiles.reset()
    }
    let addActiveReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        profiles,
        replacement in
        try await profiles.add(replacement)
    }
    let addStoredReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        profiles,
        replacement,
        profileID in
        try await profiles.add(replacement, toStoredProfileID: profileID)
    }
    let replaceActiveReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement) async throws -> TextForSpeech.Profile = {
        profiles,
        replacement in
        try await profiles.replace(replacement)
    }
    let replaceStoredReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement, String) async throws -> TextForSpeech.Profile = {
        profiles,
        replacement,
        profileID in
        try await profiles.replace(replacement, inStoredProfileID: profileID)
    }
    let removeActiveReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> TextForSpeech.Profile = {
        profiles,
        replacementID in
        try await profiles.removeReplacement(id: replacementID)
    }
    let removeStoredReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, String, String) async throws -> TextForSpeech.Profile = {
        profiles,
        replacementID,
        profileID in
        try await profiles.removeReplacement(id: replacementID, fromStoredProfileID: profileID)
    }
    let clearActiveReplacements: @Sendable (SpeakSwiftly.Normalizer.Profiles) async throws -> TextForSpeech.Profile = { profiles in
        try await profiles.clearReplacements()
    }
    let clearStoredReplacements: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> TextForSpeech.Profile = { profiles, profileID in
        try await profiles.clearReplacements(fromStoredProfileID: profileID)
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
    let renameProfile: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name, SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle = {
        voices,
        profileName,
        newProfileName in
        await voices.rename(profileName, to: newProfileName)
    }
    let rerollProfile: @Sendable (SpeakSwiftly.Voices, SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle = {
        voices,
        profileName in
        await voices.reroll(profileName)
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
    let overview: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RequestHandle = { runtime in
        await runtime.overview()
    }
    let requestSnapshot: @Sendable (SpeakSwiftly.Runtime, String) async -> SpeakSwiftly.RequestSnapshot? = { runtime, requestID in
        await runtime.request(id: requestID)
    }
    let updates: @Sendable (SpeakSwiftly.Runtime, String) async -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error> = {
        runtime,
        requestID in
        await runtime.updates(for: requestID)
    }
    let generationEvents: @Sendable (SpeakSwiftly.Runtime, String) async -> AsyncThrowingStream<SpeakSwiftly.GenerationEventUpdate, any Swift.Error> = {
        runtime,
        requestID in
        await runtime.generationEvents(for: requestID)
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
    _ = profilesHandle
    _ = persistenceHandle
    _ = makeNormalizer
    _ = liftoffWithDefaults
    _ = liftoffWithConfiguration
    _ = createProfile
    _ = createClone
    _ = profiles
    _ = renameProfile
    _ = rerollProfile
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
    _ = effectiveProfile
    _ = activeReplacements
    _ = storedReplacements
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
    _ = clearActiveReplacements
    _ = clearStoredReplacements
    _ = generationQueue
    _ = status
    _ = overview
    _ = requestSnapshot
    _ = updates
    _ = generationEvents
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
    let generationEvents: KeyPath<SpeakSwiftly.RequestHandle, AsyncThrowingStream<SpeakSwiftly.GenerationEventUpdate, any Swift.Error>> = \.generationEvents

    _ = operation
    _ = profileName
    _ = events
    _ = generationEvents
}

@Test func publicRequestObservationSurfaceExposesStableMetadata() {
    let generationInfoPromptTokenCount: KeyPath<SpeakSwiftly.GenerationEventInfo, Int> = \.promptTokenCount
    let generationInfoGenerationTokenCount: KeyPath<SpeakSwiftly.GenerationEventInfo, Int> = \.generationTokenCount
    let generationInfoPrefillTime: KeyPath<SpeakSwiftly.GenerationEventInfo, TimeInterval> = \.prefillTime
    let generationInfoGenerateTime: KeyPath<SpeakSwiftly.GenerationEventInfo, TimeInterval> = \.generateTime
    let generationInfoTokensPerSecond: KeyPath<SpeakSwiftly.GenerationEventInfo, Double> = \.tokensPerSecond
    let generationInfoPeakMemoryUsage: KeyPath<SpeakSwiftly.GenerationEventInfo, Double> = \.peakMemoryUsage
    let generationUpdateID: KeyPath<SpeakSwiftly.GenerationEventUpdate, String> = \.id
    let generationUpdateSequence: KeyPath<SpeakSwiftly.GenerationEventUpdate, Int> = \.sequence
    let generationUpdateDate: KeyPath<SpeakSwiftly.GenerationEventUpdate, Date> = \.date
    let generationUpdateEvent: KeyPath<SpeakSwiftly.GenerationEventUpdate, SpeakSwiftly.GenerationEvent> = \.event
    let updateID: KeyPath<SpeakSwiftly.RequestUpdate, String> = \.id
    let updateSequence: KeyPath<SpeakSwiftly.RequestUpdate, Int> = \.sequence
    let updateDate: KeyPath<SpeakSwiftly.RequestUpdate, Date> = \.date
    let updateState: KeyPath<SpeakSwiftly.RequestUpdate, SpeakSwiftly.RequestState> = \.state
    let snapshotID: KeyPath<SpeakSwiftly.RequestSnapshot, String> = \.id
    let snapshotOperation: KeyPath<SpeakSwiftly.RequestSnapshot, String> = \.operation
    let snapshotProfileName: KeyPath<SpeakSwiftly.RequestSnapshot, String?> = \.profileName
    let snapshotAcceptedAt: KeyPath<SpeakSwiftly.RequestSnapshot, Date> = \.acceptedAt
    let snapshotLastUpdatedAt: KeyPath<SpeakSwiftly.RequestSnapshot, Date> = \.lastUpdatedAt
    let snapshotSequence: KeyPath<SpeakSwiftly.RequestSnapshot, Int> = \.sequence
    let snapshotState: KeyPath<SpeakSwiftly.RequestSnapshot, SpeakSwiftly.RequestState> = \.state

    _ = generationInfoPromptTokenCount
    _ = generationInfoGenerationTokenCount
    _ = generationInfoPrefillTime
    _ = generationInfoGenerateTime
    _ = generationInfoTokensPerSecond
    _ = generationInfoPeakMemoryUsage
    _ = generationUpdateID
    _ = generationUpdateSequence
    _ = generationUpdateDate
    _ = generationUpdateEvent
    _ = updateID
    _ = updateSequence
    _ = updateDate
    _ = updateState
    _ = snapshotID
    _ = snapshotOperation
    _ = snapshotProfileName
    _ = snapshotAcceptedAt
    _ = snapshotLastUpdatedAt
    _ = snapshotSequence
    _ = snapshotState
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

@Test func publicTextNormalizationSurfaceExposesReplacementMetadata() {
    let successReplacements: KeyPath<SpeakSwiftly.Success, [TextForSpeech.Replacement]?> = \.replacements

    _ = successReplacements
}
