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
        topic: "runtime",
        attributes: ["surface": "mcp"],
    )
    let encoded = try JSONEncoder().encode(requestContext)
    let decoded = try JSONDecoder().decode(TextForSpeech.RequestContext.self, from: encoded)

    #expect(decoded == requestContext)
    #expect(decoded.source == "codex")
    #expect(decoded.topic == "runtime")
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
    #expect(configuration.defaultVoiceProfile == SpeakSwiftly.DefaultVoiceProfiles.signal)
    #expect(configuration.textNormalizer == nil)
}

@Test func `public configuration defaults qwen to prepared conditioning`() {
    let configuration = SpeakSwiftly.Configuration()

    #expect(configuration.speechBackend == .qwen3)
    #expect(configuration.qwenConditioningStrategy == .preparedConditioning)
    #expect(configuration.qwenResidentModel == .base06B8Bit)
    #expect(configuration.marvisResidentPolicy == .dualResidentSerialized)
    #expect(configuration.defaultVoiceProfile == SpeakSwiftly.DefaultVoiceProfiles.signal)
}

@Test func `public configuration supports chatterbox turbo backend`() {
    let configuration = SpeakSwiftly.Configuration(speechBackend: .chatterboxTurbo)

    #expect(configuration.speechBackend == .chatterboxTurbo)
    #expect(configuration.qwenConditioningStrategy == .preparedConditioning)
    #expect(configuration.qwenResidentModel == .base06B8Bit)
    #expect(configuration.marvisResidentPolicy == .dualResidentSerialized)
    #expect(configuration.defaultVoiceProfile == SpeakSwiftly.DefaultVoiceProfiles.signal)
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
        defaultVoiceProfile: SpeakSwiftly.DefaultVoiceProfiles.anchor,
    )

    try configuration.save(to: persistenceURL)
    let loaded = try SpeakSwiftly.Configuration.load(from: persistenceURL)

    #expect(loaded.speechBackend == configuration.speechBackend)
    #expect(loaded.qwenConditioningStrategy == configuration.qwenConditioningStrategy)
    #expect(loaded.qwenResidentModel == configuration.qwenResidentModel)
    #expect(loaded.marvisResidentPolicy == configuration.marvisResidentPolicy)
    #expect(loaded.defaultVoiceProfile == configuration.defaultVoiceProfile)
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
    #expect(loaded.defaultVoiceProfile == SpeakSwiftly.DefaultVoiceProfiles.signal)
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

@Test func `public normalizer default persistence honors state root override`() async throws {
    let overrideRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: overrideRoot) }

    let environmentVariable = ProfileStore.runtimeStateRootOverrideEnvironmentVariable
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

@Test func `liftoff state root parameter drives runtime persistence without environment`() async {
    let overrideRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: overrideRoot) }

    let runtime = await SpeakSwiftly.liftoff(stateRootURL: overrideRoot)
    let expectedURL = ProfileStore.defaultTextProfilesURL(
        fileManager: .default,
        stateRootOverride: overrideRoot.path,
    )

    #expect(await (runtime.normalizer.persistence.url())?.lastPathComponent == expectedURL.lastPathComponent)
}

@Test func `liftoff state root parameter preserves persisted configuration`() async throws {
    let stateRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: stateRoot) }

    try SpeakSwiftly.Configuration(speechBackend: .marvis).saveDefault(
        stateRootOverride: stateRoot.path,
    )

    let runtime = await SpeakSwiftly.liftoff(stateRootURL: stateRoot)

    #expect(await runtime.speechBackend == .marvis)
}

// MARK: - Runtime Helpers

@Test func `public library surface exposes queueing helpers`() {
    let speak: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, SpeakSwiftly.TextProfileID?, TextForSpeech.SourceFormat?) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfile,
        sourceFormat in
        await generate.speech(
            text: text,
            voiceProfile: profileName,
            textProfile: textProfile,
            sourceFormat: sourceFormat,
        )
    }
    let speakWithDefaultVoice: @Sendable (SpeakSwiftly.Generate, String) async -> SpeakSwiftly.RequestHandle = { generate, text in
        await generate.speech(text: text)
    }
    let generateAudio: @Sendable (SpeakSwiftly.Generate, String, SpeakSwiftly.Name, SpeakSwiftly.TextProfileID?, TextForSpeech.SourceFormat?) async -> SpeakSwiftly.RequestHandle = {
        generate,
        text,
        profileName,
        textProfile,
        sourceFormat in
        await generate.audio(
            text: text,
            voiceProfile: profileName,
            textProfile: textProfile,
            sourceFormat: sourceFormat,
        )
    }
    let generateAudioWithDefaultVoice: @Sendable (SpeakSwiftly.Generate, String) async -> SpeakSwiftly.RequestHandle = { generate, text in
        await generate.audio(text: text)
    }
    let generateHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Generate = { runtime in
        runtime.generate
    }
    let playbackHandle: @Sendable (SpeakSwiftly.Runtime) -> SpeakSwiftly.Playback = { runtime in
        runtime.playback
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
    let liftoffWithStateRoot: @Sendable (URL) async -> SpeakSwiftly.Runtime = { stateRootURL in
        await SpeakSwiftly.liftoff(stateRootURL: stateRootURL)
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
            voiceDescription: voiceDescription,
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
    let generatedFile: @Sendable (SpeakSwiftly.Runtime, String) async -> SpeakSwiftly.RequestHandle = { runtime, artifactID in
        await runtime.artifact(id: artifactID)
    }
    let generatedFiles: @Sendable (SpeakSwiftly.Artifacts) async -> SpeakSwiftly.RequestHandle = { artifacts in
        await artifacts()
    }
    let generatedFilesList: @Sendable (SpeakSwiftly.Artifacts) async -> SpeakSwiftly.RequestHandle = { artifacts in
        await artifacts.list()
    }
    let generateBatch: @Sendable (SpeakSwiftly.Generate, [SpeakSwiftly.BatchItem], SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle = {
        generate,
        items,
        profileName in
        await generate.batch(items, voiceProfile: profileName)
    }
    let generateBatchWithDefaultVoice: @Sendable (SpeakSwiftly.Generate, [SpeakSwiftly.BatchItem]) async -> SpeakSwiftly.RequestHandle = { generate, items in
        await generate.batch(items)
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
    let runtimeUpdates: @Sendable (SpeakSwiftly.Runtime) async -> AsyncStream<SpeakSwiftly.RuntimeUpdate> = { runtime in
        await runtime.updates()
    }
    let runtimeSnapshot: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.RuntimeSnapshot = { runtime in
        await runtime.snapshot()
    }
    let generateUpdates: @Sendable (SpeakSwiftly.Generate) async -> AsyncStream<SpeakSwiftly.GenerateUpdate> = { generate in
        await generate.updates()
    }
    let generateSnapshot: @Sendable (SpeakSwiftly.Generate) async -> SpeakSwiftly.GenerateSnapshot = { generate in
        await generate.snapshot()
    }
    let defaultVoiceProfile: @Sendable (SpeakSwiftly.Runtime) async -> SpeakSwiftly.Name = { runtime in
        await runtime.defaultVoiceProfile
    }
    let setDefaultVoiceProfile: @Sendable (SpeakSwiftly.Runtime, SpeakSwiftly.Name) async throws -> Void = { runtime, profileName in
        try await runtime.setDefaultVoiceProfile(profileName)
    }
    let requestSnapshot: @Sendable (SpeakSwiftly.Runtime, String) async -> SpeakSwiftly.RequestSnapshot? = { runtime, requestID in
        await runtime.request(id: requestID)
    }
    let updates: @Sendable (SpeakSwiftly.Runtime, String) async -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error> = {
        runtime,
        requestID in
        await runtime.updates(for: requestID)
    }
    let synthesisUpdates: @Sendable (SpeakSwiftly.Runtime, String) async -> AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error> = {
        runtime,
        requestID in
        await runtime.synthesisUpdates(for: requestID)
    }
    let completion: @Sendable (SpeakSwiftly.RequestHandle) async throws -> SpeakSwiftly.RequestCompletion = { handle in
        try await handle.completion()
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
    let playbackUpdates: @Sendable (SpeakSwiftly.Playback) async -> AsyncStream<SpeakSwiftly.PlaybackUpdate> = { playback in
        await playback.updates()
    }
    let playbackSnapshot: @Sendable (SpeakSwiftly.Playback) async -> SpeakSwiftly.PlaybackSnapshot = { playback in
        await playback.snapshot()
    }
    let playbackPause: @Sendable (SpeakSwiftly.Playback) async -> SpeakSwiftly.RequestHandle = { playback in
        await playback.pause()
    }
    let clearQueue: @Sendable (SpeakSwiftly.Playback) async -> SpeakSwiftly.RequestHandle = { playback in
        await playback.clearQueue()
    }
    let cancelRequest: @Sendable (SpeakSwiftly.Playback, String) async -> SpeakSwiftly.RequestHandle = { playback, requestID in
        await playback.cancelRequest(requestID)
    }

    _ = speak
    _ = speakWithDefaultVoice
    _ = generateAudio
    _ = generateAudioWithDefaultVoice
    _ = generateHandle
    _ = playbackHandle
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
    _ = liftoffWithStateRoot
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
    _ = generatedFilesList
    _ = generateBatch
    _ = generateBatchWithDefaultVoice
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
    _ = runtimeUpdates
    _ = runtimeSnapshot
    _ = generateUpdates
    _ = generateSnapshot
    _ = defaultVoiceProfile
    _ = setDefaultVoiceProfile
    _ = requestSnapshot
    _ = updates
    _ = synthesisUpdates
    _ = completion
    _ = clearGenerationQueue
    _ = cancelGeneration
    _ = clearRuntimeQueue
    _ = cancelRuntimeQueue
    _ = switchSpeechBackend
    _ = reloadModels
    _ = unloadModels
    _ = playbackUpdates
    _ = playbackSnapshot
    _ = playbackPause
    _ = clearQueue
    _ = cancelRequest
}

// MARK: - Handle Metadata

@Test func `public worker request handle exposes stable metadata`() {
    let kind: KeyPath<SpeakSwiftly.RequestHandle, SpeakSwiftly.RequestKind> = \.kind
    let voiceProfile: KeyPath<SpeakSwiftly.RequestHandle, String?> = \.voiceProfile
    let events: KeyPath<SpeakSwiftly.RequestHandle, AsyncThrowingStream<SpeakSwiftly.RequestEvent, any Swift.Error>> = \.events
    let synthesisUpdates: KeyPath<SpeakSwiftly.RequestHandle, AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error>> = \.synthesisUpdates

    _ = kind
    _ = voiceProfile
    _ = events
    _ = synthesisUpdates
}

@Test func `public request observation surface exposes stable metadata`() {
    let generationInfoPromptTokenCount: KeyPath<SpeakSwiftly.SynthesisEventInfo, Int> = \.promptTokenCount
    let generationInfoGenerationTokenCount: KeyPath<SpeakSwiftly.SynthesisEventInfo, Int> = \.generationTokenCount
    let generationInfoPrefillTime: KeyPath<SpeakSwiftly.SynthesisEventInfo, TimeInterval> = \.prefillTime
    let generationInfoGenerateTime: KeyPath<SpeakSwiftly.SynthesisEventInfo, TimeInterval> = \.generateTime
    let generationInfoTokensPerSecond: KeyPath<SpeakSwiftly.SynthesisEventInfo, Double> = \.tokensPerSecond
    let generationInfoPeakMemoryUsage: KeyPath<SpeakSwiftly.SynthesisEventInfo, Double> = \.peakMemoryUsage
    let generationUpdateID: KeyPath<SpeakSwiftly.SynthesisUpdate, String> = \.id
    let generationUpdateSequence: KeyPath<SpeakSwiftly.SynthesisUpdate, Int> = \.sequence
    let generationUpdateDate: KeyPath<SpeakSwiftly.SynthesisUpdate, Date> = \.date
    let generationUpdateEvent: KeyPath<SpeakSwiftly.SynthesisUpdate, SpeakSwiftly.SynthesisEvent> = \.event
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

@Test func `public retained artifact surface exposes stable metadata`() {
    let artifactID: KeyPath<SpeakSwiftly.GenerationArtifact, String> = \.artifactID
    let kind: KeyPath<SpeakSwiftly.GenerationArtifact, SpeakSwiftly.GenerationArtifactKind> = \.kind
    let createdAt: KeyPath<SpeakSwiftly.GenerationArtifact, Date> = \.createdAt
    let filePath: KeyPath<SpeakSwiftly.GenerationArtifact, String> = \.filePath
    let sampleRate: KeyPath<SpeakSwiftly.GenerationArtifact, Int> = \.sampleRate
    let voiceProfile: KeyPath<SpeakSwiftly.GenerationArtifact, String> = \.voiceProfile
    let textProfile: KeyPath<SpeakSwiftly.GenerationArtifact, String?> = \.textProfile
    let sourceFormat: KeyPath<SpeakSwiftly.GenerationArtifact, TextForSpeech.SourceFormat?> = \.sourceFormat
    let requestContext: KeyPath<SpeakSwiftly.GenerationArtifact, SpeakSwiftly.RequestContext?> = \.requestContext

    _ = artifactID
    _ = kind
    _ = createdAt
    _ = filePath
    _ = sampleRate
    _ = voiceProfile
    _ = textProfile
    _ = sourceFormat
    _ = requestContext
}

@Test func `public generation job surface exposes stable metadata`() {
    let jobID: KeyPath<SpeakSwiftly.GenerationJob, String> = \.jobID
    let jobKind: KeyPath<SpeakSwiftly.GenerationJob, SpeakSwiftly.GenerationJobKind> = \.jobKind
    let createdAt: KeyPath<SpeakSwiftly.GenerationJob, Date> = \.createdAt
    let updatedAt: KeyPath<SpeakSwiftly.GenerationJob, Date> = \.updatedAt
    let voiceProfile: KeyPath<SpeakSwiftly.GenerationJob, String> = \.voiceProfile
    let textProfile: KeyPath<SpeakSwiftly.GenerationJob, String?> = \.textProfile
    let speechBackend: KeyPath<SpeakSwiftly.GenerationJob, SpeakSwiftly.SpeechBackend> = \.speechBackend
    let state: KeyPath<SpeakSwiftly.GenerationJob, SpeakSwiftly.GenerationJobState> = \.state
    let items: KeyPath<SpeakSwiftly.GenerationJob, [SpeakSwiftly.GenerationJobItem]> = \.items
    let artifacts: KeyPath<SpeakSwiftly.GenerationJob, [SpeakSwiftly.GenerationArtifact]> = \.artifacts
    let failure: KeyPath<SpeakSwiftly.GenerationJob, SpeakSwiftly.GenerationJobFailure?> = \.failure
    let retentionPolicy: KeyPath<SpeakSwiftly.GenerationJob, SpeakSwiftly.GenerationRetentionPolicy> = \.retentionPolicy

    _ = jobID
    _ = jobKind
    _ = createdAt
    _ = updatedAt
    _ = voiceProfile
    _ = textProfile
    _ = speechBackend
    _ = state
    _ = items
    _ = artifacts
    _ = failure
    _ = retentionPolicy
}

@Test func `public request kinds expose artifact names over worker compatibility strings`() {
    let generatedFileOperation = ["get", "generated", "file"].joined(separator: "_")
    let generatedFilesOperation = ["list", "generated", "files"].joined(separator: "_")

    #expect(SpeakSwiftly.RequestKind.getArtifact.rawValue == generatedFileOperation)
    #expect(SpeakSwiftly.RequestKind.listArtifacts.rawValue == generatedFilesOperation)
}

@Test func `public observation surfaces expose stable metadata`() {
    let generateUpdateSequence: KeyPath<SpeakSwiftly.GenerateUpdate, Int> = \.sequence
    let generateUpdateState: KeyPath<SpeakSwiftly.GenerateUpdate, SpeakSwiftly.GenerateState> = \.state
    let generateSnapshotActive: KeyPath<SpeakSwiftly.GenerateSnapshot, [SpeakSwiftly.ActiveRequest]> = \.activeRequests
    let generateSnapshotQueued: KeyPath<SpeakSwiftly.GenerateSnapshot, [SpeakSwiftly.QueuedRequest]> = \.queuedRequests
    let playbackUpdateSequence: KeyPath<SpeakSwiftly.PlaybackUpdate, Int> = \.sequence
    let playbackUpdateState: KeyPath<SpeakSwiftly.PlaybackUpdate, SpeakSwiftly.PlaybackState> = \.state
    let playbackSnapshotActive: KeyPath<SpeakSwiftly.PlaybackSnapshot, SpeakSwiftly.ActiveRequest?> = \.activeRequest
    let playbackSnapshotQueued: KeyPath<SpeakSwiftly.PlaybackSnapshot, [SpeakSwiftly.QueuedRequest]> = \.queuedRequests
    let runtimeUpdateSequence: KeyPath<SpeakSwiftly.RuntimeUpdate, Int> = \.sequence
    let runtimeUpdateState: KeyPath<SpeakSwiftly.RuntimeUpdate, SpeakSwiftly.RuntimeState> = \.state
    let runtimeSpeechBackend: KeyPath<SpeakSwiftly.RuntimeSnapshot, SpeakSwiftly.SpeechBackend> = \.speechBackend
    let runtimeResidentState: KeyPath<SpeakSwiftly.RuntimeSnapshot, SpeakSwiftly.ResidentModelState> = \.residentState
    let runtimeStorage: KeyPath<SpeakSwiftly.RuntimeSnapshot, SpeakSwiftly.RuntimeStorageSnapshot> = \.storage
    let stateRootPath: KeyPath<SpeakSwiftly.RuntimeStorageSnapshot, String> = \.stateRootPath
    let profileStoreRootPath: KeyPath<SpeakSwiftly.RuntimeStorageSnapshot, String> = \.profileStoreRootPath
    let configurationPath: KeyPath<SpeakSwiftly.RuntimeStorageSnapshot, String> = \.configurationPath
    let textProfilesPath: KeyPath<SpeakSwiftly.RuntimeStorageSnapshot, String> = \.textProfilesPath
    let generatedFilesRootPath: KeyPath<SpeakSwiftly.RuntimeStorageSnapshot, String> = \.generatedFilesRootPath
    let generationJobsRootPath: KeyPath<SpeakSwiftly.RuntimeStorageSnapshot, String> = \.generationJobsRootPath

    _ = generateUpdateSequence
    _ = generateUpdateState
    _ = generateSnapshotActive
    _ = generateSnapshotQueued
    _ = playbackUpdateSequence
    _ = playbackUpdateState
    _ = playbackSnapshotActive
    _ = playbackSnapshotQueued
    _ = runtimeUpdateSequence
    _ = runtimeUpdateState
    _ = runtimeSpeechBackend
    _ = runtimeResidentState
    _ = runtimeStorage
    _ = stateRootPath
    _ = profileStoreRootPath
    _ = configurationPath
    _ = textProfilesPath
    _ = generatedFilesRootPath
    _ = generationJobsRootPath
}

@Test func `public text normalization surface exposes profile metadata`() {
    let textProfileID: KeyPath<SpeakSwiftly.TextProfileDetails, String> = \.profileID
    let textProfileSummary: KeyPath<SpeakSwiftly.TextProfileDetails, SpeakSwiftly.TextProfileSummary> = \.summary
    let textProfileReplacements: KeyPath<SpeakSwiftly.TextProfileDetails, [TextForSpeech.Replacement]> = \.replacements
    let textProfileSummaryID: KeyPath<SpeakSwiftly.TextProfileSummary, String> = \.id
    let textProfileSummaryName: KeyPath<SpeakSwiftly.TextProfileSummary, String> = \.name
    let textProfileSummaryReplacementCount: KeyPath<SpeakSwiftly.TextProfileSummary, Int> = \.replacementCount
    let textProfileStyle: KeyPath<SpeakSwiftly.TextProfileStyleOption, TextForSpeech.BuiltInProfileStyle> = \.style
    let textProfileStyleSummary: KeyPath<SpeakSwiftly.TextProfileStyleOption, String> = \.summary

    _ = textProfileID
    _ = textProfileSummary
    _ = textProfileReplacements
    _ = textProfileSummaryID
    _ = textProfileSummaryName
    _ = textProfileSummaryReplacementCount
    _ = textProfileStyle
    _ = textProfileStyleSummary
}
