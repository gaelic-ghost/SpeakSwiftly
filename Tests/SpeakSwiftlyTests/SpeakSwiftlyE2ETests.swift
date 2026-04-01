import Foundation
import Testing
@testable import SpeakSwiftly

@Suite(.serialized)
struct SpeakSwiftlyE2ETests {
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
            {"id":"req-create","op":"create_profile","profile_name":"e2e-voice","text":"Hello there from SpeakSwiftly end-to-end coverage.","voice_description":"A warm, bright, feminine narrator voice.","output_path":"\(exportURL.path)"}
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

        #expect(success["profile_name"] as? String == "e2e-voice")
        #expect(success["profile_path"] as? String == sandbox.profileRootURL.appendingPathComponent("e2e-voice").path)

        let store = ProfileStore(rootURL: sandbox.profileRootURL)
        let storedProfile = try store.loadProfile(named: "e2e-voice")
        #expect(storedProfile.manifest.sourceText == "Hello there from SpeakSwiftly end-to-end coverage.")
        #expect(storedProfile.manifest.voiceDescription == "A warm, bright, feminine narrator voice.")
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
            {"id":"req-create","op":"create_profile","profile_name":"e2e-live","text":"This is the stored transcript for the live playback path.","voice_description":"A calm, warm, feminine narrator voice."}
            """
        )

        #expect(try await worker.waitForJSONObject(timeout: Self.e2eTimeout) {
            $0["id"] as? String == "req-create"
                && $0["ok"] as? Bool == true
        } != nil)

        try worker.sendJSON(
            """
            {"id":"req-live","op":"speak_live","text":"Hello from the real zero point six billion resident model path.","profile_name":"e2e-live"}
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
        static let profileRoot = "SPEAKSWIFTLY_PROFILE_ROOT"
        static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
    }

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

        process.executableURL = try Self.workerExecutableURL()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment[Environment.profileRoot] = profileRootURL.path
        if silentPlayback {
            environment[Environment.silentPlayback] = "1"
        }
        process.environment = environment

        stdoutTask = Task {
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    recorder.appendStdout(line)
                }
            } catch {}
        }

        stderrTask = Task {
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    recorder.appendStderr(line)
                }
            } catch {}
        }

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

    private static func workerExecutableURL() throws -> URL {
        let packageRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildRootURL = packageRootURL.appendingPathComponent(".build", isDirectory: true)

        let candidateURLs = try FileManager.default.subpathsOfDirectory(atPath: buildRootURL.path)
            .filter { $0.hasSuffix("/debug/SpeakSwiftly") || $0 == "debug/SpeakSwiftly" }
            .map { buildRootURL.appendingPathComponent($0) }

        if let executableURL = candidateURLs.sorted(by: { $0.path < $1.path }).first {
            return executableURL
        }

        throw WorkerProcessError(
            "The SpeakSwiftly executable could not be found under '\(buildRootURL.path)'. Run `swift build` before the e2e suite."
        )
    }
}

private struct WorkerProcessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
