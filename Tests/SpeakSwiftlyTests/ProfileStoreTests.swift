import Foundation
import Testing
@testable import SpeakSwiftly

@Test func createsListsLoadsAndRemovesProfiles() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    let stored = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(stored.manifest.profileName == "default-femme")

    let listed = try store.listProfiles()
    #expect(listed.count == 1)
    #expect(listed.first?.profileName == "default-femme")

    let loaded = try store.loadProfile(named: "default-femme")
    #expect(loaded.manifest.sourceText == "Hello there")

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
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(throws: WorkerError.self) {
        _ = try store.createProfile(
            profileName: "default-femme",
            modelRepo: "test-model",
            voiceDescription: "Duplicate",
            sourceText: "Hello again",
            sampleRate: 24_000,
            canonicalAudioData: audioData
        )
    }
}

@Test func exportsCanonicalAudioWithoutOverwritingExistingFiles() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01, 0x02, 0x03, 0x04])
    let stored = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let exportURL = tempRoot.appendingPathComponent("exports/reference.wav")
    try store.exportCanonicalAudio(for: stored, to: exportURL.path)
    #expect(fileManager.fileExists(atPath: exportURL.path))
    #expect(try Data(contentsOf: exportURL) == audioData)

    #expect(throws: WorkerError.self) {
        try store.exportCanonicalAudio(for: stored, to: exportURL.path)
    }
}

@Test func listsProfilesInSortedOrder() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01])

    _ = try store.createProfile(
        profileName: "zeta",
        modelRepo: "test-model",
        voiceDescription: "Zeta",
        sourceText: "Zeta",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )
    _ = try store.createProfile(
        profileName: "alpha",
        modelRepo: "test-model",
        voiceDescription: "Alpha",
        sourceText: "Alpha",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["alpha", "zeta"])
}

@Test func listProfilesFailsWhenManifestIsCorrupt() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    let profileDirectory = store.profileDirectoryURL(for: "broken")
    try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: store.manifestURL(for: profileDirectory))

    #expect(throws: WorkerError.self) {
        _ = try store.listProfiles()
    }
}
