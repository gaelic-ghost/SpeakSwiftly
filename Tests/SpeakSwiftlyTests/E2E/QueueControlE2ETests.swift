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
struct QueueControlE2ETests {
    private static let queueControlTimeout: Duration = .seconds(180)

    @Test func `generation queue clear and cancel stay generation scoped`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .chatterboxTurbo,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-generation-active-e2e","op":"generate_audio_file","text":"\(E2EHarness.testingPlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-generation-active-e2e"
                && $0["event"] as? String == "started"
        })

        try worker.sendJSON(
            """
            {"id":"req-generation-queued-e2e","op":"generate_audio_file","text":"\(E2EHarness.testingPlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-generation-queued-e2e"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_active_request"
        })

        try worker.sendJSON(
            """
            {"id":"req-clear-playback-e2e","op":"clear_playback_queue"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-clear-playback-e2e"
                && $0["ok"] as? Bool == true
                && $0["cleared_count"] as? Int == 0
        })

        try worker.sendJSON(
            """
            {"id":"req-clear-generation-e2e","op":"clear_generation_queue"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-clear-generation-e2e"
                && $0["ok"] as? Bool == true
                && $0["cleared_count"] as? Int == 1
        })
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-generation-queued-e2e"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        })

        try worker.sendJSON(
            """
            {"id":"req-cancel-generation-e2e","op":"cancel_generation","request_id":"req-generation-active-e2e"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-cancel-generation-e2e"
                && $0["ok"] as? Bool == true
                && $0["cancelled_request_id"] as? String == "req-generation-active-e2e"
        })
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-generation-active-e2e"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        })

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `playback cancel stops active live playback`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            speechBackend: .chatterboxTurbo,
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-playback-active-e2e","op":"generate_speech","text":"\(E2EHarness.testingPlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-playback-active-e2e"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "starting_playback"
        })

        try worker.sendJSON(
            """
            {"id":"req-cancel-playback-e2e","op":"cancel_playback","request_id":"req-playback-active-e2e"}
            """,
        )
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-cancel-playback-e2e"
                && $0["ok"] as? Bool == true
                && $0["cancelled_request_id"] as? String == "req-playback-active-e2e"
        })
        _ = try #require(try await worker.waitForJSONObject(timeout: Self.queueControlTimeout) {
            $0["id"] as? String == "req-playback-active-e2e"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        })

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
