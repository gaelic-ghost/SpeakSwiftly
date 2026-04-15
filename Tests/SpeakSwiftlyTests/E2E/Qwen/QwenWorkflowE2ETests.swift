import Foundation
@testable import SpeakSwiftly
import Testing

extension SpeakSwiftlyE2ETests {
    struct QwenWorkflowSuite {
        @Test func `voice design silent then audible`() async throws {
            #expect(SpeakSwiftlyE2ETests.isE2EEnabled)

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let profileName = "voice-design-profile"

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-voice-design",
                    profileName: profileName,
                    text: SpeakSwiftlyE2ETests.testingProfileText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                )
                try await SpeakSwiftlyE2ETests.runSilentSpeech(
                    on: worker,
                    id: "req-live-voice-design-silent",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: profileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: false,
                    playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
                try await SpeakSwiftlyE2ETests.runAudibleSpeech(
                    on: worker,
                    id: "req-live-voice-design-audible",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: profileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }
        }

        @Test func `prepared conditioning persists and reloads across worker restart`() async throws {
            #expect(SpeakSwiftlyE2ETests.isE2EEnabled)

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let profileName = "prepared-conditioning-profile"
            let runtimeConfiguration = SpeakSwiftly.Configuration(
                speechBackend: .qwen3,
                qwenConditioningStrategy: .preparedConditioning,
            )

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                    configuration: runtimeConfiguration,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-prepared-conditioning-profile",
                    profileName: profileName,
                    text: SpeakSwiftlyE2ETests.testingProfileText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                )
                try await SpeakSwiftlyE2ETests.runSilentSpeech(
                    on: worker,
                    id: "req-live-prepared-conditioning-first-pass",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: profileName,
                )
                #expect(try await worker.waitForStderrJSONObject(timeout: e2eTimeout) {
                    $0["event"] as? String == "qwen_reference_conditioning_persisted"
                        && $0["request_id"] as? String == "req-live-prepared-conditioning-first-pass"
                } != nil)
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }

            let store = ProfileStore(rootURL: sandbox.profileRootURL)
            let storedProfile = try store.loadProfile(named: profileName)
            #expect(storedProfile.qwenConditioningArtifact(for: .qwen3) != nil)

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                    configuration: runtimeConfiguration,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
                try await SpeakSwiftlyE2ETests.runSilentSpeech(
                    on: worker,
                    id: "req-live-prepared-conditioning-second-pass",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: profileName,
                )
                #expect(try await worker.waitForStderrJSONObject(timeout: e2eTimeout) {
                    $0["event"] as? String == "qwen_reference_conditioning_loaded"
                        && $0["request_id"] as? String == "req-live-prepared-conditioning-second-pass"
                } != nil)
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }
        }

        @Test func `clone with provided transcript`() async throws {
            #expect(SpeakSwiftlyE2ETests.isE2EEnabled)

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }
            let fixtureProfileName = "clone-source-profile"
            let cloneProfileName = "provided-transcript-clone-profile"
            let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/provided-clone-reference.wav")

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-clone-fixture",
                    profileName: fixtureProfileName,
                    text: SpeakSwiftlyE2ETests.testingCloneSourceText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                    outputURL: referenceAudioURL,
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await SpeakSwiftlyE2ETests.createCloneProfile(
                    on: worker,
                    id: "req-create-clone-provided-transcript",
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

                try await SpeakSwiftlyE2ETests.runSilentSpeech(
                    on: worker,
                    id: "req-live-clone-provided-transcript-silent",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: cloneProfileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: false,
                    playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
                try await SpeakSwiftlyE2ETests.runAudibleSpeech(
                    on: worker,
                    id: "req-live-clone-provided-transcript-audible",
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
            let fixtureProfileName = "inferred-clone-source-profile"
            let cloneProfileName = "inferred-transcript-clone-profile"
            let referenceAudioURL = sandbox.rootURL.appendingPathComponent("fixtures/inferred-clone-reference.wav")

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: true,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: false)
                try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                    on: worker,
                    id: "req-create-inferred-clone-fixture",
                    profileName: fixtureProfileName,
                    text: SpeakSwiftlyE2ETests.testingCloneSourceText,
                    vibe: .masc,
                    voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
                    outputURL: referenceAudioURL,
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await SpeakSwiftlyE2ETests.createCloneProfile(
                    on: worker,
                    id: "req-create-clone-inferred-transcript",
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

                try await SpeakSwiftlyE2ETests.runSilentSpeech(
                    on: worker,
                    id: "req-live-clone-inferred-transcript-silent",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: cloneProfileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }

            do {
                let worker = try WorkerProcess(
                    profileRootURL: sandbox.profileRootURL,
                    silentPlayback: false,
                    playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled,
                )
                defer { Task { await worker.stop() } }

                try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
                try await SpeakSwiftlyE2ETests.runAudibleSpeech(
                    on: worker,
                    id: "req-live-clone-inferred-transcript-audible",
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    profileName: cloneProfileName,
                )
                try worker.closeInput()
                try await worker.waitForExit(timeout: .seconds(30))
            }
        }
    }
}
