#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

extension SpeakSwiftlyE2ETests {
    struct ChatterboxWorkflowSuite {
        @Test func `voice design silent then file`() async throws {
            #expect(SpeakSwiftlyE2ETests.isE2EEnabled)

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let profileName = "chatterbox-voice-design-profile"

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                    speechBackend: .chatterboxTurbo,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-chatterbox-voice-design",
                    profileName: profileName,
                    text: SpeakSwiftlyE2ETests.testingProfileText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                )
                try await SpeakSwiftlyE2ETests.runLiveSpeechForCurrentE2EMode(
                    on: worker,
                    id: "req-live-chatterbox-voice-design",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: profileName,
                )
                let generatedFile = try await SpeakSwiftlyE2ETests.runGeneratedFileSpeech(
                    on: worker,
                    id: "req-file-chatterbox-voice-design",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: profileName,
                )
                #expect(generatedFile["profile_name"] as? String == profileName)
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }
        }

        @Test func `clone with provided transcript`() async throws {
            #expect(SpeakSwiftlyE2ETests.isE2EEnabled)

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let fixtureProfileName = "chatterbox-clone-source-profile"
            let cloneProfileName = "chatterbox-provided-transcript-clone-profile"
            let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/chatterbox-provided-clone-reference.wav")

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                    speechBackend: .chatterboxTurbo,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-chatterbox-clone-fixture",
                    profileName: fixtureProfileName,
                    text: SpeakSwiftlyE2ETests.testingCloneSourceText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                    outputURL: referenceAudioURL,
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await SpeakSwiftlyE2ETests.createCloneProfile(
                    on: worker,
                    id: "req-create-chatterbox-clone-provided-transcript",
                    profileName: cloneProfileName,
                    referenceAudioURL: referenceAudioURL,
                    vibe: .masc,
                    transcript: SpeakSwiftlyE2ETests.testingCloneSourceText,
                    expectTranscription: false,
                )

                let store = ProfileStore(rootURL: sandbox.profileRootURL)
                let storedProfile = try store.loadProfile(named: cloneProfileName)
                #expect(storedProfile.manifest.sourceText == SpeakSwiftlyE2ETests.testingCloneSourceText)
                #expect(storedProfile.manifest.vibe == .masc)
                #expect(storedProfile.manifest.transcriptProvenance?.source == .provided)
                #expect(storedProfile.manifest.transcriptProvenance?.transcriptionModelRepo == nil)

                try await SpeakSwiftlyE2ETests.runLiveSpeechForCurrentE2EMode(
                    on: worker,
                    id: "req-live-chatterbox-clone-provided-transcript",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: cloneProfileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }
        }

        @Test func `clone with inferred transcript`() async throws {
            #expect(SpeakSwiftlyE2ETests.isE2EEnabled)

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let fixtureProfileName = "chatterbox-inferred-clone-source-profile"
            let cloneProfileName = "chatterbox-inferred-transcript-clone-profile"
            let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/chatterbox-inferred-clone-reference.wav")

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                    speechBackend: .chatterboxTurbo,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-chatterbox-inferred-clone-fixture",
                    profileName: fixtureProfileName,
                    text: SpeakSwiftlyE2ETests.testingCloneSourceText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                    outputURL: referenceAudioURL,
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await SpeakSwiftlyE2ETests.createCloneProfile(
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
                #expect(SpeakSwiftlyE2ETests.transcriptLooksCloseToCloneSource(inferredTranscript))

                try await SpeakSwiftlyE2ETests.runLiveSpeechForCurrentE2EMode(
                    on: worker,
                    id: "req-live-chatterbox-clone-inferred-transcript",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: cloneProfileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }
        }
    }
}
#endif
