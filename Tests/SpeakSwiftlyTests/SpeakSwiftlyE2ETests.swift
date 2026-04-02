import Foundation
import Testing
@testable import SpeakSwiftly

@Suite(.serialized)
struct SpeakSwiftlyE2ETests {
    private static let testingProfileName = "testing-profile"
    private static let testingProfileText = "Hello there from SpeakSwiftly end-to-end coverage."
    private static let testingProfileVoiceDescription = "A generic, warm, masculine, slow speaking voice."

    @Test func createProfileRunsEndToEndWithRealModelPaths() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true
        )
        defer { Task { await worker.stop() } }

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        } != nil)

        let exportURL = sandbox.rootURL.appendingPathComponent("exports/profile.wav")
        try worker.sendJSON(
            """
            {"id":"req-create","op":"create_profile","profile_name":"\(Self.testingProfileName)","text":"\(Self.testingProfileText)","voice_description":"\(Self.testingProfileVoiceDescription)","output_path":"\(exportURL.path)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-create"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "loading_profile_model"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-create"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "generating_profile_audio"
        } != nil)

        let success = try #require(
            try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
                $0["id"] as? String == "req-create"
                    && $0["ok"] as? Bool == true
            }
        )

        #expect(success["profile_name"] as? String == Self.testingProfileName)
        #expect(success["profile_path"] as? String == sandbox.profileRootURL.appendingPathComponent(Self.testingProfileName).path)

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: Self.testingProfileName)
        #expect(storedProfile.manifest.sourceText == Self.testingProfileText)
        #expect(storedProfile.manifest.voiceDescription == Self.testingProfileVoiceDescription)
        #expect(FileManager.default.fileExists(atPath: storedProfile.referenceAudioURL.path))
        #expect(FileManager.default.fileExists(atPath: exportURL.path))

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    @Test func speakLiveRunsEndToEndWithStoredProfileAndSilentPlayback() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        let worker = try WorkerProcess(
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true
        )
        defer { Task { await worker.stop() } }

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        } != nil)

        try worker.sendJSON(
            """
            {"id":"req-create","op":"create_profile","profile_name":"\(Self.testingProfileName)","text":"\(Self.testingProfileText)","voice_description":"\(Self.testingProfileVoiceDescription)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-create"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.sendJSON(
            """
            {"id":"req-live","op":"speak_live","text":"Hello from the real zero point six billion resident model path.","profile_name":"\(Self.testingProfileName)"}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "speak_live"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-live"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.closeInput()
        try await worker.waitForExit(timeout: .seconds(30))
    }

    private static var e2eTimeout: Duration {
        .seconds(1_200)
    }

    private static var isE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_E2E"] == "1"
    }
}

private struct E2ESandbox {
    let rootURL: URL
    let profileRootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftly-E2E-\(UUID().uuidString)", isDirectory: true)
        profileRootURL = rootURL.appendingPathComponent("profiles", isDirectory: true)

        try FileManager.default.createDirectory(at: profileRootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private final class JSONLineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutObjects = [[String: Any]]()
    private var stderrLines = [String]()

    func appendStdout(_ line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        lock.withLock {
            stdoutObjects.append(object)
        }
    }

    func appendStderr(_ line: String) {
        lock.withLock {
            stderrLines.append(line)
        }
    }

    func firstMatchingJSONObject(_ predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.withLock {
            stdoutObjects.first(where: predicate)
        }
    }

    func stderrText() -> String {
        lock.withLock {
            stderrLines.joined(separator: "\n")
        }
    }
}

private final class WorkerProcess: @unchecked Sendable {
    private enum Environment {
        static let dyldFrameworkPath = "DYLD_FRAMEWORK_PATH"
        static let profileRoot = "SPEAKSWIFTLY_PROFILE_ROOT"
        static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
    }

    private static let executableURLResult = Result(catching: {
        try computeWorkerExecutableURL()
    })

    private let process: Process
    private let stdinPipe: Pipe
    private let recorder: JSONLineRecorder
    private let stdoutTask: Task<Void, Never>
    private let stderrTask: Task<Void, Never>

    init(profileRootURL: URL, silentPlayback: Bool) throws {
        process = Process()
        stdinPipe = Pipe()
        let recorder = JSONLineRecorder()
        self.recorder = recorder
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let executableURL = try Self.workerExecutableURL()
        process.executableURL = executableURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        environment[Environment.dyldFrameworkPath] = executableURL.deletingLastPathComponent().path
        environment[Environment.profileRoot] = profileRootURL.path
        if silentPlayback {
            environment[Environment.silentPlayback] = "1"
        }
        process.environment = environment

        stdoutTask = Self.captureLines(
            from: stdoutPipe.fileHandleForReading,
            append: recorder.appendStdout(_:)
        )

        stderrTask = Self.captureLines(
            from: stderrPipe.fileHandleForReading,
            append: recorder.appendStderr(_:)
        )

        try process.run()
    }

    deinit {
        stdoutTask.cancel()
        stderrTask.cancel()
    }

    func sendJSON(_ jsonLine: String) throws {
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data((jsonLine + "\n").utf8))
    }

    func closeInput() throws {
        try stdinPipe.fileHandleForWriting.close()
    }

    func stop() async {
        if process.isRunning {
            try? closeInput()
            try? await waitForExit(timeout: .seconds(5))
        }

        if process.isRunning {
            process.terminate()
            try? await waitForExit(timeout: .seconds(5))
        }

        stdoutTask.cancel()
        stderrTask.cancel()
    }

    func waitForJSONObject(
        timeout: Duration,
        _ predicate: @escaping @Sendable ([String: Any]) -> Bool
    ) async throws -> [String: Any]? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if let object = recorder.firstMatchingJSONObject(predicate) {
                return object
            }

            if !process.isRunning {
                break
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        if let object = recorder.firstMatchingJSONObject(predicate) {
            return object
        }

        let stderr = recorder.stderrText()
        throw WorkerProcessError(
            "Timed out waiting for a matching worker JSON event. Current stderr:\n\(stderr)"
        )
    }

    func waitForExit(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while process.isRunning && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }

        guard !process.isRunning else {
            let stderr = recorder.stderrText()
            throw WorkerProcessError(
                "The SpeakSwiftly worker did not exit before the timeout expired. Current stderr:\n\(stderr)"
            )
        }

        guard process.terminationStatus == 0 else {
            let stderr = recorder.stderrText()
            throw WorkerProcessError(
                "The SpeakSwiftly worker exited with status \(process.terminationStatus). Current stderr:\n\(stderr)"
            )
        }
    }

    private static func captureLines(
        from fileHandle: FileHandle,
        append: @escaping @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            var buffer = Data()

            while !Task.isCancelled {
                let data = fileHandle.availableData
                guard !data.isEmpty else { break }
                buffer.append(data)

                while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                    let lineData = buffer[..<newlineRange.lowerBound]
                    if let line = String(data: lineData, encoding: .utf8) {
                        append(line)
                    }
                    buffer.removeSubrange(..<newlineRange.upperBound)
                }
            }

            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                append(line)
            }
        }
    }

    private static func workerExecutableURL() throws -> URL {
        try executableURLResult.get()
    }

    private static func computeWorkerExecutableURL() throws -> URL {
        let packageRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let derivedDataURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftly-xcodebuild-e2e-dd", isDirectory: true)
        let sourcePackagesURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftly-xcodebuild-e2e-spm", isDirectory: true)

        try buildWorkerProduct(
            packageRootURL: packageRootURL,
            derivedDataURL: derivedDataURL,
            sourcePackagesURL: sourcePackagesURL
        )

        let productsURL = derivedDataURL
            .appendingPathComponent("Build/Products/Debug", isDirectory: true)
        let executableURL = productsURL.appendingPathComponent("SpeakSwiftly", isDirectory: false)
        let metallibURL = productsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw WorkerProcessError(
                "The Xcode-built SpeakSwiftly worker was expected at '\(executableURL.path)', but no executable was found after `xcodebuild` finished."
            )
        }

        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw WorkerProcessError(
                "The MLX Metal shader bundle was not found at '\(metallibURL.path)' after `xcodebuild` completed. The worker cannot run real MLX-backed e2e tests without `default.metallib`."
            )
        }

        return executableURL
    }

    private static func buildWorkerProduct(
        packageRootURL: URL,
        derivedDataURL: URL,
        sourcePackagesURL: URL
    ) throws {
        let process = Process()
        let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftly-xcodebuild-e2e.log", isDirectory: false)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        process.currentDirectoryURL = packageRootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "build",
            "-scheme", "SpeakSwiftly",
            "-destination", "platform=macOS",
            "-derivedDataPath", derivedDataURL.path,
            "-clonedSourcePackagesDirPath", sourcePackagesURL.path,
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = try Data(contentsOf: logURL)
            let output = String(decoding: outputData, as: UTF8.self)
            throw WorkerProcessError(
                "The Xcode-backed SpeakSwiftly build failed with status \(process.terminationStatus). `xcodebuild` output:\n\(output)"
            )
        }
    }
}

private struct WorkerProcessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
