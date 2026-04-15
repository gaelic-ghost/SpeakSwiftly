import Foundation
@testable import SpeakSwiftly
import Testing

// MARK: - Structured Logging

@Test func `structured worker log support encodes stable JSONL shape`() throws {
    let line = try WorkerStructuredLogSupport.encode(
        WorkerLogEvent(
            event: "stdin_read_failed",
            level: .error,
            ts: "2026-04-08T12:00:00Z",
            requestID: nil,
            op: nil,
            profileName: nil,
            queueDepth: nil,
            elapsedMS: nil,
            details: [
                "message": .string("stdin failed"),
                "error": .string("Broken pipe"),
            ],
        ),
    )

    let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
    )
    let details = try #require(object["details"] as? [String: Any])
    #expect(object["event"] as? String == "stdin_read_failed")
    #expect(object["level"] as? String == "error")
    #expect(details["message"] as? String == "stdin failed")
    #expect(details["error"] as? String == "Broken pipe")
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
