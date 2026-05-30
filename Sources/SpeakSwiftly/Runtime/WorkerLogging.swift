import Foundation
import OSLog

package enum WorkerLogLevel: String, Encodable {
    case info
    case warning
    case error
}

package enum WorkerLogValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case let .string(value):
                try container.encode(value)
            case let .int(value):
                try container.encode(value)
            case let .double(value):
                try container.encode(value)
            case let .bool(value):
                try container.encode(value)
        }
    }
}

package struct WorkerLogEvent: Encodable {
    package enum CodingKeys: String, CodingKey {
        case event
        case level
        case ts
        case requestID = "request_id"
        case op
        case profileName = "profile_name"
        case queueDepth = "queue_depth"
        case elapsedMS = "elapsed_ms"
        case details
    }

    package let event: String
    package let level: WorkerLogLevel
    package let ts: String
    package let requestID: String?
    package let op: String?
    package let profileName: String?
    package let queueDepth: Int?
    package let elapsedMS: Int?
    package let details: [String: WorkerLogValue]?

    package init(
        event: String,
        level: WorkerLogLevel,
        ts: String,
        requestID: String?,
        op: String?,
        profileName: String?,
        queueDepth: Int?,
        elapsedMS: Int?,
        details: [String: WorkerLogValue]?,
    ) {
        self.event = event
        self.level = level
        self.ts = ts
        self.requestID = requestID
        self.op = op
        self.profileName = profileName
        self.queueDepth = queueDepth
        self.elapsedMS = elapsedMS
        self.details = details
    }
}

package enum WorkerStructuredLogSupport {
    package static func encode(_ event: WorkerLogEvent) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(decoding: encoder.encode(event), as: UTF8.self)
    }

    package static func encodingFailureLine(
        timestamp: String,
        errorDescription: String,
    ) -> String {
        #"{"event":"worker_error","level":"error","ts":"\#(timestamp)","details":{"message":"SpeakSwiftly could not encode a stderr log event.","error":"\#(errorDescription)"}}"#
    }
}

package struct WorkerSystemLogger {
    package static let live = WorkerSystemLogger(
        logger: Logger(subsystem: "com.gaelic-ghost.SpeakSwiftly", category: "worker"),
    )

    private let logger: Logger

    package init(logger: Logger) {
        self.logger = logger
    }

    package func log(_ event: WorkerLogEvent) {
        let summary = [
            "event=\(event.event)",
            event.requestID.map { "request_id=\($0)" },
            event.op.map { "op=\($0)" },
            event.profileName.map { "profile_name=\($0)" },
            event.elapsedMS.map { "elapsed_ms=\($0)" },
            warningReasonSummary(for: event),
        ]
        .compactMap(\.self)
        .joined(separator: " ")

        switch event.level {
            case .info:
                logger.info("\(summary, privacy: .public)")
            case .warning:
                logger.warning("\(summary, privacy: .public)")
            case .error:
                logger.error("\(summary, privacy: .public)")
        }
    }

    private func warningReasonSummary(for event: WorkerLogEvent) -> String? {
        guard event.level == .warning, let reason = event.details?["reason"] else { return nil }

        return "reason=\(compactSystemLogValue(reason))"
    }

    private func compactSystemLogValue(_ value: WorkerLogValue) -> String {
        switch value {
            case let .string(string):
                string
            case let .int(int):
                String(int)
            case let .double(double):
                String(double)
            case let .bool(bool):
                String(bool)
        }
    }
}
