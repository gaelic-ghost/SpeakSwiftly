import Foundation
import Testing
@testable import SpeakSwiftlyCore

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
    #expect(stored.manifest.backendMaterializations.map(\.backend) == [.qwen3])
    #expect(try stored.qwenMaterialization().manifest.referenceText == "Hello there")

    let listed = try store.listProfiles()
    #expect(listed.count == 1)
    #expect(listed.first?.profileName == "default-femme")

    let loaded = try store.loadProfile(named: "default-femme")
    #expect(loaded.manifest.sourceText == "Hello there")
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
    #expect(loaded.manifest.backendMaterializations.count == 1)
    #expect(try loaded.qwenMaterialization().referenceAudioURL.lastPathComponent == "reference.wav")
    #expect(try loaded.qwenMaterialization().manifest.referenceText == "Legacy transcript")
}
