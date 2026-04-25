import Foundation
@testable import SpeakSwiftly
import Testing

// MARK: - Generated File Store

@Test func `generated file store writes loads and lists artifacts`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGeneratedFileStore(rootURL: rootURL)
    let created = try store.createGeneratedFile(
        artifactID: "req-file-1",
        voiceProfile: "default-femme",
        textProfile: "logs",
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )

    #expect(FileManager.default.fileExists(atPath: created.audioURL.path))

    let loaded = try store.loadGeneratedFile(id: "req-file-1")
    #expect(loaded.summary.artifactID == "req-file-1")
    #expect(loaded.summary.voiceProfile == "default-femme")
    #expect(loaded.summary.textProfile == "logs")
    #expect(loaded.summary.sampleRate == 24000)
    #expect(loaded.summary.filePath == created.audioURL.path)

    let listed = try store.listGeneratedFiles()
    #expect(listed == [loaded.summary])
}

@Test func `generated file store lists readable artifacts when stale retained manifests exist`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGeneratedFileStore(rootURL: rootURL)
    _ = try store.createGeneratedFile(
        artifactID: "req-file-readable",
        voiceProfile: "default-femme",
        textProfile: nil,
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )

    let loaded = try store.loadGeneratedFile(id: "req-file-readable")
    let staleArtifactID = "req-file-stale"
    let staleDirectoryURL = store.generatedFileDirectoryURL(for: staleArtifactID)
    try FileManager.default.createDirectory(at: staleDirectoryURL, withIntermediateDirectories: false)
    let staleManifest = """
    {
      "artifactID" : "\(staleArtifactID)",
      "audioFile" : "generated.wav",
      "createdAt" : "2026-04-16T17:46:33Z",
      "profileName" : "default-femme",
      "sampleRate" : 24000,
      "version" : 1
    }
    """
    try Data(staleManifest.utf8).write(to: store.manifestURL(for: staleDirectoryURL))
    try Data([0x04, 0x05, 0x06]).write(to: store.audioURL(for: staleDirectoryURL))

    #expect(try store.listGeneratedFiles() == [loaded.summary])
    #expect(throws: WorkerError.self) {
        _ = try store.loadGeneratedFile(id: staleArtifactID)
    }
}

@Test func `generated file store rejects missing artifacts`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGeneratedFileStore(rootURL: rootURL)

    #expect(throws: WorkerError(code: .generatedFileNotFound, message: "Generated file 'missing' was not found in the SpeakSwiftly generated-file store.")) {
        _ = try store.loadGeneratedFile(id: "missing")
    }
}

@Test func `generated file store removes persisted artifacts`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = try makeGeneratedFileStore(rootURL: rootURL)
    let created = try store.createGeneratedFile(
        artifactID: "req-file-2",
        voiceProfile: "default-femme",
        textProfile: nil,
        inputTextContext: nil,
        requestContext: nil,
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )

    let removed = try store.removeGeneratedFile(id: "req-file-2")
    #expect(removed?.artifactID == created.summary.artifactID)
    #expect(removed?.voiceProfile == created.summary.voiceProfile)
    #expect(removed?.textProfile == created.summary.textProfile)
    #expect(removed?.sampleRate == created.summary.sampleRate)
    #expect(removed?.filePath == created.summary.filePath)
    #expect(!FileManager.default.fileExists(atPath: created.directoryURL.path))
    #expect(try store.listGeneratedFiles().isEmpty)
    #expect(try store.removeGeneratedFile(id: "req-file-2") == nil)
}
