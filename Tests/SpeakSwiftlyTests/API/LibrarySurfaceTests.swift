import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Runtime Construction

@Test func `public library surface constructs runtime from liftoff`() async {
    _ = await SpeakSwiftly.liftoff()
}

@Test func `public library surface constructs top level normalizer`() throws {
    let persistenceURL = URL(fileURLWithPath: "/tmp/speakswiftly-test-profiles.json")
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
    _ = normalizer
}

@Test func `public request context aliases the TextForSpeech model`() throws {
    let requestContext = SpeakSwiftly.RequestContext(
        source: "codex",
        app: "SpeakSwiftlyServer",
        project: "SpeakSwiftly",
        attributes: ["surface": "mcp"],
    )
    let encoded = try JSONEncoder().encode(requestContext)
    let decoded = try JSONDecoder().decode(TextForSpeech.RequestContext.self, from: encoded)

    #expect(decoded == requestContext)
    #expect(decoded.attributes == ["surface": "mcp"])
}

@Test func `public library surface constructs configuration`() {
    let configuration = SpeakSwiftly.Configuration(
        speechBackend: .marvis,
        qwenConditioningStrategy: .preparedConditioning,
    )
    #expect(configuration.speechBackend == .marvis)
    #expect(configuration.qwenConditioningStrategy == .preparedConditioning)
    #expect(configuration.qwenResidentModel == .base06B8Bit)
    #expect(configuration.marvisResidentPolicy == .dualResidentSerialized)
    #expect(configuration.textNormalizer == nil)
}

@Test func `public configuration defaults qwen to prepared conditioning`() {
    let configuration = SpeakSwiftly.Configuration()

    #expect(configuration.speechBackend == .qwen3)
    #expect(configuration.qwenConditioningStrategy == .preparedConditioning)
    #expect(configuration.qwenResidentModel == .base06B8Bit)
    #expect(configuration.marvisResidentPolicy == .dualResidentSerialized)
}

@Test func `public configuration supports chatterbox turbo backend`() {
    let configuration = SpeakSwiftly.Configuration(speechBackend: .chatterboxTurbo)

    #expect(configuration.speechBackend == .chatterboxTurbo)
    #expect(configuration.qwenConditioningStrategy == .preparedConditioning)
    #expect(configuration.qwenResidentModel == .base06B8Bit)
    #expect(configuration.marvisResidentPolicy == .dualResidentSerialized)
}

@Test func `public configuration round trips to disk`() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let persistenceURL = rootURL.appendingPathComponent("configuration.json")
    let configuration = SpeakSwiftly.Configuration(
        speechBackend: .marvis,
        qwenConditioningStrategy: .preparedConditioning,
        qwenResidentModel: .base17B8Bit,
        marvisResidentPolicy: .singleResidentDynamic,
    )

    try configuration.save(to: persistenceURL)
    let loaded = try SpeakSwiftly.Configuration.load(from: persistenceURL)

    #expect(loaded.speechBackend == configuration.speechBackend)
    #expect(loaded.qwenConditioningStrategy == configuration.qwenConditioningStrategy)
    #expect(loaded.qwenResidentModel == configuration.qwenResidentModel)
    #expect(loaded.marvisResidentPolicy == configuration.marvisResidentPolicy)
    #expect(loaded.textNormalizer == nil)
}

@Test func `public configuration load throws typed error when file is missing`() throws {
    let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("missing-configuration.json")

    #expect(throws: SpeakSwiftly.Configuration.LoadError.self) {
        try SpeakSwiftly.Configuration.load(from: missingURL)
    }
}

@Test func `public configuration normalizes the legacy qwen custom voice backend`() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let persistenceURL = rootURL.appendingPathComponent("configuration.json")
    let legacyConfigurationJSON = """
    {
      "qwenConditioningStrategy" : "legacy_raw",
      "speechBackend" : "qwen3_custom_voice"
    }
    """

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try Data(legacyConfigurationJSON.utf8).write(to: persistenceURL, options: .atomic)

    let loaded = try SpeakSwiftly.Configuration.load(from: persistenceURL)

    #expect(loaded.speechBackend == .qwen3)
    #expect(loaded.qwenConditioningStrategy == .legacyRaw)
    #expect(loaded.qwenResidentModel == .base06B8Bit)
    #expect(loaded.marvisResidentPolicy == .dualResidentSerialized)
}

@Test func `public configuration can carry A text normalizer`() throws {
    let normalizer = try SpeakSwiftly.Normalizer()
    let configuration = SpeakSwiftly.Configuration(
        speechBackend: .marvis,
        qwenConditioningStrategy: .legacyRaw,
        marvisResidentPolicy: .singleResidentDynamic,
        textNormalizer: normalizer,
    )

    #expect(configuration.speechBackend == .marvis)
    #expect(configuration.qwenConditioningStrategy == .legacyRaw)
    #expect(configuration.qwenResidentModel == .base06B8Bit)
    #expect(configuration.marvisResidentPolicy == .singleResidentDynamic)
    #expect(configuration.textNormalizer != nil)
}

@Test func `default package persistence paths use the debug namespace outside production`() async throws {
    let rootURL = ProfileStore.defaultRootURL()
    let configurationURL = ProfileStore.defaultConfigurationURL()
    let textProfilesURL = ProfileStore.defaultTextProfilesURL()
    let normalizer = try SpeakSwiftly.Normalizer()

    #expect(rootURL.path.contains("/SpeakSwiftly-Debug/profiles"))
    #expect(configurationURL.path.contains("/SpeakSwiftly-Debug/configuration.json"))
    #expect(textProfilesURL.path.contains("/SpeakSwiftly-Debug/text-profiles.json"))
    #expect(await (normalizer.persistence.url())?.lastPathComponent == "text-profiles.json")
}

@Test func `public normalizer default persistence honors profile root override`() async throws {
    let overrideRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: overrideRoot) }

    let environmentVariable = ProfileStore.profileRootOverrideEnvironmentVariable
    let previousValue = ProcessInfo.processInfo.environment[environmentVariable]
    setenv(environmentVariable, overrideRoot.path, 1)
    defer {
        if let previousValue {
            setenv(environmentVariable, previousValue, 1)
        } else {
            unsetenv(environmentVariable)
        }
    }

    let normalizer = try SpeakSwiftly.Normalizer()
    let expectedURL = overrideRoot.appendingPathComponent("text-profiles.json", isDirectory: false)

    #expect(await normalizer.persistence.url()?.standardizedFileURL == expectedURL.standardizedFileURL)
}

@Test func `liftoff normalizer persistence matches the default text profile path`() async {
    let overrideRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: overrideRoot) }

    let environmentVariable = ProfileStore.profileRootOverrideEnvironmentVariable
    let previousValue = ProcessInfo.processInfo.environment[environmentVariable]
    setenv(environmentVariable, overrideRoot.path, 1)
    defer {
        if let previousValue {
            setenv(environmentVariable, previousValue, 1)
        } else {
            unsetenv(environmentVariable)
        }
    }

    let runtime = await SpeakSwiftly.liftoff()
    let expectedURL = ProfileStore.defaultTextProfilesURL(
        fileManager: .default,
        profileRootOverride: overrideRoot.path,
    )

    #expect(await (runtime.normalizer.persistence.url())?.lastPathComponent == expectedURL.lastPathComponent)
}

// MARK: - Runtime Helpers

@Test func `public library surface exposes queueing helpers`() {
    let speak: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, SpeakSwiftly.TextProfileID?, SpeakSwiftly.InputTextContext?) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfile,
        inputTextContext in
        await generate.speech(
            text: text,
            voiceProfile: profileName,
            textProfile: textProfile,
            inputTextContext: inputTextContext,
        )
    }
    let generateAudio: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, SpeakSwiftly.TextProfileID?, SpeakSwiftly.InputTextContext?) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfile,
        inputTextContext in
        await generate.audio(
            text: text,
            voiceProfile: profileName,
            textProfile: textProfile,
            inputTextContext: inputTextContext,
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
    let styleHandle: @Sendable (SpeakSwiftly.Normalizer) -> SpeakSwiftly.Normalizer.Style = { normalizer in
        normalizer.style
    }
    let persistenceHandle: @Sendable (SpeakSwiftly.Normalizer) -> SpeakSwiftly.Normalizer.Persistence = { normalizer in
        normalizer.persistence
    }
    let makeNormalizer: @Sendable (TextForSpeech.BuiltInProfileStyle, URL?, TextForSpeech.PersistedState?) throws -> SpeakSwiftly.Normalizer = {
        builtInStyle,
        persistenceURL,
        state in
        try SpeakSwiftly.Normalizer(
            builtInStyle: builtInStyle,
            persistenceURL: persistenceURL,
            state: state,
        )
    }
    let liftoffWithDefaults: @Sendable () async -> SpeakSwiftly.Runtime = {
        await SpeakSwiftly.liftoff()
    }
    let liftoffWithConfiguration: @Sendable (SpeakSwiftly.Configuration) async -> SpeakSwiftly.Runtime = { configuration in
        await SpeakSwiftly.liftoff(configuration: configuration)
    }
    let activeStyle: @Sendable (SpeakSwiftly.Normalizer.Style) async -> TextForSpeech.BuiltInProfileStyle = { style in
        await style.getActive()
    }
    let styleOptions: @Sendable (SpeakSwiftly.Normalizer.Style) async -> [SpeakSwiftly.TextProfileStyleOption] = { style in
        await style.list()
    }
    let setActiveStyle: @Sendable (SpeakSwiftly.Normalizer.Style, TextForSpeech.BuiltInProfileStyle) async throws -> Void = {
        style,
        builtInStyle in
        try await style.setActive(to: builtInStyle)
    }
    let profile: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        id in
        try await profiles.get(id: id)
    }
    let profilesList: @Sendable (SpeakSwiftly.Normalizer.Profiles) async -> [SpeakSwiftly.TextProfileSummary] = { profiles in
        await profiles.list()
    }
    let activeProfile: @Sendable (SpeakSwiftly.Normalizer.Profiles) async -> SpeakSwiftly.TextProfileDetails = { profiles in
        await profiles.getActive()
    }
    let effectiveProfile: @Sendable (SpeakSwiftly.Normalizer.Profiles) async -> SpeakSwiftly.TextProfileDetails = { profiles in
        await profiles.getEffective()
    }
    let loadProfiles: @Sendable (SpeakSwiftly.Normalizer.Persistence) async throws -> Void = { persistence in
        try await persistence.load()
    }
    let saveProfiles: @Sendable (SpeakSwiftly.Normalizer.Persistence) async throws -> Void = { persistence in
        try await persistence.save()
    }
    let createProfileObject: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        name in
        try await profiles.create(name: name)
    }
    let removeProfileObject: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> Void = { profiles, id in
        try await profiles.delete(id: id)
    }
    let renameProfileObject: @Sendable (SpeakSwiftly.Normalizer.Profiles, String, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        id,
        name in
        try await profiles.rename(profile: id, to: name)
    }
    let setActiveProfileObject: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> Void = { profiles, id in
        try await profiles.setActive(id: id)
    }
    let factoryReset: @Sendable (SpeakSwiftly.Normalizer.Profiles) async throws -> Void = { profiles in
        try await profiles.factoryReset()
    }
    let reset: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> Void = { profiles, id in
        try await profiles.reset(id: id)
    }
    let addActiveReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        replacement in
        try await profiles.addReplacement(replacement)
    }
    let addStoredReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        replacement,
        profileID in
        try await profiles.addReplacement(replacement, toProfile: profileID)
    }
    let replaceActiveReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        replacement in
        try await profiles.patchReplacement(replacement)
    }
    let replaceStoredReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, TextForSpeech.Replacement, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        replacement,
        profileID in
        try await profiles.patchReplacement(replacement, inProfile: profileID)
    }
    let removeActiveReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        replacementID in
        try await profiles.removeReplacement(id: replacementID)
    }
    let removeStoredReplacement: @Sendable (SpeakSwiftly.Normalizer.Profiles, String, String) async throws -> SpeakSwiftly.TextProfileDetails = {
        profiles,
        replacementID,
        profileID in
        try await profiles.removeReplacement(id: replacementID, fromProfile: profileID)
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
            outputPath: outputPath,
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
            transcript: transcript,
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
        await generate.batch(items, voiceProfile: profileName)
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
    let clearGenerationQueue: @Sendable (SpeakSwiftly.Jobs) async -> SpeakSwiftly.RequestHandle = { jobs in
        await jobs.clearQueue()
    }
    let cancelGeneration: @Sendable (SpeakSwiftly.Jobs, String) async -> SpeakSwiftly.RequestHandle = { jobs, requestID in
        await jobs.cancel(requestID)
    }
    let clearRuntimeQueue: @Sendable (SpeakSwiftly.Runtime, SpeakSwiftly.QueueType) async -> SpeakSwiftly.RequestHandle = {
        runtime,
        queueType in
        await runtime.clearQueue(queueType)
    }
    let cancelRuntimeQueue: @Sendable (SpeakSwiftly.Runtime, SpeakSwiftly.QueueType, String) async -> SpeakSwiftly.RequestHandle = {
        runtime,
        queueType,
        requestID in
        await runtime.cancel(queueType, requestID: requestID)
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
    _ = styleHandle
    _ = persistenceHandle
    _ = makeNormalizer
    _ = liftoffWithDefaults
    _ = liftoffWithConfiguration
    _ = activeStyle
    _ = styleOptions
    _ = setActiveStyle
    _ = createProfile
    _ = createClone
    _ = profiles
    _ = renameProfile
    _ = rerollProfile
    _ = removeProfile
    _ = generatedFile
    _ = generatedFiles
    _ = generateBatch
    _ = expireGenerationJob
    _ = generationJob
    _ = generationJobs
    _ = profile
    _ = profilesList
    _ = activeProfile
    _ = effectiveProfile
    _ = loadProfiles
    _ = saveProfiles
    _ = createProfileObject
    _ = removeProfileObject
    _ = renameProfileObject
    _ = setActiveProfileObject
    _ = factoryReset
    _ = reset
    _ = addActiveReplacement
    _ = addStoredReplacement
    _ = replaceActiveReplacement
    _ = replaceStoredReplacement
    _ = removeActiveReplacement
    _ = removeStoredReplacement
    _ = generationQueue
    _ = status
    _ = overview
    _ = requestSnapshot
    _ = updates
    _ = generationEvents
    _ = clearGenerationQueue
    _ = cancelGeneration
    _ = clearRuntimeQueue
    _ = cancelRuntimeQueue
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

@Test func `public worker request handle exposes stable metadata`() {
    let kind: KeyPath<SpeakSwiftly.RequestHandle, SpeakSwiftly.RequestKind> = \.kind
    let voiceProfile: KeyPath<SpeakSwiftly.RequestHandle, String?> = \.voiceProfile
    let events: KeyPath<SpeakSwiftly.RequestHandle, AsyncThrowingStream<SpeakSwiftly.RequestEvent, any Swift.Error>> = \.events
    let generationEvents: KeyPath<SpeakSwiftly.RequestHandle, AsyncThrowingStream<SpeakSwiftly.GenerationEventUpdate, any Swift.Error>> = \.generationEvents

    _ = kind
    _ = voiceProfile
    _ = events
    _ = generationEvents
}

@Test func `public request observation surface exposes stable metadata`() {
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
    let snapshotKind: KeyPath<SpeakSwiftly.RequestSnapshot, SpeakSwiftly.RequestKind> = \.kind
    let snapshotVoiceProfile: KeyPath<SpeakSwiftly.RequestSnapshot, String?> = \.voiceProfile
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
    _ = snapshotKind
    _ = snapshotVoiceProfile
    _ = snapshotAcceptedAt
    _ = snapshotLastUpdatedAt
    _ = snapshotSequence
    _ = snapshotState
}

@Test func `public generated file surface exposes stable metadata`() {
    let artifactID: KeyPath<SpeakSwiftly.GeneratedFile, String> = \.artifactID
    let createdAt: KeyPath<SpeakSwiftly.GeneratedFile, Date> = \.createdAt
    let voiceProfile: KeyPath<SpeakSwiftly.GeneratedFile, String> = \.voiceProfile
    let textProfile: KeyPath<SpeakSwiftly.GeneratedFile, String?> = \.textProfile
    let sampleRate: KeyPath<SpeakSwiftly.GeneratedFile, Int> = \.sampleRate
    let filePath: KeyPath<SpeakSwiftly.GeneratedFile, String> = \.filePath

    _ = artifactID
    _ = createdAt
    _ = voiceProfile
    _ = textProfile
    _ = sampleRate
    _ = filePath
}

@Test func `public status surface exposes stable metadata`() {
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

@Test func `public text normalization surface exposes profile metadata`() {
    let successTextProfile: KeyPath<SpeakSwiftly.Success, SpeakSwiftly.TextProfileDetails?> = \.textProfile
    let successTextProfiles: KeyPath<SpeakSwiftly.Success, [SpeakSwiftly.TextProfileSummary]?> = \.textProfiles
    let successTextProfileStyleOptions: KeyPath<SpeakSwiftly.Success, [SpeakSwiftly.TextProfileStyleOption]?> = \.textProfileStyleOptions
    let textProfileID: KeyPath<SpeakSwiftly.TextProfileDetails, String> = \.profileID
    let textProfileSummary: KeyPath<SpeakSwiftly.TextProfileDetails, SpeakSwiftly.TextProfileSummary> = \.summary
    let textProfileReplacements: KeyPath<SpeakSwiftly.TextProfileDetails, [TextForSpeech.Replacement]> = \.replacements
    let textProfileSummaryID: KeyPath<SpeakSwiftly.TextProfileSummary, String> = \.id
    let textProfileSummaryName: KeyPath<SpeakSwiftly.TextProfileSummary, String> = \.name
    let textProfileSummaryReplacementCount: KeyPath<SpeakSwiftly.TextProfileSummary, Int> = \.replacementCount
    let textProfileStyle: KeyPath<SpeakSwiftly.TextProfileStyleOption, TextForSpeech.BuiltInProfileStyle> = \.style
    let textProfileStyleSummary: KeyPath<SpeakSwiftly.TextProfileStyleOption, String> = \.summary

    _ = successTextProfile
    _ = successTextProfiles
    _ = successTextProfileStyleOptions
    _ = textProfileID
    _ = textProfileSummary
    _ = textProfileReplacements
    _ = textProfileSummaryID
    _ = textProfileSummaryName
    _ = textProfileSummaryReplacementCount
    _ = textProfileStyle
    _ = textProfileStyleSummary
}
