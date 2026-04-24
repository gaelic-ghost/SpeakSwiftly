#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

@Suite(
    .serialized,
    .tags(.e2e, .deepTrace, .trace),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
    .enabled(
        if: speakSwiftlyDeepTraceE2ETestsEnabled(),
        "This deep-trace suite is opt-in and requires SPEAKSWIFTLY_DEEP_TRACE_E2E=1.",
    ),
)
struct DeepTraceE2ETests {
    @Test func `long code heavy`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-live-deep-trace","op":"generate_speech","text":"\(E2EHarness.deepTracePlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-deep-trace"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-deep-trace"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-deep-trace",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return details["chunk_count"] as? Int != nil
                    && details["sample_count"] as? Int != nil
                    && details["time_to_first_chunk_ms"] as? Int != nil
                    && details["time_to_preroll_ready_ms"] as? Int != nil
                    && details["schedule_callback_count"] as? Int != nil
                    && details["played_back_callback_count"] as? Int != nil
            },
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["chunk_count"] as? Int ?? 0) > 1)
        #expect((playbackDetails["sample_count"] as? Int ?? 0) > 0)

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-deep-trace"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `segmented weird text`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-live-segmented","op":"generate_speech","text":"\(E2EHarness.segmentedDeepTracePlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-segmented"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-segmented",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["url_count"] as? Int ?? 0) >= 1
                    && (details["file_path_count"] as? Int ?? 0) >= 1
                    && (details["dotted_identifier_count"] as? Int ?? 0) >= 2
                    && (details["camel_case_token_count"] as? Int ?? 0) >= 1
                    && (details["snake_case_token_count"] as? Int ?? 0) >= 1
                    && (details["objc_symbol_count"] as? Int ?? 0) >= 1
                    && (details["repeated_letter_run_count"] as? Int ?? 0) >= 2
            },
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-segmented",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Section Two"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-segmented"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `reversed segmented weird text`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-live-reversed-segmented","op":"generate_speech","text":"\(E2EHarness.reversedSegmentedDeepTracePlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-segmented"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-reversed-segmented",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["url_count"] as? Int ?? 0) >= 1
                    && (details["file_path_count"] as? Int ?? 0) >= 1
                    && (details["dotted_identifier_count"] as? Int ?? 0) >= 2
                    && (details["camel_case_token_count"] as? Int ?? 0) >= 1
                    && (details["snake_case_token_count"] as? Int ?? 0) >= 1
                    && (details["objc_symbol_count"] as? Int ?? 0) >= 1
                    && (details["repeated_letter_run_count"] as? Int ?? 0) >= 2
            },
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-reversed-segmented",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Footer"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-segmented"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `segmented conversational prose`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-live-conversational","op":"generate_speech","text":"\(E2EHarness.segmentedConversationalPlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-conversational"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-conversational",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["file_path_count"] as? Int ?? 0) == 0
                    && (details["dotted_identifier_count"] as? Int ?? 0) == 0
                    && (details["camel_case_token_count"] as? Int ?? 0) == 0
                    && (details["snake_case_token_count"] as? Int ?? 0) == 0
                    && (details["objc_symbol_count"] as? Int ?? 0) == 0
                    && (details["repeated_letter_run_count"] as? Int ?? 0) == 0
            },
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-conversational",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Section Two"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-conversational"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func `reversed segmented conversational prose`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        )
        defer { Task { await worker.stop() } }

        try await E2EHarness.awaitWorkerReady(worker)
        try sandbox.seedProfileFixture(.mascDesign, as: E2EHarness.testingProfileName)

        try worker.sendJSON(
            """
            {"id":"req-live-reversed-conversational","op":"generate_speech","text":"\(E2EHarness.reversedSegmentedConversationalPlaybackText.jsonEscaped)","profile_name":"\(E2EHarness.testingProfileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-conversational"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == "req-live-reversed-conversational",
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                return (details["markdown_header_count"] as? Int ?? 0) >= 5
                    && (details["file_path_count"] as? Int ?? 0) == 0
                    && (details["dotted_identifier_count"] as? Int ?? 0) == 0
                    && (details["camel_case_token_count"] as? Int ?? 0) == 0
                    && (details["snake_case_token_count"] as? Int ?? 0) == 0
                    && (details["objc_symbol_count"] as? Int ?? 0) == 0
                    && (details["repeated_letter_run_count"] as? Int ?? 0) == 0
            },
        )

        let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
        #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
        #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
        #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
        #expect(try await worker.waitForStderrJSONObject(timeout: E2EHarness.e2eTimeout) {
            guard
                $0["event"] as? String == "playback_section_window",
                $0["request_id"] as? String == "req-live-reversed-conversational",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["section_title"] as? String == "Footer"
                && (details["estimated_end_ms"] as? Int ?? 0) > (details["estimated_start_ms"] as? Int ?? 0)
                && (details["estimated_end_chunk"] as? Int ?? 0) > (details["estimated_start_chunk"] as? Int ?? 0)
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: E2EHarness.e2eTimeout) {
            $0["id"] as? String == "req-live-reversed-conversational"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }
}
#endif
