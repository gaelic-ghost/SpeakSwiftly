import Foundation
import PackagePlugin

@main
struct UpsertSystemVoiceProfilePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let options = try Options(arguments: arguments)
        guard let target = context.package.targets.first(where: { $0.name == options.target }) else {
            throw PluginError.unknownTarget(options.target)
        }

        let resourceRootURL = target.directoryURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("SystemProfiles", isDirectory: true)

        try FileManager.default.createDirectory(at: resourceRootURL, withIntermediateDirectories: true)

        let request = ToolRequest(
            id: "upsert-system-voice-profile-\(UUID().uuidString)",
            profileName: options.name,
            text: options.text,
            vibe: options.vibe,
            voiceDescription: options.voiceDescription,
            seedID: options.seedID,
            seedVersion: options.seedVersion,
            sourcePackage: context.package.displayName,
            sourceVersion: options.sourceVersion,
        )
        let tool = try context.tool(named: "SpeakSwiftlyTool")
        try runTool(at: tool.url, resourceRootURL: resourceRootURL, request: request)

        Diagnostics.remark(
            "Upserted SpeakSwiftly system voice profile '\(options.name)' under \(resourceRootURL.path)/profiles. Ensure target '\(options.target)' declares .copy(\"Resources/SystemProfiles\") and passes SpeakSwiftly.SupportResources.systemProfileRootURL(in: .module) through SpeakSwiftly.Configuration(systemProfileResourceRoots:).",
        )
    }

    private func runTool(
        at toolURL: URL,
        resourceRootURL: URL,
        request: ToolRequest,
    ) throws {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = [
            "--system-profile-resource-root",
            resourceRootURL.path,
        ]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output

        var inputIsOpen = true
        defer {
            if inputIsOpen {
                try? input.fileHandleForWriting.close()
            }
            if process.isRunning {
                process.waitUntilExit()
            }
        }

        try process.run()

        let requestLine = try request.encodedLine()
        try input.fileHandleForWriting.write(contentsOf: Data((requestLine + "\n").utf8))

        let result = try waitForToolResult(requestID: request.id, output: output)
        try input.fileHandleForWriting.close()
        inputIsOpen = false

        if process.isRunning {
            process.waitUntilExit()
        }

        guard process.terminationStatus == 0 else {
            throw PluginError.toolFailed(status: process.terminationStatus)
        }
        guard result.ok else {
            throw PluginError.requestFailed(message: result.message)
        }
    }

    private func waitForToolResult(requestID: String, output: Pipe) throws -> ToolResult {
        var bufferedOutput = Data()

        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                throw PluginError.toolClosedBeforeResponse(requestID)
            }

            bufferedOutput.append(chunk)

            while let newline = bufferedOutput.firstIndex(of: 0x0A) {
                let lineData = bufferedOutput[..<newline]
                bufferedOutput.removeSubrange(...newline)
                guard !lineData.isEmpty else {
                    continue
                }

                let decoded = try JSONSerialization.jsonObject(with: Data(lineData))
                guard let payload = decoded as? [String: Any],
                      payload["id"] as? String == requestID
                else {
                    continue
                }
                guard let ok = payload["ok"] as? Bool else {
                    continue
                }

                return ToolResult(
                    ok: ok,
                    message: payload["message"] as? String
                        ?? payload["error"] as? String
                        ?? "SpeakSwiftlyTool returned a failure response for request '\(requestID)'.",
                )
            }
        }
    }
}

private struct ToolResult {
    let ok: Bool
    let message: String
}

private struct Options {
    let target: String
    let name: String
    let text: String
    let vibe: String
    let voiceDescription: String
    let seedID: String
    let seedVersion: String
    let sourceVersion: String?

    init(arguments: [String]) throws {
        var target: String?
        var name: String?
        var text: String?
        var vibe = "femme"
        var voiceDescription: String?
        var seedID: String?
        var seedVersion = "1"
        var sourceVersion: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
                case "--target":
                    index += 1
                    target = try Self.value(arguments, at: index, for: argument)
                case "--name":
                    index += 1
                    name = try Self.value(arguments, at: index, for: argument)
                case "--text":
                    index += 1
                    text = try Self.value(arguments, at: index, for: argument)
                case "--vibe":
                    index += 1
                    vibe = try Self.value(arguments, at: index, for: argument)
                case "--voice-description":
                    index += 1
                    voiceDescription = try Self.value(arguments, at: index, for: argument)
                case "--seed-id":
                    index += 1
                    seedID = try Self.value(arguments, at: index, for: argument)
                case "--seed-version":
                    index += 1
                    seedVersion = try Self.value(arguments, at: index, for: argument)
                case "--source-version":
                    index += 1
                    sourceVersion = try Self.value(arguments, at: index, for: argument)
                case "--help", "-h":
                    throw PluginError.helpRequested
                default:
                    throw PluginError.unknownArgument(argument)
            }
            index += 1
        }

        self.target = try Self.required(target, name: "--target")
        self.name = try Self.required(name, name: "--name")
        self.text = try Self.required(text, name: "--text")
        self.vibe = vibe
        self.voiceDescription = try Self.required(voiceDescription, name: "--voice-description")
        self.seedID = seedID ?? self.name
        self.seedVersion = seedVersion
        self.sourceVersion = sourceVersion
    }

    private static func value(_ arguments: [String], at index: Int, for option: String) throws -> String {
        guard index < arguments.count else {
            throw PluginError.missingValue(option)
        }

        return arguments[index]
    }

    private static func required(_ value: String?, name: String) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            throw PluginError.missingRequiredOption(name)
        }

        return value
    }
}

private struct ToolRequest: Encodable {
    let id: String
    let op = "upsert_system_voice_profile_from_description"
    let profileName: String
    let text: String
    let vibe: String
    let voiceDescription: String
    let seedID: String
    let seedVersion: String
    let sourcePackage: String
    let sourceVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
        case text
        case vibe
        case voiceDescription = "voice_description"
        case seedID = "seed_id"
        case seedVersion = "seed_version"
        case sourcePackage = "source_package"
        case sourceVersion = "source_version"
    }

    func encodedLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let line = String(data: data, encoding: .utf8) else {
            throw PluginError.requestEncodingFailed
        }

        return line
    }
}

private enum PluginError: Error, CustomStringConvertible {
    case helpRequested
    case missingRequiredOption(String)
    case missingValue(String)
    case unknownTarget(String)
    case unknownArgument(String)
    case requestEncodingFailed
    case toolClosedBeforeResponse(String)
    case toolFailed(status: Int32)
    case requestFailed(message: String)

    var description: String {
        switch self {
            case .helpRequested:
                """
                Usage: swift package plugin --allow-writing-to-package-directory upsert-system-voice-profile --target TARGET --name PROFILE_NAME --text TEXT --vibe femme|masc --voice-description DESCRIPTION [--seed-id ID] [--seed-version VERSION] [--source-version VERSION]
                """
            case let .missingRequiredOption(option):
                "Missing required option \(option). Run with --help for usage."
            case let .missingValue(option):
                "Missing value for \(option). Run with --help for usage."
            case let .unknownTarget(target):
                "No target named '\(target)' exists in this package. Pass the consumer target that will own Resources/SystemProfiles."
            case let .unknownArgument(argument):
                "Unknown argument '\(argument)'. Run with --help for usage."
            case .requestEncodingFailed:
                "UpsertSystemVoiceProfile could not encode the JSONL request for SpeakSwiftlyTool."
            case let .toolClosedBeforeResponse(requestID):
                "SpeakSwiftlyTool exited before returning a result for system-profile request '\(requestID)'."
            case let .toolFailed(status):
                "SpeakSwiftlyTool exited with status \(status) while upserting the system voice profile."
            case let .requestFailed(message):
                message
        }
    }
}
