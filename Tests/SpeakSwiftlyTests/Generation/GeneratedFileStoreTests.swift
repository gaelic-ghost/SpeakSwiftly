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
        profileName: "default-femme",
        textProfileName: "logs",
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )

    #expect(FileManager.default.fileExists(atPath: created.audioURL.path))

    let loaded = try store.loadGeneratedFile(id: "req-file-1")
    #expect(loaded.summary.artifactID == "req-file-1")
    #expect(loaded.summary.profileName == "default-femme")
    #expect(loaded.summary.textProfileName == "logs")
    #expect(loaded.summary.sampleRate == 24000)
    #expect(loaded.summary.filePath == created.audioURL.path)

    let listed = try store.listGeneratedFiles()
    #expect(listed == [loaded.summary])
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
        profileName: "default-femme",
        textProfileName: nil,
        sampleRate: 24000,
        audioData: Data([0x01, 0x02, 0x03]),
    )

    let removed = try store.removeGeneratedFile(id: "req-file-2")
    #expect(removed?.artifactID == created.summary.artifactID)
    #expect(removed?.profileName == created.summary.profileName)
    #expect(removed?.textProfileName == created.summary.textProfileName)
    #expect(removed?.sampleRate == created.summary.sampleRate)
    #expect(removed?.filePath == created.summary.filePath)
    #expect(!FileManager.default.fileExists(atPath: created.directoryURL.path))
    #expect(try store.listGeneratedFiles().isEmpty)
    #expect(try store.removeGeneratedFile(id: "req-file-2") == nil)
}
