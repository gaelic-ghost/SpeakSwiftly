#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .trace),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
    .enabled(
        if: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        "This trace-capture suite is opt-in and requires SPEAKSWIFTLY_PLAYBACK_TRACE=1.",
    ),
)
struct TraceCaptureE2ETests {
    @Test func `capture on demand`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: true,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try await E2EHarness.createVoiceDesignProfile(
            on: worker,
            id: "req-create-trace",
            profileName: E2EHarness.testingProfileName,
            text: E2EHarness.testingProfileText,
            vibe: .masc,
            voiceDescription: E2EHarness.testingProfileVoiceDescription,
        )

        try worker.sendJSON(
            """
            {"id":"req-live-trace","op":"generate_speech","text":"\(E2EHarness.testingPlaybackText)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )

        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["event"] as? String == "playback_trace_chunk_received"
                && $0["request_id"] as? String == "req-live-trace"
        } != nil)
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["event"] as? String == "playback_trace_buffer_scheduled"
                && $0["request_id"] as? String == "req-live-trace"
        } != nil)
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["event"] as? String == "playback_trace_buffer_played_back"
                && $0["request_id"] as? String == "req-live-trace"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-trace"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
