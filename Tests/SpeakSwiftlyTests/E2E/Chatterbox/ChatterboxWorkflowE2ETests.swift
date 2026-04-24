#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .chatterbox),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
struct ChatterboxE2ETests {
    @Test func `voice design silent then file`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "chatterbox-voice-design-profile"

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .chatterboxTurbo,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: profileName)
        try await E2EHarness.runLiveSpeechForCurrentE2EMode(
            on: worker,
            id: "req-live-chatterbox-voice-design",
            text: E2EHarness.testingPlaybackText,
            profileName: profileName,
        )
        let generatedFile = try await E2EHarness.runGeneratedFileSpeech(
            on: worker,
            id: "req-file-chatterbox-voice-design",
            text: E2EHarness.testingPlaybackText,
            profileName: profileName,
        )
        #expect(generatedFile["voice_profile"] as? String == profileName)
        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `clone with provided and inferred transcripts`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let fixtureProfileName = "chatterbox-clone-source-profile"
        let cloneProfileName = "chatterbox-provided-transcript-clone-profile"
        let inferredCloneProfileName = "chatterbox-inferred-transcript-clone-profile"

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .chatterboxTurbo,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: fixtureProfileName)
        #expect(FileManager.default.fileExists(atPath: sandbox.referenceAudioURL(for: fixtureProfileName).path))

        try sandbox.seedProfileFixture(.mascCloneProvided, as: cloneProfileName)

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: cloneProfileName)
        #expect(storedProfile.manifest.sourceText == E2EHarness.testingCloneSourceText)
        #expect(storedProfile.manifest.vibe == .masc)
        #expect(storedProfile.manifest.transcriptProvenance?.source == .provided)
        #expect(storedProfile.manifest.transcriptProvenance?.transcriptionModelRepo == nil)

        try sandbox.seedProfileFixture(.mascCloneInferred, as: inferredCloneProfileName)

        let inferredProfile = try store.loadProfile(named: inferredCloneProfileName)
        let inferredTranscript = inferredProfile.manifest.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(inferredProfile.manifest.vibe == .masc)
        #expect(inferredProfile.manifest.transcriptProvenance?.source == .inferred)
        #expect(
            inferredProfile.manifest.transcriptProvenance?.transcriptionModelRepo
                == ModelFactory.cloneTranscriptionModelRepo,
        )
        #expect(!inferredTranscript.isEmpty)
        #expect(E2EHarness.transcriptLooksCloseToCloneSource(inferredTranscript))

        try await E2EHarness.runLiveSpeechForCurrentE2EMode(
            on: worker,
            id: "req-live-chatterbox-clone-provided-transcript",
            text: E2EHarness.testingPlaybackText,
            profileName: cloneProfileName,
        )
        try await E2EHarness.runLiveSpeechForCurrentE2EMode(
            on: worker,
            id: "req-live-chatterbox-clone-inferred-transcript",
            text: E2EHarness.testingPlaybackText,
            profileName: inferredCloneProfileName,
        )
        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
