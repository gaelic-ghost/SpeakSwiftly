import Foundation
import SpeakSwiftly

actor ToolJSONLOutput {
    private let encoder: JSONEncoder
    private let writeStdout: @Sendable (Data) throws -> Void

    init(writeStdout: @escaping @Sendable (Data) throws -> Void = ToolJSONLOutput.writeStandardOutput) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        self.encoder = encoder
        self.writeStdout = writeStdout
    }

    private static func bestEffortID(from line: String) -> String {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.isEmpty
        else {
            return "unknown"
        }

        return id
    }

    private static func writeStandardOutput(_ data: Data) throws {
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    func write(_ event: SpeakSwiftly.WorkerOutputEvent) async {
        switch event {
            case let .status(status):
                await write(status)
            case let .queued(queued):
                await write(queued)
            case let .started(started):
                await write(started)
            case let .progress(progress):
                await write(progress)
            case let .success(success):
                await write(success)
            case let .failure(failure):
                await write(failure)
        }
    }

    func writeFailure(for line: String, error: any Swift.Error) async {
        let toolError: SpeakSwiftly.Error = if let error = error as? SpeakSwiftly.Error {
            error
        } else {
            SpeakSwiftly.Error(
                code: .internalError,
                message: "The request could not be decoded due to an unexpected internal error. \(error.localizedDescription)",
            )
        }

        await write(
            SpeakSwiftly.Failure(
                id: Self.bestEffortID(from: line),
                code: toolError.code,
                message: toolError.message,
            ),
        )
    }

    func flush() {}

    private func write(_ value: some Encodable) async {
        do {
            let data = try encoder.encode(value) + Data("\n".utf8)
            try writeStdout(data)
        } catch {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let message = #"{"event":"tool_output_error","level":"error","message":"SpeakSwiftlyTool could not write a JSONL event to stdout.","ts":"\#(timestamp)"}"#
            fputs(message + "\n", stderr)
        }
    }
}
