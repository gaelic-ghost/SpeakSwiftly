import Foundation

// MARK: - Structured Worker Logging

package enum WorkerLogLevel: String, Encodable {
    case info
    case error
}

package enum WorkerLogValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

package struct WorkerLogEvent: Encodable {
    package let event: String
    package let level: WorkerLogLevel
    package let ts: String
    package let requestID: String?
    package let op: String?
    package let profileName: String?
    package let queueDepth: Int?
    package let elapsedMS: Int?
    package let details: [String: WorkerLogValue]?

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

    package init(
        event: String,
        level: WorkerLogLevel,
        ts: String,
        requestID: String?,
        op: String?,
        profileName: String?,
        queueDepth: Int?,
        elapsedMS: Int?,
        details: [String: WorkerLogValue]?
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
        return String(decoding: try encoder.encode(event), as: UTF8.self)
    }

    package static func encodingFailureLine(
        timestamp: String,
        errorDescription: String
    ) -> String {
        #"{"event":"worker_error","level":"error","ts":"\#(timestamp)","details":{"message":"SpeakSwiftly could not encode a stderr log event.","error":"\#(errorDescription)"}}"#
    }
}
