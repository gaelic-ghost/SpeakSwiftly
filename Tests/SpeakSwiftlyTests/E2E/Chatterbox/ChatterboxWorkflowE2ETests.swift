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
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-chatterbox-voice-design",
            profileName: profileName,
            text: E2EHarness.testingProfileText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )
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
        #expect(generatedFile["profile_name"] as? String == profileName)
        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `clone with provided transcript`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let fixtureProfileName = "chatterbox-clone-source-profile"
        let cloneProfileName = "chatterbox-provided-transcript-clone-profile"
        let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/chatterbox-provided-clone-reference.wav")

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .chatterboxTurbo,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-chatterbox-clone-fixture",
            profileName: fixtureProfileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
            outputURL: referenceAudioURL,
        )
        #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

        try await E2EHarness.createCloneProfile(
            on: worker,
            id: "req-create-chatterbox-clone-provided-transcript",
            profileName: cloneProfileName,
            referenceAudioURL: referenceAudioURL,
            vibe: .masc,
            transcript: E2EHarness.testingCloneSourceText,
            expectTranscription: false,
        )

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: cloneProfileName)
        #expect(storedProfile.manifest.sourceText == E2EHarness.testingCloneSourceText)
        #expect(storedProfile.manifest.vibe == .masc)
        #expect(storedProfile.manifest.transcriptProvenance?.source == .provided)
        #expect(storedProfile.manifest.transcriptProvenance?.transcriptionModelRepo == nil)

        try await E2EHarness.runLiveSpeechForCurrentE2EMode(
            on: worker,
            id: "req-live-chatterbox-clone-provided-transcript",
            text: E2EHarness.testingPlaybackText,
            profileName: cloneProfileName,
        )
        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `clone with inferred transcript`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let fixtureProfileName = "chatterbox-inferred-clone-source-profile"
        let cloneProfileName = "chatterbox-inferred-transcript-clone-profile"
        let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/chatterbox-inferred-clone-reference.wav")

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .chatterboxTurbo,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-chatterbox-inferred-clone-fixture",
            profileName: fixtureProfileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
            outputURL: referenceAudioURL,
        )
        #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

        try await E2EHarness.createCloneProfile(
            on: worker,
            id: "req-create-chatterbox-clone-inferred-transcript",
            profileName: cloneProfileName,
            referenceAudioURL: referenceAudioURL,
            vibe: .masc,
            transcript: nil,
            expectTranscription: true,
        )

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: cloneProfileName)
        let inferredTranscript = storedProfile.manifest.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(storedProfile.manifest.vibe == .masc)
        #expect(storedProfile.manifest.transcriptProvenance?.source == .inferred)
        #expect(
            storedProfile.manifest.transcriptProvenance?.transcriptionModelRepo
                == ModelFactory.cloneTranscriptionModelRepo,
        )
        #expect(!inferredTranscript.isEmpty)
        #expect(E2EHarness.transcriptLooksCloseToCloneSource(inferredTranscript))

        try await E2EHarness.runLiveSpeechForCurrentE2EMode(
            on: worker,
            id: "req-live-chatterbox-clone-inferred-transcript",
            text: E2EHarness.testingPlaybackText,
            profileName: cloneProfileName,
        )
        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
