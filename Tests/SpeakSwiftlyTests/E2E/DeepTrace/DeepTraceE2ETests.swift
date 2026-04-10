import Foundation
import Testing
@testable import SpeakSwiftlyCore

extension SpeakSwiftlyE2ETests {
    @Suite("Deep Trace E2E")
    struct DeepTraceSuite {
        @Test func longCodeHeavy() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled, SpeakSwiftlyE2ETests.isDeepTraceE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-deep-trace",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            try worker.sendJSON(
                """
                {"id":"req-live-deep-trace","op":"generate_speech","text":"\(SpeakSwiftlyE2ETests.deepTracePlaybackText.jsonEscaped)","profile_name":"\(SpeakSwiftlyE2ETests.testingProfileName)"}
                """
            )

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-deep-trace"
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "buffering_audio"
            } != nil)
            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-deep-trace"
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "preroll_ready"
            } != nil)

            let playbackFinished = try #require(
                try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
                }
            )

            let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
            #expect((playbackDetails["chunk_count"] as? Int ?? 0) > 1)
            #expect((playbackDetails["sample_count"] as? Int ?? 0) > 0)

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-deep-trace"
                    && $0["ok"] as? Bool == true
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        @Test func segmentedWeirdText() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled, SpeakSwiftlyE2ETests.isDeepTraceE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-segmented",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            try worker.sendJSON(
                """
                {"id":"req-live-segmented","op":"generate_speech","text":"\(SpeakSwiftlyE2ETests.segmentedDeepTracePlaybackText.jsonEscaped)","profile_name":"\(SpeakSwiftlyE2ETests.testingProfileName)"}
                """
            )

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-segmented"
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "preroll_ready"
            } != nil)

            let playbackFinished = try #require(
                try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
                }
            )

            let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
            #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
            #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
            #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-segmented"
                    && $0["ok"] as? Bool == true
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        @Test func reversedSegmentedWeirdText() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled, SpeakSwiftlyE2ETests.isDeepTraceE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-reversed-segmented",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            try worker.sendJSON(
                """
                {"id":"req-live-reversed-segmented","op":"generate_speech","text":"\(SpeakSwiftlyE2ETests.reversedSegmentedDeepTracePlaybackText.jsonEscaped)","profile_name":"\(SpeakSwiftlyE2ETests.testingProfileName)"}
                """
            )

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-reversed-segmented"
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "preroll_ready"
            } != nil)

            let playbackFinished = try #require(
                try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
                }
            )

            let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
            #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
            #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
            #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-reversed-segmented"
                    && $0["ok"] as? Bool == true
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        @Test func segmentedConversationalProse() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled, SpeakSwiftlyE2ETests.isDeepTraceE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-conversational",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            try worker.sendJSON(
                """
                {"id":"req-live-conversational","op":"generate_speech","text":"\(SpeakSwiftlyE2ETests.segmentedConversationalPlaybackText.jsonEscaped)","profile_name":"\(SpeakSwiftlyE2ETests.testingProfileName)"}
                """
            )

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-conversational"
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "preroll_ready"
            } != nil)

            let playbackFinished = try #require(
                try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
                }
            )

            let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
            #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
            #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
            #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-conversational"
                    && $0["ok"] as? Bool == true
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }

        @Test func reversedSegmentedConversationalProse() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled, SpeakSwiftlyE2ETests.isDeepTraceE2EEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: SpeakSwiftlyE2ETests.isPlaybackTraceEnabled
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-reversed-conversational",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            try worker.sendJSON(
                """
                {"id":"req-live-reversed-conversational","op":"generate_speech","text":"\(SpeakSwiftlyE2ETests.reversedSegmentedConversationalPlaybackText.jsonEscaped)","profile_name":"\(SpeakSwiftlyE2ETests.testingProfileName)"}
                """
            )

            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-reversed-conversational"
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "preroll_ready"
            } != nil)

            let playbackFinished = try #require(
                try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
                }
            )

            let playbackDetails = try #require(playbackFinished["details"] as? [String: Any])
            #expect((playbackDetails["rebuffer_event_count"] as? Int ?? 0) >= 0)
            #expect((playbackDetails["normalized_character_count"] as? Int ?? 0) > 0)
            #expect((playbackDetails["section_count"] as? Int ?? 0) >= 5)
            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
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
            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-reversed-conversational"
                    && $0["ok"] as? Bool == true
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }
}
