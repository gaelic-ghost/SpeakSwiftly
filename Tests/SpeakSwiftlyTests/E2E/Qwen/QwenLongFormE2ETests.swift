#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .qwen, .longForm),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
    .enabled(
        if: speakSwiftlyQwenLongFormE2ETestsEnabled(),
        "This long-form Qwen suite is opt-in and requires SPEAKSWIFTLY_QWEN_LONGFORM_E2E=1.",
    ),
)
struct QwenLongFormE2ETests {
    @Test func `voice design live speech spans nine prose paragraphs`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }
        let profileName = "qwen-longform-profile"

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: !speakSwiftlyAudibleE2ETestsEnabled(),
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-qwen-longform-profile",
            profileName: profileName,
            text: E2EHarness.testingCloneSourceText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )
        try await E2EHarness.runLiveSpeechForCurrentE2EMode(
            on: worker,
            id: "req-qwen-longform-live",
            text: E2EHarness.qwenLongFormPlaybackText,
            profileName: profileName,
        )
        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
