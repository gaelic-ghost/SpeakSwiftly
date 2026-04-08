import Foundation
import SpeakSwiftlyCore

// MARK: - Entry Point

@main
enum SpeakSwiftlyCLI {
    static func main() async {
        let runtime = await SpeakSwiftly.live()
        await runtime.start()

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                await runtime.accept(line: line)
            }
        } catch {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let details = [
                "message": WorkerLogValue.string(
                    "SpeakSwiftly stopped reading stdin because the standard input stream failed unexpectedly."
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
                details: details
            )

            let line = (try? WorkerStructuredLogSupport.encode(event))
                ?? WorkerStructuredLogSupport.encodingFailureLine(
                    timestamp: timestamp,
                    errorDescription: error.localizedDescription
                )
            try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
        }

        await runtime.shutdown()
    }
}
