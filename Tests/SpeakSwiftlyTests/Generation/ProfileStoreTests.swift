import Foundation
@preconcurrency import MLX
import Testing
@testable import SpeakSwiftly
import MLXAudioTTS

// MARK: - Profile Lifecycle

@Test func createsListsLoadsAndRemovesProfiles() throws {
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
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(stored.manifest.profileName == "default-femme")
    #expect(stored.manifest.vibe == .femme)
    #expect(stored.manifest.transcriptProvenance == nil)
    #expect(stored.manifest.backendMaterializations.map(\.backend) == [.qwen3])
    #expect(try stored.qwenMaterialization().manifest.referenceText == "Hello there")

    let listed = try store.listProfiles()
    #expect(listed.count == 1)
    #expect(listed.first?.profileName == "default-femme")
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

@Test func rejectsDuplicateProfiles() throws {
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
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(throws: WorkerError.self) {
        _ = try store.createProfile(
            profileName: "default-femme",
            vibe: .femme,
            modelRepo: "test-model",
            voiceDescription: "Duplicate",
            sourceText: "Hello again",
            sampleRate: 24_000,
            canonicalAudioData: audioData
        )
    }
}

@Test func renamesProfilesAndRewritesTheStoredManifestName() throws {
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
        sampleRate: 24_000,
        canonicalAudioData: audioData
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

@Test func renameRejectsAnExistingDestinationProfileName() throws {
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
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )
    _ = try store.createProfile(
        profileName: "default-masc",
        vibe: .masc,
        modelRepo: "test-model",
        voiceDescription: "Warm and low.",
        sourceText: "Hello again",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(throws: WorkerError.self) {
        _ = try store.renameProfile(named: "default-femme", to: "default-masc")
    }
}

// MARK: - Audio Export

@Test func exportsCanonicalAudioWithoutOverwritingExistingFiles() throws {
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
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let exportURL = tempRoot.appendingPathComponent("exports/reference.wav")
    try store.exportCanonicalAudio(for: stored, to: exportURL)
    #expect(fileManager.fileExists(atPath: exportURL.path))
    #expect(try Data(contentsOf: exportURL) == audioData)

    #expect(throws: WorkerError.self) {
        try store.exportCanonicalAudio(for: stored, to: exportURL)
    }
}

// MARK: - Listing and Validation

@Test func listsProfilesInSortedOrder() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01])

    _ = try store.createProfile(
        profileName: "zeta",
        vibe: .androgenous,
        modelRepo: "test-model",
        voiceDescription: "Zeta",
        sourceText: "Zeta",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )
    _ = try store.createProfile(
        profileName: "alpha",
        vibe: .androgenous,
        modelRepo: "test-model",
        voiceDescription: "Alpha",
        sourceText: "Alpha",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["alpha", "zeta"])
}

@Test func listProfilesSkipsCorruptManifestInsteadOfFailingWholeListing() throws {
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
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01])
    )

    let profileDirectory = store.profileDirectoryURL(for: "broken")
    try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: store.manifestURL(for: profileDirectory))

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["healthy"])
}

@Test func listProfilesSkipsStrayFilesAndPartialDirectories() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    _ = try store.createProfile(
        profileName: "healthy",
        vibe: .androgenous,
        modelRepo: "test-model",
        voiceDescription: "Healthy voice.",
        sourceText: "Healthy transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01])
    )

    try Data("junk".utf8).write(to: tempRoot.appendingPathComponent("README.txt"))
    try fileManager.createDirectory(
        at: tempRoot.appendingPathComponent("partial-profile", isDirectory: true),
        withIntermediateDirectories: false
    )

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["healthy"])
}

@Test func upgradesLegacyManifestIntoBackendMaterializations() throws {
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
    #expect(loaded.manifest.vibe == .androgenous)
    #expect(loaded.manifest.transcriptProvenance == nil)
    #expect(loaded.manifest.backendMaterializations.count == 1)
    #expect(try loaded.qwenMaterialization().referenceAudioURL.lastPathComponent == "reference.wav")
    #expect(try loaded.qwenMaterialization().manifest.referenceText == "Legacy transcript")
}

@Test func storesCloneTranscriptProvenanceOnNewProfilesAndLegacyUpgradeLeavesItUnknown() throws {
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
            transcriptionModelRepo: nil
        ),
        sampleRate: 24_000,
        canonicalAudioData: audioData
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
            transcriptionModelRepo: ModelFactory.cloneTranscriptionModelRepo
        ),
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )
    #expect(inferredTranscriptProfile.manifest.transcriptProvenance?.source == .inferred)
    #expect(
        inferredTranscriptProfile.manifest.transcriptProvenance?.transcriptionModelRepo
            == ModelFactory.cloneTranscriptionModelRepo
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
      "vibe" : "androgenous",
      "voiceDescription" : "\(ModelFactory.importedCloneVoiceDescription)"
    }
    """
    try Data(legacyCloneManifest.utf8).write(to: store.manifestURL(for: legacyCloneDirectory))
    try Data([0x01, 0x02]).write(to: store.referenceAudioURL(for: legacyCloneDirectory))

    let upgradedLegacyClone = try store.loadProfile(named: "legacy-clone")
    #expect(upgradedLegacyClone.manifest.version == ProfileStore.manifestVersion)
    #expect(upgradedLegacyClone.manifest.sourceKind == .importedClone)
    #expect(upgradedLegacyClone.manifest.transcriptProvenance == nil)
}

@Test func storesAndLoadsPreparedQwenConditioningArtifacts() throws {
    guard mlxConditioningPersistenceTestsEnabled() else { return }

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
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let conditioning = Qwen3TTSModel.Qwen3TTSReferenceConditioning(
        speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
        referenceSpeechCodes: MLXArray([Int32(10), 11, 12, 13]).reshaped([1, 2, 2]),
        referenceTextTokenIDs: MLXArray([Int32(101), 102, 103]).reshaped([1, 3]),
        resolvedLanguage: "English",
        codecLanguageID: 7
    )

    let stored = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3CustomVoice,
        modelRepo: ModelFactory.residentModelRepo(for: .qwen3CustomVoice),
        conditioning: conditioning,
        createdAt: Date(timeIntervalSince1970: 1_712_800_000)
    )

    let artifact = try #require(stored.qwenConditioningArtifact(for: .qwen3CustomVoice))
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
