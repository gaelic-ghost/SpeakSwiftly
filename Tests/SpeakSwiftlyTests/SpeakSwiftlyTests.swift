import Foundation
import Testing
@testable import SpeakSwiftly

@Test func decodesSpeakLiveRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live","text":"Hello","profile_name":"default-femme"}"#)

    #expect(request == .speakLive(id: "req-1", text: "Hello", profileName: "default-femme"))
}

@Test func rejectsUnknownOperation() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func rejectsInvalidProfileName() throws {
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ProfileStore(rootURL: tempRoot)

    #expect(throws: WorkerError.self) {
        try store.validateProfileName("Bad Name")
    }
}

@Test func createsListsAndRemovesProfiles() throws {
    let fileManager = FileManager.default
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
