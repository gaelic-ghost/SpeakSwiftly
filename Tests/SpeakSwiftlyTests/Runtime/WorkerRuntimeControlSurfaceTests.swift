import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Control Operations and Typed Surface

private final class WeakRuntimeBox: @unchecked Sendable {
    weak var value: WorkerRuntime?
}

private actor BackendLoadRecorder {
    private var backends = [SpeakSwiftly.SpeechBackend]()

    func record(_ backend: SpeakSwiftly.SpeechBackend) {
        backends.append(backend)
    }

    func values() -> [SpeakSwiftly.SpeechBackend] {
        backends
    }
}

@Test func listQueueReturnsActiveAndQueuedRequestsWithoutWaitingForActivePlayback() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
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
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.speak(text: "Hello there", with: "default-femme", as: .live, id: "req-active")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    _ = await runtime.speak(text: "Hi there", with: "default-femme", as: .live, id: "req-queued-1")

    let listID = await runtime.queue(.playback, id: "req-list-queue").id
    #expect(listID == "req-list-queue")

    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-list-queue",
                $0["ok"] as? Bool == true,
                let active = $0["active_request"] as? [String: Any],
                let queue = $0["queue"] as? [[String: Any]]
            else {
                return false
            }

            return active["id"] as? String == "req-active"
                && queue.count == 1
                && queue[0]["id"] as? String == "req-queued-1"
                && queue[0]["queue_position"] as? Int == 1
        }
    })

    await playbackDrain.open()
}

@Test func statusReturnsCurrentResidentBackendAndStage() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "qwen3"
        }
    })

    let statusID = await runtime.status(id: "req-status").id
    #expect(statusID == "req-status")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-status",
                $0["ok"] as? Bool == true,
                $0["speech_backend"] as? String == "qwen3",
                let status = $0["status"] as? [String: Any]
            else {
                return false
            }

            return status["stage"] as? String == "resident_model_ready"
                && status["resident_state"] as? String == "ready"
                && status["speech_backend"] as? String == "qwen3"
        }
    })
}

@Test func switchSpeechBackendReloadsResidentModelsWithoutRestartingRuntime() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "qwen3"
        }
    })

    let switchID = await runtime.switchSpeechBackend(to: .marvis, id: "req-switch").id
    #expect(switchID == "req-switch")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-switch",
                $0["ok"] as? Bool == true,
                $0["speech_backend"] as? String == "marvis",
                let status = $0["status"] as? [String: Any]
            else {
                return false
            }

            return status["stage"] as? String == "resident_model_ready"
                && status["speech_backend"] as? String == "marvis"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "marvis"
        }
    })
}

@Test func unloadAndReloadModelsParkResidentGenerationUntilResidencyReturns() async throws {
    let output = OutputRecorder()
    let backendLoads = BackendLoadRecorder()
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
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { backend in
            await backendLoads.record(backend)
            return makeResidentModel()
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["resident_state"] as? String == "ready"
        }
    })

    let unloadID = await runtime.unloadModels(id: "req-unload").id
    #expect(unloadID == "req-unload")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-unload",
                $0["ok"] as? Bool == true,
                let status = $0["status"] as? [String: Any]
            else {
                return false
            }

            return status["stage"] as? String == "resident_models_unloaded"
                && status["resident_state"] as? String == "unloaded"
                && status["speech_backend"] as? String == "qwen3"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_models_unloaded"
                && $0["resident_state"] as? String == "unloaded"
                && $0["speech_backend"] as? String == "qwen3"
        }
    })

    let queuedFileID = await runtime.speak(
        text: "Save this request once the resident models are back.",
        with: "default-femme",
        as: .file,
        id: "req-after-unload"
    ).id
    #expect(queuedFileID == "req-after-unload")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-after-unload"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_resident_models"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-after-unload"
            && $0["event"] as? String == "started"
    })

    let reloadID = await runtime.reloadModels(id: "req-reload").id
    #expect(reloadID == "req-reload")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "warming_resident_model"
                && $0["resident_state"] as? String == "warming"
                && $0["speech_backend"] as? String == "qwen3"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-reload",
                $0["ok"] as? Bool == true,
                let status = $0["status"] as? [String: Any]
            else {
                return false
            }

            return status["stage"] as? String == "resident_model_ready"
                && status["resident_state"] as? String == "ready"
                && status["speech_backend"] as? String == "qwen3"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-after-unload"
                && $0["ok"] as? Bool == true
                && $0["generated_file"] != nil
        }
    })
    #expect(await backendLoads.values() == [.qwen3, .qwen3])
}

@Test func switchSpeechBackendActsAsAnOrderedBarrierWhilePlaybackDrains() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
    let backendLoads = BackendLoadRecorder()
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
        speechBackend: .qwen3,
        residentModelLoader: { backend in
            await backendLoads.record(backend)
            return makeResidentModel()
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.speak(text: "Hello there", with: "default-femme", as: .live, id: "req-active")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let switchID = await runtime.switchSpeechBackend(to: .marvis, id: "req-switch-busy").id
    #expect(switchID == "req-switch-busy")
    let queuedFileID = await runtime.speak(
        text: "Save this request after the backend switch barrier.",
        with: "default-femme",
        as: .file,
        id: "req-after-switch"
    ).id
    #expect(queuedFileID == "req-after-switch")

    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-after-switch"
            && $0["ok"] as? Bool == true
            && $0["generated_file"] != nil
    })

    await playbackDrain.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "warming_resident_model"
                && $0["speech_backend"] as? String == "marvis"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "marvis"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-switch-busy",
                $0["ok"] as? Bool == true,
                $0["speech_backend"] as? String == "marvis",
                let status = $0["status"] as? [String: Any]
            else {
                return false
            }

            return status["stage"] as? String == "resident_model_ready"
                && status["speech_backend"] as? String == "marvis"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-after-switch",
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == "req-after-switch-artifact-1"
        }
    })

    let generationJobID = await runtime.generationJob(id: "req-after-switch", requestID: "req-after-switch-job").id
    #expect(generationJobID == "req-after-switch-job")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-after-switch-job",
                $0["ok"] as? Bool == true,
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["speech_backend"] as? String == "marvis"
        }
    })
    #expect(await backendLoads.values() == [.qwen3, .marvis])
}

@Test func clearQueueFailsQueuedRequestsWhenGenerationQueueHasWaitingWork() async throws {
    let output = OutputRecorder()
    let profileGate = AsyncGate()

    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            makeProfileModel {
                await profileGate.wait()
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

    _ = await runtime.createProfile(
        named: "bright-guide",
        from: "Hello there",
        voice: "Warm and bright",
        id: "req-active"
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["event"] as? String == "started"
        }
    })

    let queuedHandle = await runtime.submit(.listProfiles(id: "req-queued"))
    var iterator = queuedHandle.events.makeAsyncIterator()
    let queued = try await iterator.next()
    #expect(
        queued == .queued(
            WorkerQueuedEvent(
                id: "req-queued",
                reason: .waitingForActiveRequest,
                queuePosition: 1
            )
        )
    )

    let clearID = await runtime.clearQueue(id: "req-clear").id
    #expect(clearID == "req-clear")

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-clear"
                && $0["ok"] as? Bool == true
                && $0["cleared_count"] as? Int == 1
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-queued"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })

    do {
        while let _ = try await iterator.next() {}
        Issue.record("The queued request stream should have thrown after clearQueue removed it.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }

    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-active"
            && $0["ok"] as? Bool == false
    })
    await profileGate.open()
}

@Test func cancelRequestCanCancelActivePlaybackImmediately() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
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
        residentModelLoader: { _ in makeResidentModel() }
    )

    let activeHandle = await runtime.submit(
        .queueSpeech(
            id: "req-active",
            text: "Hello there",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: nil
        )
    )
    var activeIterator = activeHandle.events.makeAsyncIterator()

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    while let event = try await activeIterator.next() {
        if case .progress(let progress) = event, progress.stage == .prerollReady {
            break
        }
    }

    let cancelID = await runtime.cancelRequest("req-active", requestID: "req-cancel").id
    #expect(cancelID == "req-cancel")

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-cancel"
                && $0["ok"] as? Bool == true
                && $0["cancelled_request_id"] as? String == "req-active"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })
    #expect(playback.stopCount >= 1)

    do {
        while let _ = try await activeIterator.next() {}
        Issue.record("The active request stream should have thrown after cancelRequest cancelled it.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }

    await playbackDrain.open()
}

@Test func cancelRequestCanCancelQueuedWorkImmediately() async throws {
    let output = OutputRecorder()
    let profileGate = AsyncGate()

    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            makeProfileModel {
                await profileGate.wait()
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

    _ = await runtime.createProfile(
        named: "bright-guide",
        from: "Hello there",
        voice: "Warm and bright",
        id: "req-active"
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["event"] as? String == "started"
        }
    })

    let queuedHandle = await runtime.submit(.listProfiles(id: "req-queued"))
    var iterator = queuedHandle.events.makeAsyncIterator()
    let queued = try await iterator.next()
    #expect(
        queued == .queued(
            WorkerQueuedEvent(
                id: "req-queued",
                reason: .waitingForActiveRequest,
                queuePosition: 1
            )
        )
    )

    let cancelID = await runtime.cancelRequest("req-queued", requestID: "req-cancel").id
    #expect(cancelID == "req-cancel")

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-cancel"
                && $0["ok"] as? Bool == true
                && $0["cancelled_request_id"] as? String == "req-queued"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-queued"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })

    do {
        while let _ = try await iterator.next() {}
        Issue.record("The queued request stream should have thrown after cancelRequest removed it.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }
    await profileGate.open()
}

@Test func libraryHelpersSubmitProfileAndGeneratedFileWorkerProtocolRequests() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.createProfile(
        named: "bright-guide",
        from: "Hello there",
        voice: "Warm and bright",
        outputPath: nil,
        id: "req-create"
    ).id
    #expect(createID == "req-create")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let listID = await runtime.profiles(id: "req-list").id
    #expect(listID == "req-list")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-list",
                $0["ok"] as? Bool == true,
                let profiles = $0["profiles"] as? [[String: Any]]
            else {
                return false
            }

            return profiles.contains { $0["profile_name"] as? String == "bright-guide" }
        }
    })

    let speakFileID = await runtime.speak(
        text: "Save this request as an artifact.",
        with: "bright-guide",
        as: .file,
        id: "req-file-helper"
    ).id
    let fileArtifactID = "req-file-helper-artifact-1"
    #expect(speakFileID == "req-file-helper")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-file-helper",
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == fileArtifactID
        }
    })

    let generatedFileID = await runtime.generatedFile(id: fileArtifactID, requestID: "req-file-read").id
    #expect(generatedFileID == "req-file-read")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-file-read",
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == fileArtifactID
        }
    })

    let generatedFilesID = await runtime.generatedFiles(id: "req-file-list").id
    #expect(generatedFilesID == "req-file-list")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-file-list",
                $0["ok"] as? Bool == true,
                let generatedFiles = $0["generated_files"] as? [[String: Any]]
            else {
                return false
            }

            return generatedFiles.contains {
                $0["artifact_id"] as? String == fileArtifactID
            }
        }
    })

    let generationJobID = await runtime.generationJob(id: "req-file-helper", requestID: "req-job-read").id
    #expect(generationJobID == "req-job-read")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-job-read",
                $0["ok"] as? Bool == true,
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["job_id"] as? String == "req-file-helper"
                && generationJob["job_kind"] as? String == "file"
                && generationJob["state"] as? String == "completed"
                && (generationJob["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == fileArtifactID
        }
    })

    let generationJobsID = await runtime.generationJobs(id: "req-job-list").id
    #expect(generationJobsID == "req-job-list")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-job-list",
                $0["ok"] as? Bool == true,
                let generationJobs = $0["generation_jobs"] as? [[String: Any]]
            else {
                return false
            }

            return generationJobs.contains {
                $0["job_id"] as? String == "req-file-helper"
                    && $0["job_kind"] as? String == "file"
                    && $0["state"] as? String == "completed"
                    && ($0["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == fileArtifactID
            }
        }
    })

    let removeID = await runtime.removeProfile(named: "bright-guide", id: "req-remove").id
    #expect(removeID == "req-remove")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-remove"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })
}

@Test func createProfileResolvesRelativeOutputPathAgainstExplicitCallerWorkingDirectory() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    let callerWorkingDirectory = makeTempDirectoryURL()
    defer {
        try? FileManager.default.removeItem(at: storeRoot)
        try? FileManager.default.removeItem(at: callerWorkingDirectory)
    }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let exportURL = callerWorkingDirectory.appendingPathComponent("exports/voice.wav")
    await runtime.accept(
        line: #"{"id":"req-relative-export","op":"create_profile","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"exports/voice.wav","cwd":"\#(callerWorkingDirectory.path)"}"#
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-relative-export"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })
    #expect(FileManager.default.fileExists(atPath: exportURL.path))
}

@Test func createProfileRejectsRelativeOutputPathWithoutExplicitCallerWorkingDirectory() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-relative-export-missing-cwd","op":"create_profile","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"exports/voice.wav"}"#
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            ($0["id"] as? String) == "req-relative-export-missing-cwd"
                && ($0["ok"] as? Bool) == false
                && ($0["code"] as? String) == "invalid_request"
                && (($0["message"] as? String)?.contains("did not provide 'cwd'") ?? false)
        }
    })
}

@Test func generateBatchAcknowledgesQueueThenCompletesWithGeneratedBatchMetadata() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
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
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let batchID = await runtime.generateBatch(
        [
            SpeakSwiftly.BatchItem(text: "First generated file."),
            SpeakSwiftly.BatchItem(
                artifactID: "custom-batch-artifact",
                text: "Second generated file.",
                textProfileName: "logs"
            ),
        ],
        with: "default-femme",
        id: "req-batch-1"
    ).id
    #expect(batchID == "req-batch-1")

    #expect(await waitUntil {
        output.countJSONObjects {
            $0["id"] as? String == "req-batch-1"
                && $0["ok"] as? Bool == true
        } == 2
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-batch-1",
                let generationJob = $0["generation_job"] as? [String: Any],
                let items = generationJob["items"] as? [[String: Any]]
            else {
                return false
            }

            return generationJob["job_id"] as? String == "req-batch-1"
                && generationJob["job_kind"] as? String == "batch"
                && generationJob["state"] as? String == "queued"
                && items.count == 2
                && items[0]["artifact_id"] as? String == "req-batch-1-artifact-1"
                && items[1]["artifact_id"] as? String == "custom-batch-artifact"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-batch-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_batch"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-batch-1",
                let generatedBatch = $0["generated_batch"] as? [String: Any],
                let generationJob = $0["generation_job"] as? [String: Any],
                let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatch["batch_id"] as? String == "req-batch-1"
                && generatedBatch["state"] as? String == "completed"
                && generationJob["job_kind"] as? String == "batch"
                && generationJob["state"] as? String == "completed"
                && artifacts.count == 2
                && artifacts.contains { $0["artifact_id"] as? String == "req-batch-1-artifact-1" }
                && artifacts.contains { $0["artifact_id"] as? String == "custom-batch-artifact" }
        }
    })

    let generatedBatchID = await runtime.generatedBatch(id: "req-batch-1", requestID: "req-batch-read").id
    #expect(generatedBatchID == "req-batch-read")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-batch-read",
                let generatedBatch = $0["generated_batch"] as? [String: Any],
                let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatch["batch_id"] as? String == "req-batch-1"
                && artifacts.count == 2
        }
    })

    let generatedBatchesID = await runtime.generatedBatches(id: "req-batches-read").id
    #expect(generatedBatchesID == "req-batches-read")
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-batches-read",
                let generatedBatches = $0["generated_batches"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatches.contains {
                $0["batch_id"] as? String == "req-batch-1"
                    && $0["state"] as? String == "completed"
            }
        }
    })
}

@Test func createCloneStoresProvidedTranscriptWithoutTranscription() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)

    let referenceAudioURL = storeRoot.appendingPathComponent("reference.wav")
    try Data([0x01]).write(to: referenceAudioURL, options: .atomic)

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        loadedCloneAudioSamples: [0.1, 0.2, 0.3],
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.createClone(
        named: "ghost-copy",
        from: referenceAudioURL,
        transcript: "Provided transcript",
        id: "req-clone"
    ).id
    #expect(createID == "req-clone")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-clone"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "ghost-copy"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-clone"
            && $0["stage"] as? String == "transcribing_clone_audio"
    })

    let storedProfile = try makeProfileStore(rootURL: storeRoot).loadProfile(named: "ghost-copy")
    #expect(storedProfile.manifest.sourceText == "Provided transcript")
    #expect(storedProfile.manifest.voiceDescription == ModelFactory.importedCloneVoiceDescription)
    #expect(storedProfile.manifest.modelRepo == ModelFactory.importedCloneModelRepo)
}

@Test func createCloneResolvesRelativeReferenceAudioAgainstExplicitCallerWorkingDirectory() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    let callerWorkingDirectory = makeTempDirectoryURL()
    defer {
        try? FileManager.default.removeItem(at: storeRoot)
        try? FileManager.default.removeItem(at: callerWorkingDirectory)
    }
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: callerWorkingDirectory, withIntermediateDirectories: true)

    let referenceAudioURL = callerWorkingDirectory.appendingPathComponent("reference.wav")
    try Data([0x01]).write(to: referenceAudioURL, options: .atomic)

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        loadedCloneAudioSamples: [0.1, 0.2, 0.3],
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-relative-clone","op":"create_clone","profile_name":"ghost-copy","reference_audio_path":"reference.wav","vibe":"masc","transcript":"Provided transcript","cwd":"\#(callerWorkingDirectory.path)"}"#
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-relative-clone"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "ghost-copy"
        }
    })
}

@Test func createCloneCanInferTranscriptFromReferenceAudio() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)

    let referenceAudioURL = storeRoot.appendingPathComponent("reference.wav")
    try Data([0x01]).write(to: referenceAudioURL, options: .atomic)

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        loadedCloneAudioSamples: [0.4, 0.5, 0.6],
        residentModelLoader: { _ in makeResidentModel() },
        cloneTranscriptionModelLoader: {
            makeCloneTranscriptionModel(transcript: "Inferred transcript")
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.createClone(
        named: "ghost-copy",
        from: referenceAudioURL,
        transcript: nil,
        id: "req-clone"
    ).id
    #expect(createID == "req-clone")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-clone"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "ghost-copy"
        }
    })
    #expect(output.containsJSONObject {
        $0["id"] as? String == "req-clone"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "loading_clone_transcription_model"
    })
    #expect(output.containsJSONObject {
        $0["id"] as? String == "req-clone"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "transcribing_clone_audio"
    })

    let storedProfile = try makeProfileStore(rootURL: storeRoot).loadProfile(named: "ghost-copy")
    #expect(storedProfile.manifest.sourceText == "Inferred transcript")
}

@Test func createCloneFailsWhenTranscriptInferenceReturnsNothing() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)

    let referenceAudioURL = storeRoot.appendingPathComponent("reference.wav")
    try Data([0x01]).write(to: referenceAudioURL, options: .atomic)

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        loadedCloneAudioSamples: [0.7, 0.8, 0.9],
        residentModelLoader: { _ in makeResidentModel() },
        cloneTranscriptionModelLoader: {
            makeCloneTranscriptionModel(transcript: "")
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.createClone(
        named: "ghost-copy",
        from: referenceAudioURL,
        transcript: nil,
        id: "req-clone"
    ).id
    #expect(createID == "req-clone")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-clone"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "model_generation_failed"
        }
    })
}

@Test func typedStatusAndRequestStreamsExposeWorkerOutputForLibraryConsumers() async throws {
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

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    let statuses = await runtime.statusEvents()
    var statusIterator = statuses.makeAsyncIterator()

    await runtime.start()

    let firstStatus = await statusIterator.next()
    let secondStatus = await statusIterator.next()
    #expect(firstStatus == WorkerStatusEvent(stage: .warmingResidentModel, residentState: .warming, speechBackend: .qwen3))
    #expect(secondStatus == WorkerStatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3))

    let handle = await runtime.submit(
        .listProfiles(id: "req-stream")
    )
    var iterator = handle.events.makeAsyncIterator()
    let createdAt = try store.loadProfile(named: "default-femme").manifest.createdAt

    let started = try await iterator.next()
    let completed = try await iterator.next()
    let terminal = try await iterator.next()

    #expect(started == .started(WorkerStartedEvent(id: "req-stream", op: "list_profiles")))
    #expect(
        completed == .completed(
            WorkerSuccessResponse(
                id: "req-stream",
                profiles: [
                    ProfileSummary(
                        profileName: "default-femme",
                        vibe: .femme,
                        createdAt: createdAt,
                        voiceDescription: "Warm and bright.",
                        sourceText: "Reference transcript"
                    )
                ]
            )
        )
    )
    #expect(terminal == nil)
}

@Test func speakLiveUsesStableResidentGenerationParameters() async throws {
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

    let recorder = ResidentModelRecorder()
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel(recorder: recorder) }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.speak(
        text: "Hello there, galew.",
        with: "default-femme",
        as: .live,
        id: "req-generation-params"
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-generation-params"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    #expect(recorder.lastText == "Hello there, gale wumbo.")
    #expect(recorder.lastGenerationParameters?.maxTokens == 56)
    #expect(recorder.lastGenerationParameters?.temperature == 0.9)
    #expect(recorder.lastGenerationParameters?.topP == 1.0)
    #expect(recorder.lastGenerationParameters?.repetitionPenalty == 1.05)
}

@Test func lateStatusSubscribersReceiveCurrentReadySnapshot() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let statuses = await runtime.statusEvents()
    var iterator = statuses.makeAsyncIterator()

    #expect(await iterator.next() == WorkerStatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3))
}

@Test func droppingStatusSubscriptionDoesNotRetainRuntime() async throws {
    let output = OutputRecorder()
    let weakRuntime = WeakRuntimeBox()

    var runtime: WorkerRuntime? = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )
    weakRuntime.value = runtime

    var statuses: AsyncStream<SpeakSwiftly.StatusEvent>? = await runtime?.statusEvents()
    _ = statuses?.makeAsyncIterator()

    statuses = nil
    runtime = nil

    #expect(await waitUntil { weakRuntime.value == nil })
}

@Test func startIsIdempotentForLibraryConsumers() async throws {
    actor LoadCounter {
        private(set) var count = 0

        func increment() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    let output = OutputRecorder()
    let loadCounter = LoadCounter()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await loadCounter.increment()
            return makeResidentModel()
        }
    )

    let statuses = await runtime.statusEvents()
    var iterator = statuses.makeAsyncIterator()

    await runtime.start()
    await runtime.start()

    let firstStatus = await iterator.next()
    let secondStatus = await iterator.next()

    #expect(firstStatus == WorkerStatusEvent(stage: .warmingResidentModel, residentState: .warming, speechBackend: .qwen3))
    #expect(secondStatus == WorkerStatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3))
    #expect(await loadCounter.value() == 1)
    #expect(
        output.countJSONObjects {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "warming_resident_model"
        } == 1
    )
    #expect(
        output.countJSONObjects {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        } == 1
    )
}

@Test func typedRequestStreamKeepsBackgroundAcknowledgementAndLaterCompletionSeparate() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
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
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.speak(text: "Hello there", with: "default-femme", as: .live, id: "req-active")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let handle = await runtime.submit(
        .queueSpeech(
            id: "req-stream-bg",
            text: "Hi there",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: nil
        )
    )
    var iterator = handle.events.makeAsyncIterator()

    let acknowledged = try await iterator.next()
    #expect(acknowledged == .acknowledged(WorkerSuccessResponse(id: "req-stream-bg")))

    await playbackDrain.open()

    var sawCompletion = false
    while let event = try await iterator.next() {
        if case .completed(WorkerSuccessResponse(id: "req-stream-bg", profileName: nil, profilePath: nil, profiles: nil)) = event {
            sawCompletion = true
            break
        }
    }

    #expect(sawCompletion)
}

@Test func listProfilesSkipsCorruptEntriesAndStillReturnsHealthyProfiles() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "healthy",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Healthy transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01])
    )

    let brokenDirectory = store.profileDirectoryURL(for: "broken")
    try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: store.manifestURL(for: brokenDirectory))

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"list_profiles"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-1",
                $0["ok"] as? Bool == true,
                let profiles = $0["profiles"] as? [[String: Any]]
            else {
                return false
            }

            return profiles.count == 1
                && profiles[0]["profile_name"] as? String == "healthy"
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
        residentModelLoader: { _ in makeResidentModel() },
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
        line: #"{"id":"req-1","op":"create_profile","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_profile"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"delete_profile","profile_name":"remove-me"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"queue_speech_live","text":"Hi there","profile_name":"default-femme"}"#)

    await profileGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-3"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_live"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "delete_profile"
        }
    })

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_profile", "req-3:queue_speech_live", "req-2:delete_profile"])
}

@Test func waitingSpeakLiveForQueuedProfileCreationDoesNotJumpAheadOfThatProfile() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let profileGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            makeProfileModel {
                await profileGate.wait()
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

    await runtime.accept(
        line: #"{"id":"req-1","op":"create_profile","profile_name":"brand-new","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_profile"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"queue_speech_live","text":"Hi there","profile_name":"brand-new"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"list_profiles"}"#)

    await profileGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_live"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-3"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "list_profiles"
        }
    })

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_profile", "req-2:queue_speech_live", "req-3:list_profiles"])
}
