#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .quick),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
)
struct QuickE2ETests {
    @Test func `worker boots and produces one generated file`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-quick-profile",
            profileName: E2EHarness.testingProfileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )

        let generatedFile = try await E2EHarness.runGeneratedFileSpeech(
            on: worker,
            id: "req-quick-generated-file",
            text: E2EHarness.testingPlaybackText,
            profileName: E2EHarness.testingProfileName,
        )

        #expect(generatedFile["artifact_id"] as? String == "req-quick-generated-file-artifact-1")
        #expect(generatedFile["profile_name"] as? String == E2EHarness.testingProfileName)

        let generatedFilePath = try #require(generatedFile["file_path"] as? String)
        #expect(FileManager.default.fileExists(atPath: generatedFilePath))

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}

#endif
