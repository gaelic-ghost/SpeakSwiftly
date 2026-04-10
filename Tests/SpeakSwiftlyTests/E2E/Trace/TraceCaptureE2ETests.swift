import Foundation
import Testing
@testable import SpeakSwiftlyCore

extension SpeakSwiftlyE2ETests {
    @Suite("Trace Capture E2E")
    struct TraceCaptureSuite {
        @Test func captureOnDemand() async throws {
            guard SpeakSwiftlyE2ETests.isE2EEnabled, SpeakSwiftlyE2ETests.isPlaybackTraceEnabled else { return }

            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            let worker = try WorkerProcess(
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: true
            )
            defer { Task { await worker.stop() } }

            try await SpeakSwiftlyE2ETests.awaitWorkerReady(worker, expectPlaybackEngine: true)
            try await SpeakSwiftlyE2ETests.createVoiceDesignProfile(
                on: worker,
                id: "req-create-trace",
                profileName: SpeakSwiftlyE2ETests.testingProfileName,
                text: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voiceDescription: SpeakSwiftlyE2ETests.testingProfileVoiceDescription
            )

            try worker.sendJSON(
                """
                {"id":"req-live-trace","op":"generate_speech","text":"\(SpeakSwiftlyE2ETests.testingPlaybackText)","profile_name":"\(SpeakSwiftlyE2ETests.testingProfileName)"}
                """
            )

            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["event"] as? String == "playback_trace_chunk_received"
                    && $0["request_id"] as? String == "req-live-trace"
            } != nil)
            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["event"] as? String == "playback_trace_buffer_scheduled"
                    && $0["request_id"] as? String == "req-live-trace"
            } != nil)
            #expect(try await worker.waitForStderrJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["event"] as? String == "playback_trace_buffer_played_back"
                    && $0["request_id"] as? String == "req-live-trace"
            } != nil)
            #expect(try await worker.waitForJSONObject(timeout: SpeakSwiftlyE2ETests.e2eTimeout) {
                $0["id"] as? String == "req-live-trace"
                    && $0["ok"] as? Bool == true
            } != nil)

            try worker.closeInput()
            try await worker.waitForExit(timeout: .seconds(30))
        }
    }
}
