import Foundation
import SpeakSwiftly

@main
struct SpeakSwiftlyTestingMain {
    enum Command: String {
        case resources
        case status
        case smoke
    }

    static func main() async {
        do {
            try await run()
        } catch {
            fputs("SpeakSwiftlyTesting failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let command = try parseCommand()

        switch command {
        case .resources:
            try printResources()
        case .status:
            try await printStatus()
        case .smoke:
            try printResources()
            try await printStatus()
        }
    }

    static func parseCommand() throws -> Command {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let rawCommand = arguments.first else {
            throw UsageError.missingCommand
        }
        guard let command = Command(rawValue: rawCommand) else {
            throw UsageError.unknownCommand(rawCommand)
        }
        guard arguments.count == 1 else {
            throw UsageError.unexpectedArguments(arguments.dropFirst().joined(separator: " "))
        }
        return command
    }

    static func printResources() throws {
        let packageBundleURL = SpeakSwiftly.SupportResources.bundle.bundleURL
        let mlxBundleURL = try SpeakSwiftly.SupportResources.mlxBundleURL()
        let defaultMetallibURL = try SpeakSwiftly.SupportResources.defaultMetallibURL()

        print("package_bundle: \(packageBundleURL.path)")
        print("mlx_bundle: \(mlxBundleURL.path)")
        print("default_metallib: \(defaultMetallibURL.path)")
    }

    static func printStatus() async throws {
        let runtime = await SpeakSwiftly.liftoff()
        await runtime.start()

        let handle = await runtime.status()
        print("request_id: \(handle.id)")
        print("operation: \(handle.operation)")

        for try await event in handle.events {
            switch event {
            case .queued(let queued):
                print("queued: position=\(queued.queuePosition) reason=\(queued.reason.rawValue)")
            case .acknowledged(let success):
                print("acknowledged: \(formatStatus(success.status))")
                return
            case .started(let started):
                print("started: op=\(started.op)")
            case .progress(let progress):
                print("progress: stage=\(progress.stage.rawValue)")
            case .completed(let success):
                print("completed: \(formatStatus(success.status))")
                return
            }
        }

        throw UsageError.statusStreamEndedWithoutTerminalEvent
    }

    static func formatStatus(_ status: SpeakSwiftly.StatusEvent?) -> String {
        guard let status else {
            return "status payload missing"
        }
        return "stage=\(status.stage.rawValue) resident_state=\(status.residentState.rawValue) speech_backend=\(status.speechBackend.rawValue)"
    }
}

extension SpeakSwiftlyTestingMain {
    enum UsageError: LocalizedError {
        case missingCommand
        case unknownCommand(String)
        case unexpectedArguments(String)
        case statusStreamEndedWithoutTerminalEvent

        var errorDescription: String? {
            switch self {
            case .missingCommand:
                usage
            case .unknownCommand(let command):
                "Unknown SpeakSwiftlyTesting command '\(command)'.\n\(usage)"
            case .unexpectedArguments(let arguments):
                "SpeakSwiftlyTesting received unexpected extra arguments: \(arguments).\n\(usage)"
            case .statusStreamEndedWithoutTerminalEvent:
                "SpeakSwiftlyTesting watched the runtime status stream, but it ended before an acknowledged or completed status payload arrived."
            }
        }

        var usage: String {
            """
            Usage:
              swift run SpeakSwiftlyTesting resources
              swift run SpeakSwiftlyTesting status
              swift run SpeakSwiftlyTesting smoke
            """
        }
    }
}
