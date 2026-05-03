import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@testable import SpeakSwiftly
import Testing

// MARK: - Profile Lifecycle

@Test func `creates lists loads and removes profiles`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    let stored = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    #expect(stored.manifest.profileName == "default-femme")
    #expect(stored.manifest.vibe == .femme)
    #expect(stored.manifest.author == .user)
    #expect(stored.manifest.seed == nil)
    #expect(stored.manifest.transcriptProvenance == nil)
    #expect(stored.manifest.backendMaterializations.map(\.backend) == [.qwen3])
    #expect(try stored.qwenMaterialization().manifest.referenceText == "Hello there")

    let listed = try store.listProfiles()
    #expect(listed.count == 1)
    #expect(listed.first?.profileName == "default-femme")
    #expect(listed.first?.author == .user)
    #expect(listed.first?.seedID == nil)
    #expect(listed.first?.seedVersion == nil)
    #expect(listed.first?.transcriptSource == nil)
    #expect(listed.first?.transcriptResolvedAt == nil)
    #expect(listed.first?.transcriptionModelRepo == nil)

    let loaded = try store.loadProfile(named: "default-femme")
    #expect(loaded.manifest.sourceText == "Hello there")
    #expect(loaded.manifest.transcriptProvenance == nil)
    #expect(loaded.materializations.count == 1)
    #expect(try loaded.qwenMaterialization().manifest.referenceText == "Hello there")

    try store.removeProfile(named: "default-femme")
    let empty = try store.listProfiles()
    #expect(empty.isEmpty)
}

@Test func `concurrent create load and remove access stays consistent`() async throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let profileNames = (0..<6).map { "parallel-\($0)" }

    try await withThrowingTaskGroup(of: String.self) { group in
        for profileName in profileNames {
            group.addTask {
                try store.createProfile(
                    profileName: profileName,
                    vibe: .femme,
                    modelRepo: "test-model",
                    voiceDescription: "Parallel voice \(profileName).",
                    sourceText: "Parallel transcript \(profileName)",
                    sampleRate: 24000,
                    canonicalAudioData: Data([0x52, 0x49, 0x46, 0x46]),
                )
                .manifest
                .profileName
            }
        }

        var createdNames: [String] = []
        for try await profileName in group {
            createdNames.append(profileName)
        }

        #expect(createdNames.sorted() == profileNames)
    }

    #expect(try store.listProfiles().map(\.profileName) == profileNames)

    try await withThrowingTaskGroup(of: String.self) { group in
        for profileName in profileNames {
            group.addTask {
                try store.loadProfile(named: profileName).manifest.profileName
            }
        }

        var loadedNames: [String] = []
        for try await profileName in group {
            loadedNames.append(profileName)
        }

        #expect(loadedNames.sorted() == profileNames)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
        for profileName in profileNames {
            group.addTask {
                try store.removeProfile(named: profileName)
            }
        }

        try await group.waitForAll()
    }

    #expect(try store.listProfiles().isEmpty)
}

@Test func `concurrent duplicate creates publish one complete profile`() async throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)

    let outcomes = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
        for index in 0..<6 {
            group.addTask {
                do {
                    _ = try store.createProfile(
                        profileName: "shared",
                        vibe: .femme,
                        modelRepo: "test-model",
                        voiceDescription: "Shared voice \(index).",
                        sourceText: "Shared transcript \(index)",
                        sampleRate: 24000,
                        canonicalAudioData: Data([0x52, 0x49, 0x46, 0x46]),
                    )
                    return "created"
                } catch let error as WorkerError where error.code == .profileAlreadyExists {
                    return "already-exists"
                }
            }
        }

        var outcomes: [String] = []
        for try await outcome in group {
            outcomes.append(outcome)
        }

        return outcomes
    }

    #expect(outcomes.filter { $0 == "created" }.count == 1)
    #expect(outcomes.filter { $0 == "already-exists" }.count == 5)

    let profileDirectory = store.profileDirectoryURL(for: "shared")
    #expect(fileManager.fileExists(atPath: store.manifestURL(for: profileDirectory).path))
    #expect(fileManager.fileExists(atPath: store.referenceAudioURL(for: profileDirectory).path))
    #expect(try store.listProfiles().map(\.profileName) == ["shared"])
}

@Test func `stores and lists system profile authorship and seed metadata`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let installedAt = Date(timeIntervalSince1970: 1_777_728_000)
    let seed = SpeakSwiftly.ProfileSeed(
        seedID: "swift.signal",
        seedVersion: "1",
        intendedProfileName: "swift-signal",
        fallbackProfileName: nil,
        installedAt: installedAt,
        sourcePackage: "SpeakSwiftlyServer",
        sourceVersion: "4.2.0",
        sampleMediaPath: "Samples/swift-signal.wav",
    )

    let stored = try store.createProfile(
        profileName: "swift-signal",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Bright and clear.",
        sourceText: "Hello there",
        author: .system,
        seed: seed,
        sampleRate: 24000,
        canonicalAudioData: Data([0x52, 0x49, 0x46, 0x46]),
    )

    #expect(stored.manifest.author == .system)
    #expect(stored.manifest.seed == seed)

    let reloaded = try store.loadProfile(named: "swift-signal")
    #expect(reloaded.manifest.author == .system)
    #expect(reloaded.manifest.seed?.seedID == "swift.signal")
    #expect(reloaded.manifest.seed?.sampleMediaPath == "Samples/swift-signal.wav")

    let summary = try #require(try store.listProfiles().first)
    #expect(summary.profileName == "swift-signal")
    #expect(summary.author == .system)
    #expect(summary.seedID == "swift.signal")
    #expect(summary.seedVersion == "1")
}

@Test func `ordinary mutation rejects system profiles`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    _ = try store.createProfile(
        profileName: "swift-anchor",
        vibe: .masc,
        modelRepo: "test-model",
        voiceDescription: "Grounded and steady.",
        sourceText: "Hello there",
        author: .system,
        seed: SpeakSwiftly.ProfileSeed(
            seedID: "swift.anchor",
            seedVersion: "1",
            intendedProfileName: "swift-anchor",
            sourcePackage: "SpeakSwiftlyServer",
        ),
        sampleRate: 24000,
        canonicalAudioData: Data([0x52, 0x49, 0x46, 0x46]),
    )

    #expect(throws: WorkerError.self) {
        _ = try store.renameProfile(named: "swift-anchor", to: "renamed-anchor")
    }
    #expect(throws: WorkerError.self) {
        try store.removeProfile(named: "swift-anchor")
    }
    #expect(throws: WorkerError.self) {
        _ = try store.replaceProfile(
            named: "swift-anchor",
            vibe: .masc,
            modelRepo: "test-model",
            voiceDescription: "Grounded and steady.",
            sourceText: "Hello again",
            sampleRate: 24000,
            canonicalAudioData: Data([0x01]),
            createdAt: Date(),
        )
    }
}

@Test func `rejects duplicate profiles`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    _ = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    #expect(throws: WorkerError.self) {
        _ = try store.createProfile(
            profileName: "default-femme",
            vibe: .femme,
            modelRepo: "test-model",
            voiceDescription: "Duplicate",
            sourceText: "Hello again",
            sampleRate: 24000,
            canonicalAudioData: audioData,
        )
    }
}

@Test func `renames profiles and rewrites the stored manifest name`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    _ = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    let renamed = try store.renameProfile(named: "default-femme", to: "guide-femme")

    #expect(renamed.manifest.profileName == "guide-femme")
    #expect(renamed.directoryURL.lastPathComponent == "guide-femme")
    #expect(fileManager.fileExists(atPath: store.profileDirectoryURL(for: "guide-femme").path))
    #expect(!fileManager.fileExists(atPath: store.profileDirectoryURL(for: "default-femme").path))
    #expect(try store.loadProfile(named: "guide-femme").manifest.profileName == "guide-femme")
    #expect(throws: WorkerError.self) {
        _ = try store.loadProfile(named: "default-femme")
    }
}

@Test func `rename rejects an existing destination profile name`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    _ = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )
    _ = try store.createProfile(
        profileName: "default-masc",
        vibe: .masc,
        modelRepo: "test-model",
        voiceDescription: "Warm and low.",
        sourceText: "Hello again",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    #expect(throws: WorkerError.self) {
        _ = try store.renameProfile(named: "default-femme", to: "default-masc")
    }
}

// MARK: - Audio Export

@Test func `exports canonical audio without overwriting existing files`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01, 0x02, 0x03, 0x04])
    let stored = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    let exportURL = tempRoot.appendingPathComponent("exports/reference.wav")
    try store.exportCanonicalAudio(for: stored, to: exportURL)
    #expect(fileManager.fileExists(atPath: exportURL.path))
    #expect(try Data(contentsOf: exportURL) == audioData)

    #expect(throws: WorkerError.self) {
        try store.exportCanonicalAudio(for: stored, to: exportURL)
    }
}

@Test func `state root override accepts a base directory path`() {
    let overrideRoot = URL(fileURLWithPath: "/tmp/speakswiftly-override-root", isDirectory: true)

    #expect(ProfileStore.defaultRootURL(stateRootOverride: overrideRoot.path) == overrideRoot.appendingPathComponent("profiles", isDirectory: true))
    #expect(ProfileStore.defaultConfigurationURL(stateRootOverride: overrideRoot.path) == overrideRoot.appendingPathComponent("configuration.json", isDirectory: false))
    #expect(ProfileStore.defaultTextProfilesURL(stateRootOverride: overrideRoot.path) == overrideRoot.appendingPathComponent("text-profiles.json", isDirectory: false))
}

@Test func `state root override preserves a literal base directory named profiles`() {
    let overrideRoot = URL(fileURLWithPath: "/tmp/speakswiftly-override-root/profiles", isDirectory: true)

    #expect(ProfileStore.defaultRootURL(stateRootOverride: overrideRoot.path) == overrideRoot.appendingPathComponent("profiles", isDirectory: true))
    #expect(ProfileStore.defaultConfigurationURL(stateRootOverride: overrideRoot.path) == overrideRoot.appendingPathComponent("configuration.json", isDirectory: false))
    #expect(ProfileStore.defaultTextProfilesURL(stateRootOverride: overrideRoot.path) == overrideRoot.appendingPathComponent("text-profiles.json", isDirectory: false))
}

@Test func `state root override preserves compatibility with an existing legacy profiles directory path`() throws {
    let fileManager = FileManager.default
    let overrideRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: overrideRoot) }

    let legacyProfilesURL = overrideRoot.appendingPathComponent("profiles", isDirectory: true)
    try fileManager.createDirectory(at: legacyProfilesURL, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: overrideRoot.appendingPathComponent(ProfileStore.configurationFileName))

    #expect(ProfileStore.defaultRootURL(fileManager: fileManager, stateRootOverride: legacyProfilesURL.path) == legacyProfilesURL)
    #expect(ProfileStore.defaultConfigurationURL(fileManager: fileManager, stateRootOverride: legacyProfilesURL.path) == overrideRoot.appendingPathComponent("configuration.json", isDirectory: false))
    #expect(ProfileStore.defaultTextProfilesURL(fileManager: fileManager, stateRootOverride: legacyProfilesURL.path) == overrideRoot.appendingPathComponent("text-profiles.json", isDirectory: false))
}

@Test func `state root override preserves compatibility with a profiles-only legacy store`() throws {
    let fileManager = FileManager.default
    let overrideRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: overrideRoot) }

    let legacyProfilesURL = overrideRoot.appendingPathComponent("profiles", isDirectory: true)
    let legacyStore = ProfileStore(rootURL: legacyProfilesURL, fileManager: fileManager)
    _ = try legacyStore.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    #expect(ProfileStore.defaultRootURL(fileManager: fileManager, stateRootOverride: legacyProfilesURL.path) == legacyProfilesURL)
    #expect(ProfileStore.defaultConfigurationURL(fileManager: fileManager, stateRootOverride: legacyProfilesURL.path) == overrideRoot.appendingPathComponent("configuration.json", isDirectory: false))
    #expect(ProfileStore.defaultTextProfilesURL(fileManager: fileManager, stateRootOverride: legacyProfilesURL.path) == overrideRoot.appendingPathComponent("text-profiles.json", isDirectory: false))
}

@Test func `runtime state root environment override supersedes deprecated profile root alias`() {
    let environment = [
        ProfileStore.runtimeStateRootOverrideEnvironmentVariable: "/tmp/speakswiftly-state-root",
        ProfileStore.profileRootOverrideEnvironmentVariable: "/tmp/speakswiftly-profile-root",
    ]

    #expect(ProfileStore.runtimeStateRootOverride(in: environment) == ProfileStore.RuntimeStateRootOverride(
        path: "/tmp/speakswiftly-state-root",
        source: .runtimeStateRoot,
    ))
    #expect(ProfileStore.runtimeStateRootOverridePath(in: environment) == "/tmp/speakswiftly-state-root")
}

@Test func `deprecated profile root environment alias remains compatible`() {
    let environment = [
        ProfileStore.profileRootOverrideEnvironmentVariable: "/tmp/speakswiftly-profile-root",
    ]

    #expect(ProfileStore.runtimeStateRootOverride(in: environment) == ProfileStore.RuntimeStateRootOverride(
        path: "/tmp/speakswiftly-profile-root",
        source: .deprecatedProfileRoot,
    ))
    #expect(ProfileStore.runtimeStateRootOverridePath(in: environment) == "/tmp/speakswiftly-profile-root")
}

// MARK: - Listing and Validation

@Test func `lists profiles in sorted order`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01])

    _ = try store.createProfile(
        profileName: "zeta",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Zeta",
        sourceText: "Zeta",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )
    _ = try store.createProfile(
        profileName: "alpha",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Alpha",
        sourceText: "Alpha",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["alpha", "zeta"])
}

@Test func `list profiles skips corrupt manifest instead of failing whole listing`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    _ = try store.createProfile(
        profileName: "healthy",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Healthy voice.",
        sourceText: "Healthy transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01]),
    )

    let profileDirectory = store.profileDirectoryURL(for: "broken")
    try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: store.manifestURL(for: profileDirectory))

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["healthy"])
}

@Test func `list profiles skips stray files and partial directories`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    _ = try store.createProfile(
        profileName: "healthy",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Healthy voice.",
        sourceText: "Healthy transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01]),
    )

    try Data("junk".utf8).write(to: tempRoot.appendingPathComponent("README.txt"))
    try fileManager.createDirectory(
        at: tempRoot.appendingPathComponent("partial-profile", isDirectory: true),
        withIntermediateDirectories: false,
    )

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["healthy"])
}

@Test func `create profile publishes completed directory and clears abandoned staged data`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    let abandonedStage = tempRoot.appendingPathComponent(".fresh.create-abandoned", isDirectory: true)
    try fileManager.createDirectory(at: abandonedStage, withIntermediateDirectories: false)
    try Data("stale".utf8).write(to: abandonedStage.appendingPathComponent("partial.txt"))

    let stored = try store.createProfile(
        profileName: "fresh",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Fresh voice.",
        sourceText: "Fresh transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01]),
    )

    #expect(stored.directoryURL == store.profileDirectoryURL(for: "fresh"))
    #expect(fileManager.fileExists(atPath: store.manifestURL(for: stored.directoryURL).path))
    #expect(fileManager.fileExists(atPath: store.referenceAudioURL(for: stored.directoryURL).path))
    #expect(!fileManager.fileExists(atPath: abandonedStage.path))
    #expect(try store.listProfiles().map(\.profileName) == ["fresh"])
}

@Test func `upgrades legacy manifest into backend materializations`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    let profileDirectory = store.profileDirectoryURL(for: "legacy")
    try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: false)

    let legacyManifest = """
    {
      "createdAt" : "2026-04-07T12:00:00Z",
      "modelRepo" : "test-model",
      "profileName" : "legacy",
      "referenceAudioFile" : "reference.wav",
      "sampleRate" : 24000,
      "sourceText" : "Legacy transcript",
      "version" : 1,
      "voiceDescription" : "Legacy voice"
    }
    """
    try Data(legacyManifest.utf8).write(to: store.manifestURL(for: profileDirectory))
    try Data([0x01, 0x02]).write(to: store.referenceAudioURL(for: profileDirectory))

    let loaded = try store.loadProfile(named: "legacy")

    #expect(loaded.manifest.version == ProfileStore.manifestVersion)
    #expect(loaded.manifest.sourceKind == .generated)
    #expect(loaded.manifest.vibe == .femme)
    #expect(loaded.manifest.author == .user)
    #expect(loaded.manifest.seed == nil)
    #expect(loaded.manifest.transcriptProvenance == nil)
    #expect(loaded.manifest.backendMaterializations.count == 1)
    #expect(try loaded.qwenMaterialization().referenceAudioURL.lastPathComponent == "reference.wav")
    #expect(try loaded.qwenMaterialization().manifest.referenceText == "Legacy transcript")
}

@Test func `stores clone transcript provenance on new profiles and legacy upgrade leaves it unknown`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    let providedTranscriptProfile = try store.createProfile(
        profileName: "provided-clone",
        vibe: .masc,
        modelRepo: ModelFactory.importedCloneModelRepo,
        voiceDescription: ModelFactory.importedCloneVoiceDescription,
        sourceText: "Provided transcript",
        transcriptProvenance: TranscriptProvenance(
            source: .provided,
            createdAt: Date(timeIntervalSince1970: 1_712_345_678),
            transcriptionModelRepo: nil,
        ),
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )
    #expect(providedTranscriptProfile.manifest.sourceKind == .importedClone)
    #expect(providedTranscriptProfile.manifest.transcriptProvenance?.source == .provided)
    #expect(providedTranscriptProfile.manifest.transcriptProvenance?.transcriptionModelRepo == nil)

    let inferredTranscriptProfile = try store.createProfile(
        profileName: "inferred-clone",
        vibe: .femme,
        modelRepo: ModelFactory.importedCloneModelRepo,
        voiceDescription: ModelFactory.importedCloneVoiceDescription,
        sourceText: "Inferred transcript",
        transcriptProvenance: TranscriptProvenance(
            source: .inferred,
            createdAt: Date(timeIntervalSince1970: 1_712_345_679),
            transcriptionModelRepo: ModelFactory.cloneTranscriptionModelRepo,
        ),
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )
    #expect(inferredTranscriptProfile.manifest.transcriptProvenance?.source == .inferred)
    #expect(
        inferredTranscriptProfile.manifest.transcriptProvenance?.transcriptionModelRepo
            == ModelFactory.cloneTranscriptionModelRepo,
    )

    let listedProfiles = try store.listProfiles()
    let inferredSummary = try #require(listedProfiles.first(where: { $0.profileName == "inferred-clone" }))
    #expect(inferredSummary.transcriptSource == .inferred)
    #expect(inferredSummary.transcriptResolvedAt == Date(timeIntervalSince1970: 1_712_345_679))
    #expect(inferredSummary.transcriptionModelRepo == ModelFactory.cloneTranscriptionModelRepo)

    let providedSummary = try #require(listedProfiles.first(where: { $0.profileName == "provided-clone" }))
    #expect(providedSummary.transcriptSource == .provided)
    #expect(providedSummary.transcriptResolvedAt == Date(timeIntervalSince1970: 1_712_345_678))
    #expect(providedSummary.transcriptionModelRepo == nil)

    try store.ensureRootExists()
    let legacyCloneDirectory = store.profileDirectoryURL(for: "legacy-clone")
    try fileManager.createDirectory(at: legacyCloneDirectory, withIntermediateDirectories: false)
    let legacyFemmeAlias = String(
        decoding: [97, 110, 100, 114, 111, 103, 121, 110, 111, 117, 115],
        as: UTF8.self,
    )

    let legacyCloneManifest = """
    {
      "backendMaterializations" : [
        {
          "backend" : "qwen3",
          "createdAt" : "2026-04-07T12:00:00Z",
          "modelRepo" : "\(ModelFactory.residentModelRepo(for: .qwen3))",
          "referenceAudioFile" : "reference.wav",
          "referenceText" : "Legacy clone transcript",
          "sampleRate" : 24000
        }
      ],
      "createdAt" : "2026-04-07T12:00:00Z",
      "modelRepo" : "\(ModelFactory.importedCloneModelRepo)",
      "profileName" : "legacy-clone",
      "sampleRate" : 24000,
      "sourceKind" : "imported_clone",
      "sourceText" : "Legacy clone transcript",
      "version" : 4,
      "vibe" : "\(legacyFemmeAlias)",
      "voiceDescription" : "\(ModelFactory.importedCloneVoiceDescription)"
    }
    """
    try Data(legacyCloneManifest.utf8).write(to: store.manifestURL(for: legacyCloneDirectory))
    try Data([0x01, 0x02]).write(to: store.referenceAudioURL(for: legacyCloneDirectory))

    let upgradedLegacyClone = try store.loadProfile(named: "legacy-clone")
    #expect(upgradedLegacyClone.manifest.version == ProfileStore.manifestVersion)
    #expect(upgradedLegacyClone.manifest.sourceKind == .importedClone)
    #expect(upgradedLegacyClone.manifest.vibe == .femme)
    #expect(upgradedLegacyClone.manifest.transcriptProvenance == nil)
}

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `stores and loads prepared qwen conditioning artifacts`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    _ = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: audioData,
    )

    let conditioning = Qwen3TTSModel.Qwen3TTSReferenceConditioning(
        speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
        referenceSpeechCodes: MLXArray([Int32(10), 11, 12, 13]).reshaped([1, 2, 2]),
        referenceTextTokenIDs: MLXArray([Int32(101), 102, 103]).reshaped([1, 3]),
        resolvedLanguage: "English",
        codecLanguageID: 7,
    )

    let stored = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3,
        modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
        conditioning: conditioning,
        createdAt: Date(timeIntervalSince1970: 1_712_800_000),
    )

    let artifact = try #require(stored.qwenConditioningArtifact(for: .qwen3, modelRepo: ModelFactory.qwenResidentModelRepo))
    #expect(stored.manifest.qwenConditioningArtifacts.count == 1)
    #expect(fileManager.fileExists(atPath: artifact.artifactURL.path))

    let reloadedConditioning = try store.loadQwenConditioningArtifact(artifact)

    #expect(reloadedConditioning.resolvedLanguage == "English")
    #expect(reloadedConditioning.codecLanguageID == 7)
    #expect(reloadedConditioning.referenceSpeechCodes.asArray(Int32.self) == [10, 11, 12, 13])
    #expect(reloadedConditioning.referenceSpeechCodes.shape == [1, 2, 2])
    #expect(reloadedConditioning.referenceTextTokenIDs.asArray(Int32.self) == [101, 102, 103])
    #expect(reloadedConditioning.referenceTextTokenIDs.shape == [1, 3])
    #expect(reloadedConditioning.speakerEmbedding?.asArray(Float.self) == [0.25, 0.5])
}

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `stores prepared qwen conditioning per model repo`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    _ = try store.createProfile(
        profileName: "default-femme",
        vibe: .femme,
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: Data([0x52, 0x49, 0x46, 0x46]),
    )

    let defaultConditioning = Qwen3TTSModel.Qwen3TTSReferenceConditioning(
        speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
        referenceSpeechCodes: MLXArray([Int32(10), 11]).reshaped([1, 1, 2]),
        referenceTextTokenIDs: MLXArray([Int32(101), 102]).reshaped([1, 2]),
        resolvedLanguage: "English",
        codecLanguageID: 7,
    )
    let largerConditioning = Qwen3TTSModel.Qwen3TTSReferenceConditioning(
        speakerEmbedding: MLXArray([Float(0.75), 1.0]).reshaped([1, 2]),
        referenceSpeechCodes: MLXArray([Int32(20), 21]).reshaped([1, 1, 2]),
        referenceTextTokenIDs: MLXArray([Int32(201), 202]).reshaped([1, 2]),
        resolvedLanguage: "English",
        codecLanguageID: 7,
    )

    _ = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3,
        modelRepo: ModelFactory.qwenResidentModelRepo,
        conditioning: defaultConditioning,
    )
    let stored = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3,
        modelRepo: ModelFactory.qwen17B8BitResidentModelRepo,
        conditioning: largerConditioning,
    )

    let defaultArtifact = try #require(stored.qwenConditioningArtifact(for: .qwen3, modelRepo: ModelFactory.qwenResidentModelRepo))
    let largerArtifact = try #require(stored.qwenConditioningArtifact(for: .qwen3, modelRepo: ModelFactory.qwen17B8BitResidentModelRepo))

    #expect(stored.manifest.qwenConditioningArtifacts.count == 2)
    #expect(defaultArtifact.manifest.artifactFile == "qwen-conditioning-qwen3.json")
    #expect(largerArtifact.manifest.artifactFile.contains("Qwen3-TTS-12Hz-1_7B-Base-8bit"))
    #expect(fileManager.fileExists(atPath: defaultArtifact.artifactURL.path))
    #expect(fileManager.fileExists(atPath: largerArtifact.artifactURL.path))
}

@Test func `loads and normalizes legacy custom voice qwen artifact metadata`() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let profileDirectory = store.profileDirectoryURL(for: "legacy-custom-voice")
    try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: profileDirectory.appendingPathComponent(ProfileStore.audioFileName))
    try Data("{}".utf8).write(
        to: profileDirectory.appendingPathComponent("qwen-conditioning-\(SpeakSwiftly.SpeechBackend.legacyQwenCustomVoiceRawValue).json"),
    )

    let legacyManifestJSON = """
    {
      "backendMaterializations" : [
        {
          "backend" : "qwen3_custom_voice",
          "createdAt" : "2026-04-16T00:00:00Z",
          "modelRepo" : "\(ModelFactory.legacyQwenCustomVoiceResidentModelRepo)",
          "referenceAudioFile" : "\(ProfileStore.audioFileName)",
          "referenceText" : "Legacy custom voice transcript",
          "sampleRate" : 24000
        }
      ],
      "createdAt" : "2026-04-16T00:00:00Z",
      "modelRepo" : "test-model",
      "profileName" : "legacy-custom-voice",
      "qwenConditioningArtifacts" : [
        {
          "artifactFile" : "qwen-conditioning-\(SpeakSwiftly.SpeechBackend.legacyQwenCustomVoiceRawValue).json",
          "artifactVersion" : 1,
          "backend" : "qwen3_custom_voice",
          "createdAt" : "2026-04-16T00:00:00Z",
          "modelRepo" : "\(ModelFactory.legacyQwenCustomVoiceResidentModelRepo)"
        }
      ],
      "sampleRate" : 24000,
      "sourceKind" : "generated",
      "sourceText" : "Legacy custom voice transcript",
      "version" : 5,
      "vibe" : "femme",
      "voiceDescription" : "Legacy custom voice profile."
    }
    """

    try Data(legacyManifestJSON.utf8).write(to: store.manifestURL(for: profileDirectory))

    let loaded = try store.loadProfile(named: "legacy-custom-voice")
    let materialization = try loaded.qwenMaterialization(for: .qwen3)
    let artifact = try #require(loaded.qwenConditioningArtifact(for: .qwen3))

    #expect(materialization.manifest.backend == .qwen3)
    #expect(materialization.manifest.modelRepo == ModelFactory.residentModelRepo(for: .qwen3))
    #expect(artifact.manifest.backend == .qwen3)
    #expect(artifact.manifest.modelRepo == ModelFactory.residentModelRepo(for: .qwen3))
    #expect(artifact.artifactURL.lastPathComponent == "qwen-conditioning-\(SpeakSwiftly.SpeechBackend.legacyQwenCustomVoiceRawValue).json")
}
