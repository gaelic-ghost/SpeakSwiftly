#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .qwen),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
struct QwenE2ETests {
    @Test func `voice design silent then audible`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "voice-design-profile"

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
            )
            defer { Task { await worker.stop() } }

            try await E2EHarness.awaitWorkerReady(worker)
            try await E2EHarness.createVoiceDesignProfile(
                on: worker,
                id: "req-create-voice-design",
                profileName: profileName,
                text: E2EHarness.testingCloneSourceText,
                vibe: .masc,
                voiceDescription: E2EHarness.testingProfileVoiceDescription,
            )
            try await E2EHarness.runSilentSpeech(
                on: worker,
                id: "req-live-voice-design-silent",
                text: E2EHarness.testingPlaybackText,
                profileName: profileName,
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
            )
            defer { Task { await worker.stop() } }

            try await E2EHarness.awaitWorkerReady(worker)
            try await E2EHarness.runAudibleSpeech(
                on: worker,
                id: "req-live-voice-design-audible",
                text: E2EHarness.testingPlaybackText,
                profileName: profileName,
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }

    @Test(.tags(.persistence))
    func `prepared conditioning persists and reloads across worker restart`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "prepared-conditioning-profile"
        let runtimeConfiguration = SpeakSwiftly.Configuration(
            speechBackend: .qwen3_smol,
            qwenConditioningStrategy: .preparedConditioning,
        )

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                configuration: runtimeConfiguration,
            )
            defer { Task { await worker.stop() } }

            try await E2EHarness.awaitWorkerReady(worker)
            try await E2EHarness.createVoiceDesignProfile(
                on: worker,
                id: "req-create-prepared-conditioning-profile",
                profileName: profileName,
                text: E2EHarness.testingCloneSourceText,
                vibe: .masc,
                voiceDescription: E2EHarness.testingProfileVoiceDescription,
            )
            #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                $0["event"] as? String == "qwen_reference_conditioning_persisted"
                    && $0["request_id"] as? String == "req-create-prepared-conditioning-profile"
            } != nil)
            try await E2EHarness.runSilentSpeech(
                on: worker,
                id: "req-live-prepared-conditioning-first-pass",
                text: E2EHarness.testingPlaybackText,
                profileName: profileName,
            )
            #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                $0["event"] as? String == "qwen_reference_conditioning_loaded"
                    && $0["request_id"] as? String == "req-live-prepared-conditioning-first-pass"
            } != nil)
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: profileName)
        #expect(storedProfile.qwenConditioningArtifact(for: .qwen3_smol) != nil)

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                configuration: runtimeConfiguration,
            )
            defer { Task { await worker.stop() } }

            try await E2EHarness.awaitWorkerReady(worker)
            try await E2EHarness.runSilentSpeech(
                on: worker,
                id: "req-live-prepared-conditioning-second-pass",
                text: E2EHarness.testingPlaybackText,
                profileName: profileName,
            )
            #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                $0["event"] as? String == "qwen_reference_conditioning_loaded"
                    && $0["request_id"] as? String == "req-live-prepared-conditioning-second-pass"
            } != nil)
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }

    @Test(
        .tags(.persistence),
        .enabled(
            if: speakSwiftlyQwenBackendE2ETestsEnabled(),
            "This Qwen backend-variant E2E is opt-in and requires SPEAKSWIFTLY_QWEN_BACKEND_E2E=1.",
        ),
    )
    func `prepared conditioning accumulates across qwen sizes and reroll rebuilds them`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "qwen-backend-conditioning-profile"
        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let runtimeConfiguration = SpeakSwiftly.Configuration(
            speechBackend: .qwen3_smol,
            qwenConditioningStrategy: .preparedConditioning,
        )

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            configuration: runtimeConfiguration,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-qwen-backend-conditioning-profile",
            profileName: profileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            Self.qwenConditioningWasPersisted(
                $0,
                requestID: "req-create-qwen-backend-conditioning-profile",
                backend: .qwen3_smol,
            )
        } != nil)
        #expect(try store.loadProfile(named: profileName).qwenConditioningArtifact(
            for: .qwen3_smol,
            modelRepo: ModelFactory.qwenResidentModelRepo,
        ) != nil)

        try await E2EHarness.switchSpeechBackend(
            on: worker,
            id: "req-switch-qwen-big",
            to: .qwen3_BIG,
        )
        try await E2EHarness.runSilentSpeech(
            on: worker,
            id: "req-live-qwen-big-conditioning",
            text: E2EHarness.testingPlaybackText,
            profileName: profileName,
        )
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            Self.qwenConditioningWasPersisted(
                $0,
                requestID: "req-live-qwen-big-conditioning",
                backend: .qwen3_BIG,
            )
        } != nil)

        let accumulatedProfile = try store.loadProfile(named: profileName)
        #expect(accumulatedProfile.qwenConditioningArtifact(
            for: .qwen3_smol,
            modelRepo: ModelFactory.qwenResidentModelRepo,
        ) != nil)
        #expect(accumulatedProfile.qwenConditioningArtifact(
            for: .qwen3_BIG,
            modelRepo: ModelFactory.qwen17B8BitResidentModelRepo,
        ) != nil)
        #expect(accumulatedProfile.manifest.qwenConditioningArtifacts.count == 2)

        try await E2EHarness.rerollProfile(
            on: worker,
            id: "req-reroll-qwen-backend-conditioning-profile",
            profileName: profileName,
        )
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["event"] as? String == "qwen_reroll_conditioning_ready",
                $0["request_id"] as? String == "req-reroll-qwen-backend-conditioning-profile",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["prepared_backend_count"] as? Int == 2
                && details["qwen_conditioning_artifact_count"] as? Int == 2
        } != nil)

        let rerolledProfile = try store.loadProfile(named: profileName)
        #expect(rerolledProfile.qwenConditioningArtifact(
            for: .qwen3_smol,
            modelRepo: ModelFactory.qwenResidentModelRepo,
        ) != nil)
        #expect(rerolledProfile.qwenConditioningArtifact(
            for: .qwen3_BIG,
            modelRepo: ModelFactory.qwen17B8BitResidentModelRepo,
        ) != nil)
        #expect(rerolledProfile.manifest.qwenConditioningArtifacts.count == 2)
    }

    @Test(
        .tags(.persistence),
        .enabled(
            if: speakSwiftlyQwenBackendE2ETestsEnabled(),
            "This Qwen backend-variant E2E is opt-in and requires SPEAKSWIFTLY_QWEN_BACKEND_E2E=1.",
        ),
    )
    func `explicit qwen quant backend prepares its own conditioning artifact`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "qwen-explicit-quant-profile"
        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let runtimeConfiguration = SpeakSwiftly.Configuration(
            speechBackend: .qwen3_smol_6bit,
            qwenConditioningStrategy: .preparedConditioning,
        )

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            configuration: runtimeConfiguration,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-qwen-explicit-quant-profile",
            profileName: profileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            Self.qwenConditioningWasPersisted(
                $0,
                requestID: "req-create-qwen-explicit-quant-profile",
                backend: .qwen3_smol_6bit,
            )
        } != nil)

        let storedProfile = try store.loadProfile(named: profileName)
        let artifact = try #require(storedProfile.qwenConditioningArtifact(
            for: .qwen3_smol_6bit,
            modelRepo: ModelFactory.qwen06B6BitResidentModelRepo,
        ))
        #expect(artifact.manifest.backend == .qwen3_smol_6bit)
        #expect(artifact.manifest.modelRepo == ModelFactory.qwen06B6BitResidentModelRepo)
    }

    @Test func `clone with provided and inferred transcripts`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let fixtureProfileName = "clone-source-profile"
        let cloneProfileName = "provided-transcript-clone-profile"
        let inferredCloneProfileName = "inferred-transcript-clone-profile"

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
            )
            defer { Task { await worker.stop() } }

            try await E2EHarness.awaitWorkerReady(worker)
            try sandbox.seedProfileFixture(.mascDesign, as: fixtureProfileName)
            let referenceAudioURL = sandbox.referenceAudioURL(for: fixtureProfileName)
            #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

            try await E2EHarness.createCloneProfile(
                on: worker,
                id: "req-create-clone-provided-transcript",
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

            try await E2EHarness.createCloneProfile(
                on: worker,
                id: "req-create-clone-inferred-transcript",
                profileName: inferredCloneProfileName,
                referenceAudioURL: referenceAudioURL,
                vibe: .masc,
                transcript: nil,
                expectTranscription: true,
            )

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

            try await E2EHarness.runSilentSpeech(
                on: worker,
                id: "req-live-clone-provided-transcript-silent",
                text: E2EHarness.testingPlaybackText,
                profileName: cloneProfileName,
            )
            try await E2EHarness.runSilentSpeech(
                on: worker,
                id: "req-live-clone-inferred-transcript-silent",
                text: E2EHarness.testingPlaybackText,
                profileName: inferredCloneProfileName,
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        do {
            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
            )
            defer { Task { await worker.stop() } }

            try await E2EHarness.awaitWorkerReady(worker)
            try await E2EHarness.runAudibleSpeech(
                on: worker,
                id: "req-live-clone-provided-transcript-audible",
                text: E2EHarness.testingPlaybackText,
                profileName: cloneProfileName,
            )
            try await E2EHarness.runAudibleSpeech(
                on: worker,
                id: "req-live-clone-inferred-transcript-audible",
                text: E2EHarness.testingPlaybackText,
                profileName: inferredCloneProfileName,
            )
            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }
}

private extension QwenE2ETests {
    static func qwenConditioningWasPersisted(
        _ object: [String: Any],
        requestID: String,
        backend: SpeakSwiftly.SpeechBackend,
    ) -> Bool {
        guard
            object["event"] as? String == "qwen_reference_conditioning_persisted",
            object["request_id"] as? String == requestID,
            let details = object["details"] as? [String: Any]
        else {
            return false
        }

        return details["speech_backend"] as? String == backend.rawValue
    }
}
#endif
