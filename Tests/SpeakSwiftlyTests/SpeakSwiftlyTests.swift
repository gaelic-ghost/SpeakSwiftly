import Foundation
import Testing
@testable import SpeakSwiftly

// MARK: - Request Decoding

@Test func decodesSpeakLiveRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live","text":"Hello","profile_name":"default-femme"}"#)

    #expect(request == .speakLive(id: "req-1", text: "Hello", profileName: "default-femme"))
}

@Test func decodesCreateProfileRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello","voice_description":"Warm and bright","output_path":"./voice.wav"}"#
    )

    #expect(
        request == .createProfile(
            id: "req-2",
            profileName: "bright-guide",
            text: "Hello",
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav"
        )
    )
}

@Test func decodesListProfilesRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-3","op":"list_profiles"}"#)
    #expect(request == .listProfiles(id: "req-3"))
}

@Test func decodesRemoveProfileRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-4","op":"remove_profile","profile_name":"bright-guide"}"#)
    #expect(request == .removeProfile(id: "req-4", profileName: "bright-guide"))
}

@Test func rejectsMalformedJSON() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live""#)
    }
}

@Test func rejectsUnknownOperation() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func rejectsMissingRequiredFields() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live","text":"   ","profile_name":"default-femme"}"#)
    }
}

@Test func rejectsInvalidProfileName() throws {
    let tempRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot)

    #expect(throws: WorkerError.self) {
        try store.validateProfileName("Bad Name")
    }
}

// MARK: - Envelope Encoding

@Test func encodesWorkerEnvelopesWithExpectedKeys() throws {
    let queued = try jsonObject(
        WorkerQueuedEvent(
            id: "req-1",
            reason: .waitingForResidentModel,
            queuePosition: 2
        )
    )
    #expect(queued["event"] as? String == "queued")
    #expect(queued["reason"] as? String == "waiting_for_resident_model")
    #expect(queued["queue_position"] as? Int == 2)

    let started = try jsonObject(WorkerStartedEvent(id: "req-1", op: "speak_live"))
    #expect(started["event"] as? String == "started")
    #expect(started["op"] as? String == "speak_live")

    let progress = try jsonObject(WorkerProgressEvent(id: "req-1", stage: .bufferingAudio))
    #expect(progress["event"] as? String == "progress")
    #expect(progress["stage"] as? String == "buffering_audio")

    let success = try jsonObject(
        WorkerSuccessResponse(
            id: "req-1",
            profileName: "default-femme",
            profilePath: "/tmp/default-femme",
            profiles: nil
        )
    )
    #expect(success["ok"] as? Bool == true)
    #expect(success["profile_name"] as? String == "default-femme")
    #expect(success["profile_path"] as? String == "/tmp/default-femme")

    let failure = try jsonObject(
        WorkerFailureResponse(
            id: "req-1",
            code: .profileNotFound,
            message: "Profile 'ghost' was not found in the SpeakSwiftly profile store."
        )
    )
    #expect(failure["ok"] as? Bool == false)
    #expect(failure["code"] as? String == "profile_not_found")
}

// MARK: - Profile Store

@Test func createsListsLoadsAndRemovesProfiles() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    let stored = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(stored.manifest.profileName == "default-femme")

    let listed = try store.listProfiles()
    #expect(listed.count == 1)
    #expect(listed.first?.profileName == "default-femme")

    let loaded = try store.loadProfile(named: "default-femme")
    #expect(loaded.manifest.sourceText == "Hello there")

    try store.removeProfile(named: "default-femme")
    let empty = try store.listProfiles()
    #expect(empty.isEmpty)
}

@Test func rejectsDuplicateProfiles() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x52, 0x49, 0x46, 0x46])

    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    #expect(throws: WorkerError.self) {
        _ = try store.createProfile(
            profileName: "default-femme",
            modelRepo: "test-model",
            voiceDescription: "Duplicate",
            sourceText: "Hello again",
            sampleRate: 24_000,
            canonicalAudioData: audioData
        )
    }
}

@Test func exportsCanonicalAudioWithoutOverwritingExistingFiles() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01, 0x02, 0x03, 0x04])
    let stored = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let exportURL = tempRoot.appendingPathComponent("exports/reference.wav")
    try store.exportCanonicalAudio(for: stored, to: exportURL.path)
    #expect(fileManager.fileExists(atPath: exportURL.path))
    #expect(try Data(contentsOf: exportURL) == audioData)

    #expect(throws: WorkerError.self) {
        try store.exportCanonicalAudio(for: stored, to: exportURL.path)
    }
}

@Test func listsProfilesInSortedOrder() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    let audioData = Data([0x01])

    _ = try store.createProfile(
        profileName: "zeta",
        modelRepo: "test-model",
        voiceDescription: "Zeta",
        sourceText: "Zeta",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )
    _ = try store.createProfile(
        profileName: "alpha",
        modelRepo: "test-model",
        voiceDescription: "Alpha",
        sourceText: "Alpha",
        sampleRate: 24_000,
        canonicalAudioData: audioData
    )

    let listed = try store.listProfiles()
    #expect(listed.map(\.profileName) == ["alpha", "zeta"])
}

@Test func listProfilesFailsWhenManifestIsCorrupt() throws {
    let fileManager = FileManager.default
    let tempRoot = makeTempDirectoryURL()
    defer { try? fileManager.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot, fileManager: fileManager)
    try store.ensureRootExists()

    let profileDirectory = store.profileDirectoryURL(for: "broken")
    try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: store.manifestURL(for: profileDirectory))

    #expect(throws: Error.self) {
        _ = try store.listProfiles()
    }
}

// MARK: - Runtime

@Test func requestsQueuedDuringPreloadEmitWaitingStatusThenProcess() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let playback = PlaybackSpy()
    let runtime = try await makeRuntime(
        output: output,
        playback: playback,
        residentModelLoader: {
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-1","op":"list_profiles"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_resident_model"
        }
    })

    await preloadGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })
}

@Test func residentModelPreloadFailureFailsQueuedRequests() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: {
            await preloadGate.wait()
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Resident model preload failed while loading test-resident. The local test intentionally forced this failure."
            )
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-1","op":"list_profiles"}"#)
    await preloadGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_failed"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "model_generation_failed"
        }
    })
}

@Test func waitingSpeakLiveRunsBeforeWaitingProfileManagementAfterActiveWorkFinishes() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let profileGate = AsyncGate()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { makeResidentModel() },
        profileModelLoader: {
            makeProfileModel {
                await profileGate.wait()
            }
        }
    )
    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01])
    )
    _ = try store.createProfile(
        profileName: "remove-me",
        modelRepo: "test-model",
        voiceDescription: "Remove me.",
        sourceText: "Remove me.",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x02])
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-1","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_profile"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"remove_profile","profile_name":"remove-me"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"speak_live","text":"Hi there","profile_name":"default-femme"}"#)

    await profileGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-3"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "speak_live"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "remove_profile"
        }
    })

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_profile", "req-3:speak_live", "req-2:remove_profile"])
}

@Test func speakLiveUsesStoredProfileDataWaitsForPlaybackDrainAndReusesPlaybackController() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(drainGate: playbackDrain)
    let residentRecorder = ResidentModelRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01, 0x02])
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        audioLoadRecorder: residentRecorder,
        residentModelLoader: {
            makeResidentModel(recorder: residentRecorder)
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-1"
            && $0["ok"] as? Bool == true
    })

    await playbackDrain.open()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"speak_live","text":"Hello again","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == true
        }
    })

    await runtime.shutdown()

    #expect(residentRecorder.lastRefText == "Reference transcript")
    #expect(residentRecorder.lastRefAudioWasProvided == false)
    #expect(residentRecorder.audioLoadCallCount == 2)
    #expect(playback.playCount == 2)
    #expect(playback.stopCount == 1)
}

// MARK: - Helpers

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private final class OutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutLines = [String]()
    private var stderrLines = [String]()

    func writeStdout(_ data: Data) throws {
        let string = String(decoding: data, as: UTF8.self)
        let lines = string
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        lock.withLock {
            stdoutLines.append(contentsOf: lines)
        }
    }

    func writeStderr(_ message: String) {
        lock.withLock {
            stderrLines.append(message)
        }
    }

    func stdoutContains(_ fragment: String) -> Bool {
        lock.withLock {
            stdoutLines.contains { $0.contains(fragment) }
        }
    }

    func containsJSONObject(_ predicate: ([String: Any]) -> Bool) -> Bool {
        lock.withLock {
            stdoutLines.contains { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                else {
                    return false
                }

                return predicate(object)
            }
        }
    }

    func startedEvents() -> [String] {
        lock.withLock {
            stdoutLines.compactMap { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    object["event"] as? String == "started",
                    let id = object["id"] as? String,
                    let op = object["op"] as? String
                else {
                    return nil
                }

                return "\(id):\(op)"
            }
        }
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private final class PlaybackSpy: @unchecked Sendable {
    private let lock = NSLock()
    private let drainGate: AsyncGate?
    private(set) var playCount = 0
    private(set) var stopCount = 0

    init(drainGate: AsyncGate? = nil) {
        self.drainGate = drainGate
    }

    func controller() -> AnyPlaybackController {
        AnyPlaybackController(
            play: { [self] _, stream, onFirstChunk in
                lock.withLock { playCount += 1 }

                var emittedFirstChunk = false
                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }

                    if !emittedFirstChunk {
                        emittedFirstChunk = true
                        await onFirstChunk()
                    }
                }

                if let drainGate {
                    await drainGate.wait()
                }
            },
            stop: { [self] in
                lock.withLock { stopCount += 1 }
            }
        )
    }
}

private final class ResidentModelRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lastRefText: String?
    private(set) var lastRefAudioWasProvided = false
    private(set) var audioLoadCallCount = 0

    func record(refAudioWasProvided: Bool, refText: String?) {
        lock.withLock {
            lastRefAudioWasProvided = refAudioWasProvided
            lastRefText = refText
        }
    }

    func recordAudioLoad() {
        lock.withLock {
            audioLoadCallCount += 1
        }
    }
}

private func makeResidentModel(recorder: ResidentModelRecorder? = nil) -> AnySpeechModel {
    AnySpeechModel(
        sampleRate: 24_000,
        generate: { _, _, _, _, _ in
            [0.1, 0.2]
        },
        generateSamplesStream: { _, _, refAudio, refText, _, _ in
            recorder?.record(refAudioWasProvided: refAudio != nil, refText: refText)

            return AsyncThrowingStream { continuation in
                continuation.yield([0.1, 0.2])
                continuation.finish()
            }
        }
    )
}

private func makeProfileModel(waitBeforeGenerate: (@Sendable () async -> Void)? = nil) -> AnySpeechModel {
    AnySpeechModel(
        sampleRate: 24_000,
        generate: { _, _, _, _, _ in
            if let waitBeforeGenerate {
                await waitBeforeGenerate()
            }
            return [0.1, 0.2, 0.3]
        },
        generateSamplesStream: { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    )
}

private func makeProfileStore(rootURL: URL) throws -> ProfileStore {
    let store = ProfileStore(rootURL: rootURL, fileManager: .default)
    try store.ensureRootExists()
    return store
}

private func makeRuntime(
    rootURL: URL = makeTempDirectoryURL(),
    output: OutputRecorder,
    playback: PlaybackSpy,
    audioLoadRecorder: ResidentModelRecorder? = nil,
    residentModelLoader: @escaping @Sendable () async throws -> AnySpeechModel,
    profileModelLoader: @escaping @Sendable () async throws -> AnySpeechModel = {
        makeProfileModel()
    }
) async throws -> WorkerRuntime {
    let store = try makeProfileStore(rootURL: rootURL)
    let playbackController = playback.controller()
    let dependencies = WorkerDependencies(
        fileManager: .default,
        loadResidentModel: residentModelLoader,
        loadProfileModel: profileModelLoader,
        makePlaybackController: { playbackController },
        writeWAV: { samples, _, url in
            let bytes = samples.map(\.bitPattern).flatMap { value in
                withUnsafeBytes(of: value.littleEndian, Array.init)
            }
            try Data(bytes).write(to: url, options: .atomic)
        },
        loadAudioSamples: { _, _ in
            audioLoadRecorder?.recordAudioLoad()
            return nil
        },
        writeStdout: output.writeStdout,
        writeStderr: output.writeStderr,
        now: Date.init
    )

    return WorkerRuntime(
        dependencies: dependencies,
        profileStore: store,
        playbackController: playbackController
    )
}

private func makeTempDirectoryURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @escaping @Sendable () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if condition() {
            return true
        }

        try? await Task.sleep(for: pollInterval)
    }

    return condition()
}
