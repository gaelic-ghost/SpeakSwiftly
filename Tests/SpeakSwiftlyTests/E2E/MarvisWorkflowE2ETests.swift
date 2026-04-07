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

        @Test func marvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            struct MarvisProfileLane {
                let createID: String
                let liveID: String
                let profileName: String
                let vibe: SpeakSwiftly.Vibe
                let voiceDescription: String
                let expectedVoice: String
            }

            let lanes = [
                MarvisProfileLane(
                    createID: "req-create-marvis-triplet-femme",
                    liveID: "req-live-marvis-triplet-femme",
                    profileName: "marvis-triplet-femme-profile",
                    vibe: .femme,
                    voiceDescription: "A warm, bright, feminine narrator voice.",
                    expectedVoice: "conversational_a"
                ),
                MarvisProfileLane(
                    createID: "req-create-marvis-triplet-masc",
                    liveID: "req-live-marvis-triplet-masc",
                    profileName: "marvis-triplet-masc-profile",
                    vibe: .masc,
                    voiceDescription: "A grounded, rich, masculine speaking voice.",
                    expectedVoice: "conversational_b"
                ),
                MarvisProfileLane(
                    createID: "req-create-marvis-triplet-androgenous",
                    liveID: "req-live-marvis-triplet-androgenous",
                    profileName: "marvis-triplet-androgenous-profile",
                    vibe: .androgenous,
                    voiceDescription: "A calm, balanced, and gentle speaking voice.",
                    expectedVoice: "conversational_a"
                ),
            ]

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled,
                speechBackend: .marvis
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)

            for lane in lanes {
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: lane.createID,
                    profileName: lane.profileName,
                    text: SpeakSwiftlyE2ETests.testingProfileText,
                    vibe: lane.vibe,
                    voiceDescription: lane.voiceDescription
                )
            }

            let store = ProfileStore(rootURL: sandbox.profileRootURL)
            for lane in lanes {
                let storedProfile = try store.loadProfile(named: lane.profileName)
                #expect(storedProfile.manifest.vibe == lane.vibe)
            }

            for lane in lanes {
                try await SpeakSwiftlyE2ETests.runAudibleSpeech(
                    on: worker,
                    id: lane.liveID,
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: lane.profileName
                )
                try await SpeakSwiftlyE2ETests.expectMarvisVoiceSelection(
                    on: worker,
                    requestID: lane.liveID,
                    expectedVoice: lane.expectedVoice
                )
            }

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }
}
