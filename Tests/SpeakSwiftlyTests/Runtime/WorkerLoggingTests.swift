import Foundation
@testable import SpeakSwiftly
import Testing

// MARK: - Structured Logging

@Test func `structured worker log support encodes stable JSONL shape`() throws {
    let line = try WorkerStructuredLogSupport.encode(
        WorkerLogEvent(
            event: "playback_generation_quality_warning",
            level: .warning,
            ts: "2026-04-08T12:00:00Z",
            requestID: "req-quality",
            op: "generate_speech",
            profileName: "default-femme",
            queueDepth: nil,
            elapsedMS: 1200,
            details: [
                "reason": .string("repeated_non_silent_window"),
                "message": .string("repeated non-silent window"),
            ],
        ),
    )

    let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
    )
    let details = try #require(object["details"] as? [String: Any])
    #expect(object["event"] as? String == "playback_generation_quality_warning")
    #expect(object["level"] as? String == "warning")
    #expect(object["request_id"] as? String == "req-quality")
    #expect(object["elapsed_ms"] as? Int == 1200)
    #expect(details["reason"] as? String == "repeated_non_silent_window")
    #expect(details["message"] as? String == "repeated non-silent window")
}

@Test func `structured worker log support falls back to structured worker error line`() throws {
    let line = WorkerStructuredLogSupport.encodingFailureLine(
        timestamp: "2026-04-08T12:00:00Z",
        errorDescription: "encoding exploded",
    )

    let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
    )
    let details = try #require(object["details"] as? [String: Any])
    #expect(object["event"] as? String == "worker_error")
    #expect(object["level"] as? String == "error")
    #expect(details["message"] as? String == "SpeakSwiftly could not encode a stderr log event.")
    #expect(details["error"] as? String == "encoding exploded")
}
