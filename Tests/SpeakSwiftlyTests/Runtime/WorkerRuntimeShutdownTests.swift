import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

final class BlockingFilesystemCoordinator: @unchecked Sendable {
    private let enteredSemaphore = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func markEntered() {
        enteredSemaphore.signal()
    }

    func waitUntilEntered(timeout: TimeInterval = 1.0) {
        let result = enteredSemaphore.wait(timeout: .now() + timeout)
        #expect(result == .success)
    }

    func blockUntilReleased() {
        _ = releaseSemaphore.wait(timeout: .distantFuture)
    }

    func release() {
        releaseSemaphore.signal()
    }
}

final class CopyBlockingFileManager: FileManager, @unchecked Sendable {
    let blockedDestinationPath: String
    let coordinator: BlockingFilesystemCoordinator

    init(blockedDestinationPath: String, coordinator: BlockingFilesystemCoordinator) {
        self.blockedDestinationPath = blockedDestinationPath
        self.coordinator = coordinator
        super.init()
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.path == blockedDestinationPath {
            coordinator.markEntered()
            coordinator.blockUntilReleased()
        }

        try super.copyItem(at: srcURL, to: dstURL)
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func set() {
        lock.withLock {
            storedValue = true
        }
    }
}

// MARK: - Shutdown Behavior

@Test func shutdownCancelsActivePlaybackAndQueuedRequestsExactlyOnce() async throws {
    let output = OutputRecorder()
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

    let playback = PlaybackSpy(behavior: .sleep(.seconds(30)))
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"queue_speech_live","text":"Hello there","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "buffering_audio"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"queue_speech_live","text":"Hello again","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == true
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_live"
        }
    })

    await runtime.shutdown()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
    #expect(output.countJSONObjects {
        $0["id"] as? String == "req-1"
            && $0["ok"] as? Bool == false
    } == 1)
    #expect(playback.stopCount == 1)
}

@Test func shutdownPathEmitsCancellationNotPlaybackTimeout() async throws {
    let output = OutputRecorder()
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

    let playback = PlaybackSpy(behavior: .sleep(.seconds(30)))
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"queue_speech_live","text":"Hello there","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    await runtime.shutdown()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-1"
            && $0["ok"] as? Bool == false
            && $0["code"] as? String == "audio_playback_timeout"
    })
}

@Test func shutdownFailsTypedRequestStreamsForActiveAndQueuedRequests() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy(behavior: .sleep(.seconds(30)))
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
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            makeProfileModel {
                try? await Task.sleep(for: .seconds(30))
            }
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeHandle = await runtime.submit(
        .queueSpeech(
            id: "req-active-shutdown-stream",
            text: "Hello there",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: nil
        )
    )
    var activeIterator = activeHandle.events.makeAsyncIterator()

    let activeStarted = try await activeIterator.next()
    #expect(
        activeStarted == .acknowledged(
            WorkerSuccessResponse(id: "req-active-shutdown-stream")
        )
    )

    let queuedHandle = await runtime.submit(
        .createProfile(
            id: "req-queued-shutdown-stream",
            profileName: "shutdown-queued-profile",
            text: "A queued request that should still be active when shutdown begins.",
            vibe: .femme,
            voiceDescription: "Warm and bright",
            outputPath: nil,
            cwd: nil
        )
    )
    var queuedIterator = queuedHandle.events.makeAsyncIterator()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-queued-shutdown-stream"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_profile"
        }
    })

    await runtime.shutdown()

    do {
        while let _ = try await activeIterator.next() {}
        Issue.record("The active typed request stream should have thrown during shutdown.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }

    do {
        while let _ = try await queuedIterator.next() {}
        Issue.record("The queued typed request stream should have thrown during shutdown.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }
}

@Test func shutdownRejectsNewRequests() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    await runtime.shutdown()
    await runtime.accept(line: #"{"id":"req-1","op":"list_profiles"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "worker_shutting_down"
        }
    })
}

@Test func shutdownCancelsActiveProfileCreationBeforeProfileIsWritten() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            AnySpeechModel(
                sampleRate: 24_000,
                generate: { _, _, _, _, _, _ in
                    try await Task.sleep(for: .seconds(30))
                    return [0.1, 0.2, 0.3]
                },
                generateSamplesStream: { _, _, _, _, _, _, _ in
                    AsyncThrowingStream { continuation in
                        continuation.finish()
                    }
                }
            )
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-1","op":"create_profile","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "generating_profile_audio"
        }
    })

    await runtime.shutdown()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
    #expect(!FileManager.default.fileExists(atPath: storeRoot.appendingPathComponent("bright-guide").path))
}

@Test func shutdownWaitsForActiveProfileCreationToUnwindBeforeEmittingCancellationDuringTempWAVWrite() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let writeCoordinator = BlockingFilesystemCoordinator()
    let blockedRuntime = WorkerRuntime(
        dependencies: WorkerDependencies(
            fileManager: .default,
            loadResidentModels: { _ in makeResidentModels(for: .qwen3) },
            loadProfileModel: { makeProfileModel() },
            loadCloneTranscriptionModel: { makeCloneTranscriptionModel() },
            makePlaybackController: { AnyPlaybackController.silent() },
            writeWAV: { samples, _, url in
                writeCoordinator.markEntered()
                writeCoordinator.blockUntilReleased()
                let bytes = samples.map(\.bitPattern).flatMap { value in
                    withUnsafeBytes(of: value.littleEndian, Array.init)
                }
                try Data(bytes).write(to: url, options: .atomic)
            },
            loadAudioSamples: { _, _ in nil },
            loadAudioFloats: { _, _ in [] },
            writeStdout: output.writeStdout,
            writeStderr: output.writeStderr,
            now: Date.init,
            readRuntimeMemory: { nil }
        ),
        speechBackend: .qwen3,
        profileStore: try makeProfileStore(rootURL: storeRoot),
        generatedFileStore: try makeGeneratedFileStore(rootURL: storeRoot),
        generationJobStore: try makeGenerationJobStore(rootURL: storeRoot),
        normalizer: SpeakSwiftly.Normalizer(
            persistenceURL: storeRoot.appending(path: ProfileStore.textProfilesFileName)
        ),
        playbackController: PlaybackController(driver: AnyPlaybackController.silent())
    )
    await blockedRuntime.installPlaybackHooks()
    await blockedRuntime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await blockedRuntime.accept(
        line: #"{"id":"req-write-gate","op":"create_profile","profile_name":"bright-gate","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-write-gate"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_profile"
        }
    })
    writeCoordinator.waitUntilEntered()

    let shutdownFinished = LockedFlag()
    let shutdownTask = Task {
        await blockedRuntime.shutdown()
        shutdownFinished.set()
    }

    try await Task.sleep(for: .milliseconds(100))
    #expect(!shutdownFinished.value)
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-write-gate"
            && $0["ok"] as? Bool == false
            && $0["code"] as? String == "request_cancelled"
    })

    writeCoordinator.release()
    await shutdownTask.value

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-write-gate"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
    #expect(!FileManager.default.fileExists(atPath: storeRoot.appendingPathComponent("bright-gate").path))
}

@Test func shutdownWaitsForActiveProfileExportToUnwindBeforeEmittingCancellation() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let exportURL = storeRoot.appendingPathComponent("exports/reference.wav")
    let exportCoordinator = BlockingFilesystemCoordinator()
    let fileManager = CopyBlockingFileManager(
        blockedDestinationPath: exportURL.path,
        coordinator: exportCoordinator
    )

    let profileStore = ProfileStore(rootURL: storeRoot, fileManager: fileManager)
    let generatedFileStore = GeneratedFileStore(
        rootURL: storeRoot.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true),
        fileManager: fileManager
    )
    let generationJobStore = GenerationJobStore(
        rootURL: storeRoot.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true),
        fileManager: fileManager
    )
    try profileStore.ensureRootExists()
    try generatedFileStore.ensureRootExists()
    try generationJobStore.ensureRootExists()

    let normalizer = SpeakSwiftly.Normalizer(
        persistenceURL: storeRoot.appending(path: ProfileStore.textProfilesFileName)
    )
    try await normalizer.loadProfiles()

    let dependencies = WorkerDependencies(
        fileManager: fileManager,
        loadResidentModels: { _ in makeResidentModels(for: .qwen3) },
        loadProfileModel: { makeProfileModel() },
        loadCloneTranscriptionModel: { makeCloneTranscriptionModel() },
        makePlaybackController: { AnyPlaybackController.silent() },
        writeWAV: { samples, _, url in
            let bytes = samples.map(\.bitPattern).flatMap { value in
                withUnsafeBytes(of: value.littleEndian, Array.init)
            }
            try Data(bytes).write(to: url, options: .atomic)
        },
        loadAudioSamples: { _, _ in nil },
        loadAudioFloats: { _, _ in [] },
        writeStdout: output.writeStdout,
        writeStderr: output.writeStderr,
        now: Date.init,
        readRuntimeMemory: { nil }
    )

    let runtime = WorkerRuntime(
        dependencies: dependencies,
        speechBackend: .qwen3,
        profileStore: profileStore,
        generatedFileStore: generatedFileStore,
        generationJobStore: generationJobStore,
        normalizer: normalizer,
        playbackController: PlaybackController(driver: AnyPlaybackController.silent())
    )
    await runtime.installPlaybackHooks()

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: """
        {"id":"req-export-gate","op":"create_profile","profile_name":"bright-export","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"\(exportURL.path)"}
        """
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-export-gate"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "exporting_profile_audio"
        }
    })
    exportCoordinator.waitUntilEntered()

    let shutdownFinished = LockedFlag()
    let shutdownTask = Task {
        await runtime.shutdown()
        shutdownFinished.set()
    }

    try await Task.sleep(for: .milliseconds(100))
    #expect(!shutdownFinished.value)
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-export-gate"
            && $0["ok"] as? Bool == false
            && $0["code"] as? String == "request_cancelled"
    })

    exportCoordinator.release()
    await shutdownTask.value

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-export-gate"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
}
