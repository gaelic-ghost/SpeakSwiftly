import Foundation
import Testing
@testable import SpeakSwiftlyCore

extension SpeakSwiftlyE2ETests {
    @Suite("Marvis Workflow E2E")
    struct MarvisWorkflowSuite {
        @Test func marvisVoiceDesignProfilesRouteFemmeToConversationalA() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let profileName = "marvis-femme-profile"

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                speechBackend: .marvis
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-marvis-femme",
                profileName: profileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .femme,
                voiceDescription: "A warm, bright, feminine narrator voice."
            )

            try await SpeakSwiftlyE2ETests.runSilentSpeech(
                on: worker,
                id: "req-live-marvis-femme",
                text: SpeakSwiftlyE2ETests.testingPlaybackText,
                profileName: profileName
            )
            try await SpeakSwiftlyE2ETests.expectMarvisVoiceSelection(
                on: worker,
                requestID: "req-live-marvis-femme",
                expectedVoice: "conversational_a"
            )

            _ = try await SpeakSwiftlyE2ETests.runGeneratedFileSpeech(
                on: worker,
                id: "req-file-marvis-femme",
                text: SpeakSwiftlyE2ETests.testingPlaybackText,
                profileName: profileName
            )
            try await SpeakSwiftlyE2ETests.expectMarvisVoiceSelection(
                on: worker,
                requestID: "req-file-marvis-femme",
                expectedVoice: "conversational_a"
            )

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        @Test func marvisCloneProfilesRouteMascToConversationalB() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let fixtureProfileName = "marvis-clone-source"
            let cloneProfileName = "marvis-masc-clone-profile"
            let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/marvis-clone-reference.wav")

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                speechBackend: .marvis
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-marvis-clone-fixture",
                profileName: fixtureProfileName,
                text: SpeakSwiftlyE2ETests.testingCloneSourceText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                outputURL: referenceAudioURL
            )

            try await SpeakSwiftlyE2ETests.createCloneProfile(
                on: worker,
                id: "req-create-marvis-clone",
                profileName: cloneProfileName,
                referenceAudioURL: referenceAudioURL,
                vibe: .masc,
                transcript: SpeakSwiftlyE2ETests.testingCloneSourceText,
                expectTranscription: false
            )

            let store = ProfileStore(rootURL: sandbox.profileRootURL)
            let storedProfile = try store.loadProfile(named: cloneProfileName)
            #expect(storedProfile.manifest.vibe == .masc)

            try await SpeakSwiftlyE2ETests.runSilentSpeech(
                on: worker,
                id: "req-live-marvis-masc",
                text: SpeakSwiftlyE2ETests.testingPlaybackText,
                profileName: cloneProfileName
            )
            try await SpeakSwiftlyE2ETests.expectMarvisVoiceSelection(
                on: worker,
                requestID: "req-live-marvis-masc",
                expectedVoice: "conversational_b"
            )

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        @Test func marvisVoiceDesignProfilesRouteAndrogenousToConversationalA() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let profileName = "marvis-androgenous-profile"

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                speechBackend: .marvis
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-marvis-androgenous",
                profileName: profileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .androgenous,
                voiceDescription: "A calm, balanced, and gentle speaking voice."
            )

            try await SpeakSwiftlyE2ETests.runSilentSpeech(
                on: worker,
                id: "req-live-marvis-androgenous",
                text: SpeakSwiftlyE2ETests.testingPlaybackText,
                profileName: profileName
            )
            try await SpeakSwiftlyE2ETests.expectMarvisVoiceSelection(
                on: worker,
                requestID: "req-live-marvis-androgenous",
                expectedVoice: "conversational_a"
            )

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }
}
