#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

extension SpeakSwiftlyE2ETests {
    static var isQwenBenchmarkE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_E2E"] == "1"
    }

    static var qwenBenchmarkIterations: Int {
        let rawValue = ProcessInfo.processInfo.environment["SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS"] ?? ""
        return max(1, Int(rawValue) ?? 1)
    }

    static let testingProfileName = "testing-profile"
    static let testingProfileText = "Hello there from SpeakSwiftly end-to-end coverage."
    static let testingProfileVoiceDescription = "A generic, warm, masculine, slow speaking voice."
    static let testingCloneSourceText = """
    This imported reference audio should let SpeakSwiftly build a clone profile for end to end coverage with a clean transcript and steady speech.
    """
    static let testingPlaybackText = """
    Hello from the real resident SpeakSwiftly playback path. This end to end test now uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.
    """
    static let deepTracePlaybackText = """
    Deep trace playback probe begins now. Please read this exactly once and do not repeat yourself.
    The path `/Users/galew/Workspace/speak-to-user-mcp/src/speak_to_user_mcp/speakswiftly.py` contains a helper named `SpeakSwiftlyOwner.speak_live`.
    The config file `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift` should be spoken as plain speech rather than spiraling into code noise.
    Read this fenced code sample calmly.
    ```swift
    let sourcePath = "/Users/galew/Workspace/speak-to-user-mcp/src/speak_to_user_mcp/speakswiftly.py"
    let weirdWords = ["Xobni", "quizzaciously", "Cwmfjord", "phthalo", "lophophore"]
    let fallback = weirdWords.first(where: { $0.hasPrefix("q") }) ?? "nothing"
    print(sourcePath, fallback)
    ```
    Also read these oddly spelled words once each: quizzaciously, xylophonic, cwmfjord, lophophore, phthalo, zyzzyva.
    Finish with this sentence exactly once. End of deep trace playback probe.
    """
    static let segmentedDeepTracePlaybackText = """
    # Section One

    Please read this paragraph once and keep a natural tone. The path `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift` should sound like speech, not code noise.

    ## Section Two

    Read these symbol-heavy identifiers carefully: NSApplication.didFinishLaunchingNotification, AVAudioEngine.mainMixerNode, dot.syntax.stuff, camelCaseStuff, snake_case_stuff, `profile?.sampleRate ?? 24000`, and the URL https://example.com/deep-trace.

    ## Section Three

    ```objc
    @property(nonatomic, strong) NSString *displayName;
    [NSFileManager.defaultManager fileExistsAtPath:@"/tmp/Thing"];
    ```

    ## Section Four

    Also read these words once each: chrommmaticallly, qqqwweerrtyy, phthalo, zyzzyva, lophophore.

    ## Footer

    End this segmented deep trace playback probe once, clearly, and without looping.
    """
    static let reversedSegmentedDeepTracePlaybackText = """
    # Footer

    End this segmented deep trace playback probe once, clearly, and without looping.

    ## Section Four

    Also read these words once each: chrommmaticallly, qqqwweerrtyy, phthalo, zyzzyva, lophophore.

    ## Section Three

    ```objc
    @property(nonatomic, strong) NSString *displayName;
    [NSFileManager.defaultManager fileExistsAtPath:@"/tmp/Thing"];
    ```

    ## Section Two

    Read these symbol-heavy identifiers carefully: NSApplication.didFinishLaunchingNotification, AVAudioEngine.mainMixerNode, dot.syntax.stuff, camelCaseStuff, snake_case_stuff, `profile?.sampleRate ?? 24000`, and the URL https://example.com/deep-trace.

    ## Section One

    Please read this paragraph once and keep a natural tone. The path `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift` should sound like speech, not code noise.
    """
    static let segmentedConversationalPlaybackText = """
    # Section One

    Please read this opening section in a steady, friendly tone. We are checking how the worker sounds over a longer stretch of ordinary conversational prose, with enough breathing room and variety to make the trace useful instead of tiny and noisy.

    ## Section Two

    In this part, talk as if you are explaining a thoughtful idea to one person who is listening closely. Keep the pacing natural, let the phrasing stay connected, and avoid sounding clipped, rushed, or overly dramatic.

    ## Section Three

    Now continue with a calmer reflective paragraph about a quiet afternoon, a cup of tea, a patch of sun on the floor, and the feeling that time has slowed down just enough for the room to seem gentle and easy to inhabit.

    ## Section Four

    Finish the body with another plain spoken paragraph about wrapping up a task, setting the last page in order, and feeling relieved that the long careful effort has finally started to come together in a satisfying way.

    ## Footer

    End this conversational deep trace playback probe once, clearly, and without looping.
    """
    static let reversedSegmentedConversationalPlaybackText = """
    # Footer

    End this conversational deep trace playback probe once, clearly, and without looping.

    ## Section Four

    Finish the body with another plain spoken paragraph about wrapping up a task, setting the last page in order, and feeling relieved that the long careful effort has finally started to come together in a satisfying way.

    ## Section Three

    Now continue with a calmer reflective paragraph about a quiet afternoon, a cup of tea, a patch of sun on the floor, and the feeling that time has slowed down just enough for the room to seem gentle and easy to inhabit.

    ## Section Two

    In this part, talk as if you are explaining a thoughtful idea to one person who is listening closely. Keep the pacing natural, let the phrasing stay connected, and avoid sounding clipped, rushed, or overly dramatic.

    ## Section One

    Please read this opening section in a steady, friendly tone. We are checking how the worker sounds over a longer stretch of ordinary conversational prose, with enough breathing room and variety to make the trace useful instead of tiny and noisy.
    """

    static func awaitWorkerReady(
        _ worker: WorkerProcess,
    ) async throws {
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        } != nil)
    }

    static func createVoiceDesignProfile(
        on worker: WorkerProcess,
        id: String,
        profileName: String,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        outputURL: URL? = nil,
    ) async throws {
        if let outputURL {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
        }

        let outputPathFragment = outputURL.map { #","output_path":"\#($0.path)""# } ?? ""
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"create_voice_profile_from_description","profile_name":"\(profileName)","text":"\(text.jsonEscaped)","vibe":"\(vibe.rawValue)","voice_description":"\(voiceDescription.jsonEscaped)"\(outputPathFragment)}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "loading_profile_model"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "generating_profile_audio"
        } != nil)

        let success = try #require(
            try await worker.waitForJSONObject(timeout: e2eTimeout) {
                $0["id"] as? String == id
                    && $0["ok"] as? Bool == true
            },
        )

        #expect(success["profile_name"] as? String == profileName)
        if let outputURL {
            #expect(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    static func createCloneProfile(
        on worker: WorkerProcess,
        id: String,
        profileName: String,
        referenceAudioURL: URL,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        expectTranscription: Bool,
    ) async throws {
        let transcriptFragment = transcript.map { #","transcript":"\#($0.jsonEscaped)""# } ?? ""
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"create_voice_profile_from_audio","profile_name":"\(profileName)","reference_audio_path":"\(referenceAudioURL.path)","vibe":"\(vibe.rawValue)"\(transcriptFragment)}
            """,
        )

        if expectTranscription {
            #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
                $0["id"] as? String == id
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "loading_clone_transcription_model"
            } != nil)
            #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
                $0["id"] as? String == id
                    && $0["event"] as? String == "progress"
                    && $0["stage"] as? String == "transcribing_clone_audio"
            } != nil)
        }

        let success = try #require(
            try await worker.waitForJSONObject(timeout: e2eTimeout) {
                $0["id"] as? String == id
                    && $0["ok"] as? Bool == true
            },
        )

        #expect(success["profile_name"] as? String == profileName)
    }

    static func runSilentSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String,
    ) async throws {
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"generate_speech","text":"\(text.jsonEscaped)","profile_name":"\(profileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_speech"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
        } != nil)
    }

    static func runLiveSpeechForCurrentE2EMode(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String,
    ) async throws {
        if isAudibleE2EEnabled {
            try await runAudibleSpeech(
                on: worker,
                id: id,
                text: text,
                profileName: profileName,
            )
        } else {
            try await runSilentSpeech(
                on: worker,
                id: id,
                text: text,
                profileName: profileName,
            )
        }
    }

    static func runAudibleSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String,
    ) async throws {
        try await queueAudibleSpeech(
            on: worker,
            id: id,
            text: text,
            profileName: profileName,
        )
        _ = try await awaitAudibleSpeechCompletion(
            on: worker,
            id: id,
        )
    }

    static func queueAudibleSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String,
    ) async throws {
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"generate_speech","text":"\(text.jsonEscaped)","profile_name":"\(profileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
        } != nil)
    }

    @discardableResult
    static func awaitAudibleSpeechCompletion(
        on worker: WorkerProcess,
        id: String,
    ) async throws -> [String: Any] {
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        } != nil)
        #expect(try await worker.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_started",
                $0["request_id"] as? String == id,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String

            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && (details["startup_buffer_target_ms"] as? Int ?? 0) >= 360
                && details["startup_buffered_audio_ms"] as? Int != nil
                && details["process_phys_footprint_bytes"] as? Int != nil
                && details["process_resident_bytes"] as? Int != nil
                && details["process_user_cpu_time_ns"] as? Int != nil
                && details["process_system_cpu_time_ns"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
                && details["mlx_cache_memory_bytes"] as? Int != nil
                && details["mlx_peak_memory_bytes"] as? Int != nil
        } != nil)

        let playbackFinished = try #require(
            try await worker.waitForStderrJSONObject(timeout: e2eTimeout) {
                guard
                    $0["event"] as? String == "playback_finished",
                    $0["request_id"] as? String == id,
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                let textComplexityClass = details["text_complexity_class"] as? String

                return ["compact", "balanced", "extended"].contains(textComplexityClass)
                    && (details["startup_buffer_target_ms"] as? Int ?? 0) >= 360
                    && (details["low_water_target_ms"] as? Int ?? 0) >= 140
                    && (details["resume_buffer_target_ms"] as? Int ?? 0) >= (details["startup_buffer_target_ms"] as? Int ?? 0)
                    && (details["chunk_gap_warning_threshold_ms"] as? Int ?? 0) >= 360
                    && (details["schedule_gap_warning_threshold_ms"] as? Int ?? 0) >= 140
                    && details["startup_buffered_audio_ms"] as? Int != nil
                    && details["min_queued_audio_ms"] as? Int != nil
                    && details["max_queued_audio_ms"] as? Int != nil
                    && details["avg_queued_audio_ms"] as? Int != nil
                    && details["queue_depth_sample_count"] as? Int != nil
                    && details["schedule_callback_count"] as? Int != nil
                    && details["played_back_callback_count"] as? Int != nil
                    && details["fade_in_chunk_count"] as? Int != nil
                    && details["starvation_event_count"] as? Int != nil
                    && details["process_phys_footprint_bytes"] as? Int != nil
                    && details["process_resident_bytes"] as? Int != nil
                    && details["process_user_cpu_time_ns"] as? Int != nil
                    && details["process_system_cpu_time_ns"] as? Int != nil
                    && details["mlx_active_memory_bytes"] as? Int != nil
                    && details["mlx_cache_memory_bytes"] as? Int != nil
                    && details["mlx_peak_memory_bytes"] as? Int != nil
            },
        )

        #expect(playbackFinished["event"] as? String == "playback_finished")
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
        } != nil)

        return playbackFinished
    }

    static func runGeneratedFileSpeech(
        on worker: WorkerProcess,
        id: String,
        text: String,
        profileName: String,
    ) async throws -> [String: Any] {
        try worker.sendJSON(
            """
            {"id":"\(id)","op":"generate_audio_file","text":"\(text.jsonEscaped)","profile_name":"\(profileName)"}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
                && $0["generated_file"] == nil
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_audio_file"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "generating_file_audio"
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: e2eTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "writing_generated_file"
        } != nil)

        let success = try #require(
            try await worker.waitForJSONObject(timeout: e2eTimeout) {
                guard
                    $0["id"] as? String == id,
                    $0["ok"] as? Bool == true,
                    let generatedFile = $0["generated_file"] as? [String: Any]
                else {
                    return false
                }

                return generatedFile["artifact_id"] as? String == "\(id)-artifact-1"
            },
        )

        return try #require(success["generated_file"] as? [String: Any])
    }

    static func runGeneratedBatchSpeech(
        on worker: WorkerProcess,
        id: String,
        profileName: String,
        itemsJSON: String,
    ) async throws -> [String: Any] {
        let batchTimeout: Duration = .seconds(180)
        let compactItemsJSON = try compactJSONArrayString(itemsJSON)

        try worker.sendJSON(
            """
            {"id":"\(id)","op":"generate_batch","profile_name":"\(profileName)","items":\(compactItemsJSON)}
            """,
        )

        #expect(try await worker.waitForJSONObject(timeout: batchTimeout) {
            $0["id"] as? String == id
                && $0["ok"] as? Bool == true
                && $0["generated_batch"] == nil
        } != nil)
        #expect(try await worker.waitForJSONObject(timeout: batchTimeout) {
            $0["id"] as? String == id
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_batch"
        } != nil)

        let success = try #require(
            try await worker.waitForJSONObject(timeout: batchTimeout) {
                guard
                    $0["id"] as? String == id,
                    $0["ok"] as? Bool == true,
                    let generatedBatch = $0["generated_batch"] as? [String: Any],
                    let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
                else {
                    return false
                }

                return generatedBatch["batch_id"] as? String == id
                    && generatedBatch["state"] as? String == "completed"
                    && artifacts.count >= 1
            },
        )

        return try #require(success["generated_batch"] as? [String: Any])
    }

    static func compactJSONArrayString(_ source: String) throws -> String {
        guard let data = source.data(using: .utf8) else {
            throw WorkerProcessError(
                "The batch items payload could not be encoded as UTF-8 before sending it to the SpeakSwiftly worker.",
            )
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard JSONSerialization.isValidJSONObject(object) else {
            throw WorkerProcessError(
                "The batch items payload is not valid JSON and cannot be compacted into a single-line worker request.",
            )
        }

        let compactData = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: compactData, as: UTF8.self)
    }

    static func expectMarvisVoiceSelection(
        on worker: WorkerProcess,
        requestID: String,
        expectedVoice: String,
    ) async throws {
        #expect(try await worker.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "marvis_voice_selected",
                $0["request_id"] as? String == requestID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["speech_backend"] as? String == "marvis"
                && details["marvis_voice"] as? String == expectedVoice
        } != nil)
    }

    static func transcriptLooksCloseToCloneSource(_ transcript: String) -> Bool {
        let expectedTokens = normalizedTranscriptTokens(from: testingCloneSourceText)
        let actualTokens = normalizedTranscriptTokens(from: transcript)

        guard !expectedTokens.isEmpty, !actualTokens.isEmpty else {
            return false
        }

        let sharedTokens = expectedTokens.intersection(actualTokens)
        let recall = Double(sharedTokens.count) / Double(expectedTokens.count)
        let precision = Double(sharedTokens.count) / Double(actualTokens.count)

        return recall >= 0.7 && precision >= 0.6
    }

    static func normalizedTranscriptTokens(from text: String) -> Set<String> {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(scalars)
        return Set(
            normalized
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !$0.isEmpty },
        )
    }

    static var e2eTimeout: Duration {
        .seconds(1200)
    }

    static var isE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_E2E"] == "1"
    }

    static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    static var isAudibleE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_AUDIBLE_E2E"] == "1"
    }

    static var isDeepTraceE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_DEEP_TRACE_E2E"] == "1"
    }
}

// MARK: - E2ESandbox

struct E2ESandbox {
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

// MARK: - JSONLineRecorder

final class JSONLineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutObjects = [[String: Any]]()
    private var stderrObjects = [[String: Any]]()
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
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return
            }

            stderrObjects.append(object)
        }
    }

    func firstMatchingJSONObject(_ predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.withLock {
            stdoutObjects.first(where: predicate)
        }
    }

    func recentStdoutObjects(limit: Int = 10) -> [[String: Any]] {
        lock.withLock {
            Array(stdoutObjects.suffix(limit))
        }
    }

    func stderrText() -> String {
        lock.withLock {
            stderrLines.joined(separator: "\n")
        }
    }

    func firstMatchingStderrJSONObject(_ predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.withLock {
            stderrObjects.first(where: predicate)
        }
    }

    func lastStdoutJSONObject() -> [String: Any]? {
        lock.withLock {
            stdoutObjects.last
        }
    }

    func lastStderrJSONObject() -> [String: Any]? {
        lock.withLock {
            stderrObjects.last
        }
    }

    func allStdoutObjects() -> [[String: Any]] {
        lock.withLock {
            stdoutObjects
        }
    }

    func allStderrObjects() -> [[String: Any]] {
        lock.withLock {
            stderrObjects
        }
    }
}

// MARK: - WorkerProcess

final class WorkerProcess: @unchecked Sendable {
    private enum Environment {
        static let dyldFrameworkPath = "DYLD_FRAMEWORK_PATH"
        static let profileRoot = "SPEAKSWIFTLY_PROFILE_ROOT"
        static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
        static let playbackTrace = "SPEAKSWIFTLY_PLAYBACK_TRACE"
        static let speechBackend = "SPEAKSWIFTLY_SPEECH_BACKEND"
    }

    private let artifacts: E2EWorkerArtifacts
    private let process: Process
    private let stdinPipe: Pipe
    private let stdinWriteHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let recorder: JSONLineRecorder
    private let stdoutTask: Task<Void, Never>
    private let stderrTask: Task<Void, Never>
    private let finalizedLock = NSLock()
    private var didFinalizeArtifacts = false

    init(
        profileRootURL: URL,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        speechBackend: SpeakSwiftly.SpeechBackend? = nil,
        configuration: SpeakSwiftly.Configuration? = nil,
        caller: StaticString = #function,
    ) throws {
        let packageRootURL = try Self.packageRootURL()
        let buildConfiguration = "Debug"
        let runtimeConfiguration = configuration
        try Self.publishWorkerRuntime(packageRootURL: packageRootURL, configuration: buildConfiguration)

        process = Process()
        stdinPipe = Pipe()
        stdinWriteHandle = stdinPipe.fileHandleForWriting
        let recorder = JSONLineRecorder()
        self.recorder = recorder
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        let executableURL = try Self.workerExecutableURL(
            packageRootURL: packageRootURL,
            configuration: buildConfiguration,
        )
        artifacts = try E2EWorkerArtifacts(
            packageRootURL: packageRootURL,
            configuration: buildConfiguration,
            caller: String(describing: caller),
            executableURL: executableURL,
            profileRootURL: profileRootURL,
        )
        if let runtimeConfiguration {
            try runtimeConfiguration.save(
                to: SpeakSwiftly.Configuration.defaultPersistenceURL(
                    fileManager: .default,
                    profileRootOverride: profileRootURL.path,
                ),
            )
        }

        process.executableURL = executableURL
        process.standardInput = stdinPipe.fileHandleForReading
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        environment[Environment.dyldFrameworkPath] = executableURL.deletingLastPathComponent().path
        environment[Environment.profileRoot] = profileRootURL.path
        if silentPlayback, !SpeakSwiftlyE2ETests.isAudibleE2EEnabled {
            environment[Environment.silentPlayback] = "1"
        }
        if playbackTrace {
            environment[Environment.playbackTrace] = "1"
        }
        if let speechBackend {
            environment[Environment.speechBackend] = speechBackend.rawValue
        }
        process.environment = environment

        stdoutTask = Self.captureLines(
            from: stdoutHandle,
            append: { [artifacts, recorder] line in
                artifacts.appendStdout(line)
                recorder.appendStdout(line)
            },
        )

        stderrTask = Self.captureLines(
            from: stderrHandle,
            append: { [artifacts, recorder] line in
                artifacts.appendStderr(line)
                recorder.appendStderr(line)
            },
        )

        try process.run()
        artifacts.recordProcessID(process.processIdentifier)
    }

    deinit {
        closeCapturedOutputs()
        stdoutTask.cancel()
        stderrTask.cancel()
    }

    private static func captureLines(
        from fileHandle: FileHandle,
        append: @escaping @Sendable (String) -> Void,
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

    private static func workerExecutableURL(
        packageRootURL: URL,
        configuration: String,
    ) throws -> URL {
        let result = Result {
            try computeWorkerExecutableURL(
                packageRootURL: packageRootURL,
                configuration: configuration,
            )
        }
        return try result.get()
    }

    private static func computeWorkerExecutableURL(
        packageRootURL: URL,
        configuration: String,
    ) throws -> URL {
        let runtime = try loadPublishedRuntime(
            packageRootURL: packageRootURL,
            configuration: configuration,
        )

        guard FileManager.default.isExecutableFile(atPath: runtime.executableURL.path) else {
            throw WorkerProcessError(
                "The published SpeakSwiftly worker executable recorded in '\(runtime.metadataURL.path)' was expected at '\(runtime.executableURL.path)', but no executable was found there.",
            )
        }
        guard FileManager.default.fileExists(atPath: runtime.metallibURL.path) else {
            throw WorkerProcessError(
                "The published SpeakSwiftly runtime recorded in '\(runtime.metadataURL.path)' is missing its MLX Metal shader bundle at '\(runtime.metallibURL.path)'. The worker cannot run real MLX-backed e2e tests without `default.metallib`.",
            )
        }
        guard FileManager.default.isExecutableFile(atPath: runtime.launcherURL.path) else {
            throw WorkerProcessError(
                "The published SpeakSwiftly runtime recorded in '\(runtime.metadataURL.path)' is missing its launcher script at '\(runtime.launcherURL.path)'.",
            )
        }

        return runtime.launcherURL
    }

    private static func loadPublishedRuntime(
        packageRootURL: URL,
        configuration: String,
    ) throws -> PublishedRuntime {
        let metadataURL = packageRootURL
            .appendingPathComponent(".local/xcode/SpeakSwiftly.\(configuration.lowercased()).json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw WorkerProcessError(
                "The published SpeakSwiftly runtime metadata manifest was expected at '\(metadataURL.path)', but no manifest was found there.",
            )
        }

        let data = try Data(contentsOf: metadataURL)
        let manifest = try JSONDecoder().decode(PublishedRuntimeManifest.self, from: data)

        return PublishedRuntime(
            metadataURL: metadataURL,
            productsURL: URL(fileURLWithPath: manifest.productsPath),
            executableURL: URL(fileURLWithPath: manifest.executablePath),
            launcherURL: URL(fileURLWithPath: manifest.launcherPath),
            metallibURL: URL(fileURLWithPath: manifest.metallibPath),
            aliasURL: URL(fileURLWithPath: manifest.aliasPath),
        )
    }

    private static func packageRootURL() throws -> URL {
        let fileManager = FileManager.default
        var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while true {
            let manifestURL = candidateURL.appendingPathComponent("Package.swift", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL != candidateURL else {
                throw WorkerProcessError(
                    "SpeakSwiftly e2e tests could not find the package root while walking upward from '\(#filePath)'. Expected to find a directory containing 'Package.swift'.",
                )
            }

            candidateURL = parentURL
        }
    }

    private static func buildWorkerProduct(
        packageRootURL: URL,
        configuration: String,
    ) throws {
        let process = Process()
        let logURL = packageRootURL
            .appendingPathComponent(".local/xcode/SpeakSwiftly-e2e-publish-\(configuration.lowercased()).log", isDirectory: false)
        try FileManager.default.createDirectory(
            at: packageRootURL.appendingPathComponent(".local/xcode", isDirectory: true),
            withIntermediateDirectories: true,
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        process.currentDirectoryURL = packageRootURL
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "scripts/repo-maintenance/publish-runtime.sh",
            "--configuration", configuration,
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = try Data(contentsOf: logURL)
            let output = String(decoding: outputData, as: UTF8.self)
            throw WorkerProcessError(
                "The SpeakSwiftly runtime publisher failed with status \(process.terminationStatus). Publisher output:\n\(output)",
            )
        }
    }

    private static func publishWorkerRuntime(
        packageRootURL: URL,
        configuration: String,
    ) throws {
        try buildWorkerProduct(
            packageRootURL: packageRootURL,
            configuration: configuration,
        )
    }

    func sendJSON(_ jsonLine: String) throws {
        try stdinWriteHandle.write(contentsOf: Data((jsonLine + "\n").utf8))
    }

    func closeInput() throws {
        if #available(macOS 12.0, *) {
            try stdinWriteHandle.close()
        } else {
            stdinWriteHandle.closeFile()
        }
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

        closeCapturedOutputs()
        stdoutTask.cancel()
        stderrTask.cancel()
        finalizeArtifactsIfNeeded()
    }

    func waitForJSONObject(
        timeout: Duration,
        _ predicate: @escaping @Sendable ([String: Any]) -> Bool,
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
        let stdoutTail = recorder.recentStdoutObjects()
        throw WorkerProcessError(
            """
            Timed out waiting for a matching worker JSON event.
            Recent stdout JSON objects:
            \(stdoutTail)

            Current stderr:
            \(stderr)
            """,
        )
    }

    func waitForExit(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while process.isRunning, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }

        guard !process.isRunning else {
            let stderr = recorder.stderrText()
            throw WorkerProcessError(
                "The SpeakSwiftly worker did not exit before the timeout expired. Current stderr:\n\(stderr)",
            )
        }

        closeCapturedOutputs()
        stdoutTask.cancel()
        stderrTask.cancel()

        guard process.terminationStatus == 0 else {
            let stderr = recorder.stderrText()
            finalizeArtifactsIfNeeded()
            throw WorkerProcessError(
                "The SpeakSwiftly worker exited with status \(process.terminationStatus). Current stderr:\n\(stderr)",
            )
        }

        finalizeArtifactsIfNeeded()
    }

    func waitForStderrJSONObject(
        timeout: Duration,
        _ predicate: @escaping @Sendable ([String: Any]) -> Bool,
    ) async throws -> [String: Any]? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if let object = recorder.firstMatchingStderrJSONObject(predicate) {
                return object
            }

            if !process.isRunning {
                break
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        if let object = recorder.firstMatchingStderrJSONObject(predicate) {
            return object
        }

        let stderr = recorder.stderrText()
        throw WorkerProcessError(
            "Timed out waiting for a matching worker stderr JSON event. Current stderr:\n\(stderr)",
        )
    }

    func stdoutObjects() -> [[String: Any]] {
        recorder.allStdoutObjects()
    }

    private func closeCapturedOutputs() {
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    private func finalizeArtifactsIfNeeded() {
        finalizedLock.withLock {
            guard !didFinalizeArtifacts else { return }

            didFinalizeArtifacts = true

            artifacts.finalize(
                terminationStatus: Int(process.terminationStatus),
                terminationReason: process.terminationReason,
                stdoutObjects: recorder.allStdoutObjects(),
                stderrObjects: recorder.allStderrObjects(),
            )
        }
    }
}

// MARK: - PublishedRuntimeManifest

private struct PublishedRuntimeManifest: Decodable {
    let productsPath: String
    let executablePath: String
    let launcherPath: String
    let metallibPath: String
    let aliasPath: String

    private enum CodingKeys: String, CodingKey {
        case productsPath = "products_path"
        case executablePath = "executable_path"
        case launcherPath = "launcher_path"
        case metallibPath = "metallib_path"
        case aliasPath = "alias_path"
    }
}

// MARK: - PublishedRuntime

private struct PublishedRuntime {
    let metadataURL: URL
    let productsURL: URL
    let executableURL: URL
    let launcherURL: URL
    let metallibURL: URL
    let aliasURL: URL
}

// MARK: - WorkerProcessError

struct WorkerProcessError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

// MARK: - E2EWorkerArtifacts

private final class E2EWorkerArtifacts: @unchecked Sendable {
    private let lock = NSLock()
    private let startedAt = Date()
    private let artifactsRootURL: URL
    private let stdoutURL: URL
    private let stderrURL: URL
    private let summaryURL: URL
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let runID: String
    private let caller: String
    private let configuration: String
    private let executableURL: URL
    private let profileRootURL: URL
    private let runtimeMetadataURL: URL
    private var processID: Int32?

    init(
        packageRootURL: URL,
        configuration: String,
        caller: String,
        executableURL: URL,
        profileRootURL: URL,
    ) throws {
        runID = Self.runTimestampString(for: startedAt)
            + "-" + UUID().uuidString.lowercased()
        self.caller = caller
        self.configuration = configuration
        self.executableURL = executableURL
        self.profileRootURL = profileRootURL

        let sanitizedCaller = caller
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let baseName = sanitizedCaller.isEmpty ? "worker-run" : sanitizedCaller

        artifactsRootURL = packageRootURL
            .appendingPathComponent(".local/e2e-runs", isDirectory: true)
            .appendingPathComponent("\(runID)-\(baseName)", isDirectory: true)
        stdoutURL = artifactsRootURL.appendingPathComponent("stdout.jsonl", isDirectory: false)
        stderrURL = artifactsRootURL.appendingPathComponent("stderr.jsonl", isDirectory: false)
        summaryURL = artifactsRootURL.appendingPathComponent("summary.json", isDirectory: false)
        runtimeMetadataURL = packageRootURL
            .appendingPathComponent(".local/xcode/SpeakSwiftly.\(configuration.lowercased()).json", isDirectory: false)

        try FileManager.default.createDirectory(at: artifactsRootURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        stderrHandle = try FileHandle(forWritingTo: stderrURL)
    }

    deinit {
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    private static func runTimestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    func recordProcessID(_ processID: Int32) {
        lock.withLock {
            self.processID = processID
        }
    }

    func appendStdout(_ line: String) {
        append(line, to: stdoutHandle)
    }

    func appendStderr(_ line: String) {
        append(line, to: stderrHandle)
    }

    func finalize(
        terminationStatus: Int,
        terminationReason: Process.TerminationReason,
        stdoutObjects: [[String: Any]],
        stderrObjects: [[String: Any]],
    ) {
        lock.withLock {
            let finishedAt = Date()
            let duration = finishedAt.timeIntervalSince(startedAt)
            let summary = E2ERunSummary(
                runID: runID,
                caller: caller,
                startedAt: startedAt,
                finishedAt: finishedAt,
                durationSeconds: duration,
                configuration: configuration,
                executablePath: executableURL.path,
                profileRootPath: profileRootURL.path,
                runtimeMetadataPath: runtimeMetadataURL.path,
                processID: processID.map(Int.init),
                terminationStatus: terminationStatus,
                terminationReason: terminationReason == .exit ? "exit" : "uncaught_signal",
                stdoutLogPath: stdoutURL.path,
                stderrLogPath: stderrURL.path,
                stdoutEventCount: stdoutObjects.count,
                stderrEventCount: stderrObjects.count,
                lastRuntimeMetrics: lastRuntimeMetrics(from: stderrObjects),
            )

            do {
                let data = try JSONEncoder.e2eArtifacts.encode(summary)
                try data.write(to: summaryURL, options: .atomic)
            } catch {
                let failure = """
                {"event":"e2e_artifact_summary_failed","message":"\(error.localizedDescription.jsonEscaped)","summary_path":"\(summaryURL.path.jsonEscaped)"}
                """
                append(failure, to: stderrHandle)
            }

            try? stdoutHandle.close()
            try? stderrHandle.close()
        }
    }

    private func append(_ line: String, to handle: FileHandle) {
        lock.withLock {
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    private func lastRuntimeMetrics(from stderrObjects: [[String: Any]]) -> E2ERuntimeMetrics? {
        for object in stderrObjects.reversed() {
            guard let details = object["details"] as? [String: Any] else { continue }

            let hasMetrics =
                details["process_resident_bytes"] != nil
                    || details["process_phys_footprint_bytes"] != nil
                    || details["process_user_cpu_time_ns"] != nil
                    || details["process_system_cpu_time_ns"] != nil
                    || details["mlx_active_memory_bytes"] != nil
                    || details["mlx_cache_memory_bytes"] != nil
                    || details["mlx_peak_memory_bytes"] != nil
                    || details["mlx_cache_limit_bytes"] != nil
                    || details["mlx_memory_limit_bytes"] != nil

            guard hasMetrics else { continue }

            return E2ERuntimeMetrics(
                event: object["event"] as? String,
                requestID: object["request_id"] as? String,
                processResidentBytes: details["process_resident_bytes"] as? Int,
                processPhysFootprintBytes: details["process_phys_footprint_bytes"] as? Int,
                processUserCPUTimeNS: details["process_user_cpu_time_ns"] as? Int,
                processSystemCPUTimeNS: details["process_system_cpu_time_ns"] as? Int,
                mlxActiveMemoryBytes: details["mlx_active_memory_bytes"] as? Int,
                mlxCacheMemoryBytes: details["mlx_cache_memory_bytes"] as? Int,
                mlxPeakMemoryBytes: details["mlx_peak_memory_bytes"] as? Int,
                mlxCacheLimitBytes: details["mlx_cache_limit_bytes"] as? Int,
                mlxMemoryLimitBytes: details["mlx_memory_limit_bytes"] as? Int,
            )
        }

        return nil
    }
}

// MARK: - E2ERunSummary

private struct E2ERunSummary: Codable {
    let runID: String
    let caller: String
    let startedAt: Date
    let finishedAt: Date
    let durationSeconds: TimeInterval
    let configuration: String
    let executablePath: String
    let profileRootPath: String
    let runtimeMetadataPath: String
    let processID: Int?
    let terminationStatus: Int
    let terminationReason: String
    let stdoutLogPath: String
    let stderrLogPath: String
    let stdoutEventCount: Int
    let stderrEventCount: Int
    let lastRuntimeMetrics: E2ERuntimeMetrics?
}

// MARK: - E2ERuntimeMetrics

private struct E2ERuntimeMetrics: Codable {
    let event: String?
    let requestID: String?
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let processUserCPUTimeNS: Int?
    let processSystemCPUTimeNS: Int?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
    let mlxCacheLimitBytes: Int?
    let mlxMemoryLimitBytes: Int?
}

private extension JSONEncoder {
    static var e2eArtifacts: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension String {
    var jsonEscaped: String {
        let data = (try? JSONSerialization.data(withJSONObject: [self])) ?? Data("[\"\"]".utf8)
        let encoded = String(decoding: data, as: UTF8.self)
        return String(encoded.dropFirst(2).dropLast(2))
    }
}
#endif
