import Foundation
import SpeakSwiftly

// MARK: - Entry Point

@main
enum SpeakSwiftlyTool {
    private enum ArgumentError: LocalizedError {
        case unknown(String)
        case missingValue(String)

        var errorDescription: String? {
            switch self {
                case let .unknown(argument):
                    "Unknown argument '\(argument)'. Supported options: --state-root PATH."
                case let .missingValue(option):
                    "Missing value for \(option)."
            }
        }
    }

    static func main() async {
        do {
            let stateRootURL = try parseStateRootURL(arguments: Array(CommandLine.arguments.dropFirst()))
            let runtime = await SpeakSwiftly.liftoff(stateRootURL: stateRootURL)
            await run(runtime: runtime)
        } catch {
            let message = "SpeakSwiftlyTool could not start because its launch arguments were invalid. \(error.localizedDescription)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            exit(2)
        }
    }

    private static func run(runtime: SpeakSwiftly.Runtime) async {
        let output = ToolJSONLOutput()
        await runtime.tool.useExternalJSONLOutput()
        let outputEvents = await runtime.tool.outputEvents()
        let outputTask = Task {
            for await event in outputEvents {
                await output.write(event)
            }
        }

        await runtime.start()

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                do {
                    let request = try ToolRequest.decode(from: line)
                    await request.submit(to: runtime)
                } catch {
                    await output.writeFailure(for: line, error: error)
                }
            }
        } catch {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let details = [
                "message": WorkerLogValue.string(
                    "SpeakSwiftly stopped reading stdin because the standard input stream failed unexpectedly.",
                ),
                "error": WorkerLogValue.string(error.localizedDescription),
            ]
            let event = WorkerLogEvent(
                event: "stdin_read_failed",
                level: .error,
                ts: timestamp,
                requestID: nil,
                op: nil,
                profileName: nil,
                queueDepth: nil,
                elapsedMS: nil,
                details: details,
            )

            let line = (try? WorkerStructuredLogSupport.encode(event))
                ?? WorkerStructuredLogSupport.encodingFailureLine(
                    timestamp: timestamp,
                    errorDescription: error.localizedDescription,
                )
            try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
        }

        await runtime.shutdown()
        await Task.yield()
        await output.flush()
        outputTask.cancel()
    }

    private static func parseStateRootURL(arguments: [String]) throws -> URL? {
        guard !arguments.isEmpty else { return nil }

        var stateRootURL: URL?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--state-root":
                    index += 1
                    stateRootURL = try URL(
                        fileURLWithPath: requireOptionValue(arguments, index: index, for: argument),
                        isDirectory: true,
                    )
                default:
                    throw ArgumentError.unknown(argument)
            }
            index += 1
        }

        return stateRootURL
    }

    private static func requireOptionValue(
        _ arguments: [String],
        index: Int,
        for option: String,
    ) throws -> String {
        guard index < arguments.count else {
            throw ArgumentError.missingValue(option)
        }

        return arguments[index]
    }
}
