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

    let activeHandle = await runtime.generate.speech(text: "Hello there", with: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
                $0["id"] as? String == activeHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let queuedHandle = await runtime.generate.speech(text: "Hi there", with: "default-femme")

    let listID = await runtime.player.list().id

    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == listID,
                $0["ok"] as? Bool == true,
                let active = $0["active_request"] as? [String: Any],
                let queue = $0["queue"] as? [[String: Any]]
            else {
                return false
            }

            return active["id"] as? String == activeHandle.id
                && queue.count == 1
                && queue[0]["id"] as? String == queuedHandle.id
                && queue[0]["queue_position"] as? Int == 1
        }
    })

    await playbackDrain.open()
}

@Test func playbackStateStaysConsistentWhileLivePlaybackOwnsTheActiveRequest() async throws {
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

    let activeHandle = await runtime.generate.speech(text: "Hello there", with: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    _ = await runtime.generate.speech(text: "Hi there", with: "default-femme")
    let stateID = await runtime.player.state().id

    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == stateID,
                $0["ok"] as? Bool == true,
                let playbackState = $0["playback_state"] as? [String: Any],
                let activeRequest = playbackState["active_request"] as? [String: Any]
            else {
                return false
            }

            return playbackState["state"] as? String == "playing"
                && activeRequest["id"] as? String == activeHandle.id
        }
    })

    await playbackDrain.open()
}

@Test func runtimeOverviewCapturesDualLaneMarvisGenerationAndPlaybackStability() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
    let laneAGenerationDrain = AsyncGate()
    let laneBGenerationDrain = AsyncGate()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    @Sendable func makeLaneModel(_ gate: AsyncGate) -> AnySpeechModel {
        AnySpeechModel(
            sampleRate: 24_000,
            generate: { _, _, _, _, _, _ in
                [0.1, 0.2]
            },
            generateSamplesStream: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(Array(repeating: 0.1, count: 24_000))
                    Task {
                        await gate.wait()
                        continuation.finish()
                    }
                }
            }
        )
    }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "lane-a-primary",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x01, 0x02])
    )
    _ = try store.createProfile(
        profileName: "lane-b-secondary",
        vibe: .masc,
        modelRepo: "test-model",
        voiceDescription: "Grounded and rich.",
        sourceText: "Reference transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x03, 0x04])
    )
    _ = try store.createProfile(
        profileName: "lane-a-tertiary",
        vibe: .androgenous,
        modelRepo: "test-model",
        voiceDescription: "Balanced and clear.",
        sourceText: "Reference transcript",
        sampleRate: 24_000,
        canonicalAudioData: Data([0x05, 0x06])
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        speechBackend: .marvis,
        residentModelLoader: { _ in
            ResidentSpeechModels.marvis(
                MarvisResidentModels(
                    conversationalA: makeLaneModel(laneAGenerationDrain),
                    conversationalB: makeLaneModel(laneBGenerationDrain)
                )
            )
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "marvis"
        }
    })

    let firstHandle = await runtime.generate.speech(text: "First request", with: "lane-a-primary")
    let secondHandle = await runtime.generate.speech(text: "Second request", with: "lane-b-secondary")
    let thirdHandle = await runtime.generate.speech(text: "Third request", with: "lane-a-tertiary")

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == firstHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == secondHandle.id
                && $0["event"] as? String == "started"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == thirdHandle.id
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_marvis_generation_lane"
        }
    })

    let overviewID = await runtime.overview().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == overviewID,
                $0["ok"] as? Bool == true,
                let overview = $0["runtime_overview"] as? [String: Any],
                let generationQueue = overview["generation_queue"] as? [String: Any],
                let activeRequests = generationQueue["active_requests"] as? [[String: Any]],
                let queuedRequests = generationQueue["queue"] as? [[String: Any]],
                let playbackState = overview["playback_state"] as? [String: Any],
                let playbackActiveRequest = playbackState["active_request"] as? [String: Any]
            else {
                return false
            }

            let activeIDs = Set(activeRequests.compactMap { $0["id"] as? String })
            let queuedIDs = Set(queuedRequests.compactMap { $0["id"] as? String })
            return overview["speech_backend"] as? String == "marvis"
                && activeIDs == Set([firstHandle.id, secondHandle.id])
                && queuedIDs == Set([thirdHandle.id])
                && playbackState["state"] as? String == "playing"
                && playbackState["is_stable_for_concurrent_generation"] as? Bool == true
                && playbackState["is_rebuffering"] as? Bool == false
                && (playbackState["stable_buffered_audio_ms"] as? Int ?? 0) >= 0
                && (playbackState["stable_buffer_target_ms"] as? Int ?? 0) > 0
                && playbackActiveRequest["id"] as? String == firstHandle.id
        }
    })

    await laneAGenerationDrain.open()
    await laneBGenerationDrain.open()
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

    let statusID = await runtime.status().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == statusID,
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

    let switchID = await runtime.switchSpeechBackend(to: .marvis).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == switchID,
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

    let unloadID = await runtime.unloadModels().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == unloadID,
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

    let queuedFileID = await runtime.generate.audio(
        text: "Save this request once the resident models are back.",
        with: "default-femme"
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == queuedFileID
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_resident_models"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == queuedFileID
            && $0["event"] as? String == "started"
    })

    let reloadID = await runtime.reloadModels().id
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
                $0["id"] as? String == reloadID,
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
            $0["id"] as? String == queuedFileID
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

    let activeHandle = await runtime.generate.speech(text: "Hello there", with: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
                $0["id"] as? String == activeHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let switchID = await runtime.switchSpeechBackend(to: .marvis).id
    let queuedFileID = await runtime.generate.audio(
        text: "Save this request after the backend switch barrier.",
        with: "default-femme"
    ).id

    #expect(!output.containsJSONObject {
        $0["id"] as? String == queuedFileID
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
                $0["id"] as? String == switchID,
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
                $0["id"] as? String == queuedFileID,
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == "\(queuedFileID)-artifact-1"
        }
    })

    let generationJobID = await runtime.jobs.job(id: queuedFileID).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationJobID,
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

    let activeCreateID = await runtime.voices.create(design: "bright-guide",
        from: "Hello there",
        vibe: .femme,
        voice: "Warm and bright"
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeCreateID
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

    let clearID = await runtime.player.clearQueue().id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == clearID
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
        $0["id"] as? String == activeCreateID
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

    let cancelID = await runtime.player.cancelRequest("req-active").id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == cancelID
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

    let activeCreateID = await runtime.voices.create(design: "bright-guide",
        from: "Hello there",
        vibe: .femme,
        voice: "Warm and bright"
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeCreateID
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

    let cancelID = await runtime.player.cancelRequest("req-queued").id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == cancelID
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

    let createID = await runtime.voices.create(design: "bright-guide",
        from: "Hello there",
        vibe: .femme,
        voice: "Warm and bright",
        outputPath: nil
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let listID = await runtime.voices.list().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == listID,
                $0["ok"] as? Bool == true,
                let profiles = $0["profiles"] as? [[String: Any]]
            else {
                return false
            }

            return profiles.contains { $0["profile_name"] as? String == "bright-guide" }
        }
    })

    let renameID = await runtime.voices.rename("bright-guide", to: "clear-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == renameID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "clear-guide"
        }
    })

    let renamedListID = await runtime.voices.list().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == renamedListID,
                $0["ok"] as? Bool == true,
                let profiles = $0["profiles"] as? [[String: Any]]
            else {
                return false
            }

            let names = profiles.compactMap { $0["profile_name"] as? String }
            return names.contains("clear-guide") && !names.contains("bright-guide")
        }
    })

    let rerollID = await runtime.voices.reroll("clear-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == rerollID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "clear-guide"
        }
    })

    let speakFileID = await runtime.generate.audio(
        text: "Save this request as an artifact.",
        with: "clear-guide"
    ).id
    let fileArtifactID = "\(speakFileID)-artifact-1"
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == speakFileID,
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == fileArtifactID
        }
    })

    let generatedFileID = await runtime.artifacts.file(id: fileArtifactID).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generatedFileID,
                $0["ok"] as? Bool == true,
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == fileArtifactID
        }
    })

    let generatedFilesID = await runtime.artifacts.files().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generatedFilesID,
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

    let generationJobID = await runtime.jobs.job(id: speakFileID).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationJobID,
                $0["ok"] as? Bool == true,
                let generationJob = $0["generation_job"] as? [String: Any]
            else {
                return false
            }

            return generationJob["job_id"] as? String == speakFileID
                && generationJob["job_kind"] as? String == "file"
                && generationJob["state"] as? String == "completed"
                && (generationJob["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == fileArtifactID
        }
    })

    let generationJobsID = await runtime.jobs.list().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationJobsID,
                $0["ok"] as? Bool == true,
                let generationJobs = $0["generation_jobs"] as? [[String: Any]]
            else {
                return false
            }

            return generationJobs.contains {
                $0["job_id"] as? String == speakFileID
                    && $0["job_kind"] as? String == "file"
                    && $0["state"] as? String == "completed"
                    && ($0["items"] as? [[String: Any]])?.first?["artifact_id"] as? String == fileArtifactID
            }
        }
    })

    let removeID = await runtime.voices.delete(named: "clear-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == removeID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "clear-guide"
        }
    })
}

@Test func rerollRebuildsAnExistingProfileInPlaceFromItsStoredInputs() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    let originalAudio = Data([0x01, 0x02, 0x03, 0x04])
    _ = try store.createProfile(
        profileName: "bright-guide",
        vibe: .femme,
        modelRepo: ModelFactory.profileModelRepo,
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24_000,
        canonicalAudioData: originalAudio
    )

    let rerolledSamples: [Float] = [0.7, 0.8, 0.9]
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
        profileModelLoader: {
            AnySpeechModel(
                sampleRate: 24_000,
                generate: { _, _, _, _, _, _ in rerolledSamples },
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

    let rerollID = await runtime.voices.reroll("bright-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == rerollID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let rerolledProfile = try store.loadProfile(named: "bright-guide")
    #expect(rerolledProfile.manifest.profileName == "bright-guide")
    #expect(rerolledProfile.manifest.sourceText == "Hello there")
    #expect(rerolledProfile.manifest.voiceDescription == "Warm and bright.")
    #expect(try Data(contentsOf: rerolledProfile.referenceAudioURL) == rawTestAudioData(for: rerolledSamples))
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
        line: #"{"id":"req-relative-export","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"exports/voice.wav","cwd":"\#(callerWorkingDirectory.path)"}"#
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
        line: #"{"id":"req-relative-export-missing-cwd","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright","output_path":"exports/voice.wav"}"#
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

    let batchID = await runtime.generate.batch(
        [
            SpeakSwiftly.BatchItem(text: "First generated file."),
            SpeakSwiftly.BatchItem(
                artifactID: "custom-batch-artifact",
                text: "Second generated file.",
                textProfileName: "logs"
            ),
        ],
        with: "default-femme"
    ).id

    #expect(await waitUntil {
        output.countJSONObjects {
            $0["id"] as? String == batchID
                && $0["ok"] as? Bool == true
        } == 2
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == batchID,
                let generationJob = $0["generation_job"] as? [String: Any],
                let items = generationJob["items"] as? [[String: Any]]
            else {
                return false
            }

            return generationJob["job_id"] as? String == batchID
                && generationJob["job_kind"] as? String == "batch"
                && generationJob["state"] as? String == "queued"
                && items.count == 2
                && items[0]["artifact_id"] as? String == "\(batchID)-artifact-1"
                && items[1]["artifact_id"] as? String == "custom-batch-artifact"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == batchID
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_batch"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == batchID,
                let generatedBatch = $0["generated_batch"] as? [String: Any],
                let generationJob = $0["generation_job"] as? [String: Any],
                let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatch["batch_id"] as? String == batchID
                && generatedBatch["state"] as? String == "completed"
                && generationJob["job_kind"] as? String == "batch"
                && generationJob["state"] as? String == "completed"
                && artifacts.count == 2
                && artifacts.contains { $0["artifact_id"] as? String == "\(batchID)-artifact-1" }
                && artifacts.contains { $0["artifact_id"] as? String == "custom-batch-artifact" }
        }
    })

    let generatedBatchID = await runtime.artifacts.batch(id: batchID).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generatedBatchID,
                let generatedBatch = $0["generated_batch"] as? [String: Any],
                let artifacts = generatedBatch["artifacts"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatch["batch_id"] as? String == batchID
                && artifacts.count == 2
        }
    })

    let generatedBatchesID = await runtime.artifacts.batches().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generatedBatchesID,
                let generatedBatches = $0["generated_batches"] as? [[String: Any]]
            else {
                return false
            }

            return generatedBatches.contains {
                $0["batch_id"] as? String == batchID
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

    let createID = await runtime.voices.create(clone: "ghost-copy",
        from: referenceAudioURL,
        transcript: "Provided transcript"
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "ghost-copy"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == createID
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
        line: #"{"id":"req-relative-clone","op":"create_voice_profile_from_audio","profile_name":"ghost-copy","reference_audio_path":"reference.wav","vibe":"masc","transcript":"Provided transcript","cwd":"\#(callerWorkingDirectory.path)"}"#
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

    let createID = await runtime.voices.create(clone: "ghost-copy",
        from: referenceAudioURL,
        transcript: nil
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "ghost-copy"
        }
    })
    #expect(output.containsJSONObject {
        $0["id"] as? String == createID
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "loading_clone_transcription_model"
    })
    #expect(output.containsJSONObject {
        $0["id"] as? String == createID
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

    let createID = await runtime.voices.create(clone: "ghost-copy",
        from: referenceAudioURL,
        transcript: nil
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == createID
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

    var sawStarted = false
    var sawCompleted = false

    while let event = try await iterator.next() {
        switch event {
        case .queued:
            continue

        case .started(let started):
            #expect(started == WorkerStartedEvent(id: "req-stream", op: "list_voice_profiles"))
            sawStarted = true

        case .completed(let response):
            #expect(
                response == WorkerSuccessResponse(
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
            sawCompleted = true
            break

        case .progress, .acknowledged:
            Issue.record("The typed list-voice-profiles request stream emitted an unexpected event before completion: \(event)")
        }
    }

    #expect(sawStarted)
    #expect(sawCompleted)
}

@Test func requestObservationReturnsNilAndFinishedStreamForUnknownRequestID() async throws {
    let runtime = try await makeRuntime(
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()

    #expect(await runtime.request(id: "missing-request") == nil)

    let updates = await runtime.updates(for: "missing-request")
    var iterator = updates.makeAsyncIterator()
    let first = try await iterator.next()
    #expect(first == nil)
}

@Test func requestObservationExposesReplayableGenerationEventsForQwenRequests() async throws {
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
        residentModelLoader: { _ in makeResidentModel(chunkCount: 2) }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let handle = await runtime.generate.audio(
        text: "Hello from the generation event side channel.",
        with: "default-femme"
    )

    let runtimeEvents = await runtime.generationEvents(for: handle.id)
    var runtimeIterator = runtimeEvents.makeAsyncIterator()

    if case .token(let token)? = try await runtimeIterator.next()?.event {
        #expect(token == 101)
    } else {
        Issue.record("Expected the first replayed generation event to be a qwen token.")
    }

    if case .info(let info)? = try await runtimeIterator.next()?.event {
        #expect(info.promptTokenCount == 12)
        #expect(info.generationTokenCount == 8)
        #expect(info.prefillTime == 0.12)
        #expect(info.generateTime == 0.34)
        #expect(info.tokensPerSecond == 56.7)
        #expect(info.peakMemoryUsage == 1.23)
    } else {
        Issue.record("Expected the second replayed generation event to carry qwen generation info.")
    }

    if case .audioChunk(let sampleCount)? = try await runtimeIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the third replayed generation event to describe the first audio chunk.")
    }

    if case .audioChunk(let sampleCount)? = try await runtimeIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the fourth replayed generation event to describe the second audio chunk.")
    }

    #expect(try await runtimeIterator.next() == nil)

    var handleIterator = handle.generationEvents.makeAsyncIterator()
    if case .token(let token)? = try await handleIterator.next()?.event {
        #expect(token == 101)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the qwen token event.")
    }
    if case .info(let info)? = try await handleIterator.next()?.event {
        #expect(info.promptTokenCount == 12)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the qwen info event.")
    }
    if case .audioChunk(let sampleCount)? = try await handleIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the first audio chunk event.")
    }
    if case .audioChunk(let sampleCount)? = try await handleIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the second audio chunk event.")
    }
    #expect(try await handleIterator.next() == nil)
}

@Test func requestObservationReplaysQueuedStateAndFansOutToMultipleSubscribers() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()

    let handle = await runtime.submit(.listProfiles(id: "req-late"))
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-late"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_resident_model"
        }
    })

    let snapshot = await runtime.request(id: "req-late")
    #expect(snapshot?.id == "req-late")
    #expect(snapshot?.operation == "list_voice_profiles")
    #expect(snapshot?.sequence == 1)
    if let snapshot {
        switch snapshot.state {
        case .queued(let queued):
            #expect(queued == WorkerQueuedEvent(id: "req-late", reason: .waitingForResidentModel, queuePosition: 1))
        default:
            Issue.record("Expected queued state in the late-attach snapshot, got \(snapshot.state)")
        }
        #expect(snapshot.acceptedAt <= snapshot.lastUpdatedAt)
    }

    let updatesA = await runtime.updates(for: "req-late")
    let updatesB = await runtime.updates(for: "req-late")
    var iteratorA = updatesA.makeAsyncIterator()
    var iteratorB = updatesB.makeAsyncIterator()

    let replayA = try await iteratorA.next()
    let replayB = try await iteratorB.next()
    #expect(replayA?.sequence == 1)
    #expect(replayB?.sequence == 1)
    if case .queued(let queuedA)? = replayA?.state {
        #expect(queuedA.reason == .waitingForResidentModel)
    } else {
        Issue.record("Expected subscriber A to replay a queued update first.")
    }
    if case .queued(let queuedB)? = replayB?.state {
        #expect(queuedB.reason == .waitingForResidentModel)
    } else {
        Issue.record("Expected subscriber B to replay a queued update first.")
    }

    await preloadGate.open()

    let startedA = try await iteratorA.next()
    let startedB = try await iteratorB.next()
    #expect(startedA?.sequence == 2)
    #expect(startedB?.sequence == 2)
    if case .started(let eventA)? = startedA?.state {
        #expect(eventA == WorkerStartedEvent(id: "req-late", op: "list_voice_profiles"))
    } else {
        Issue.record("Expected subscriber A to receive a started update second.")
    }
    if case .started(let eventB)? = startedB?.state {
        #expect(eventB == WorkerStartedEvent(id: "req-late", op: "list_voice_profiles"))
    } else {
        Issue.record("Expected subscriber B to receive a started update second.")
    }

    let completedA = try await iteratorA.next()
    let completedB = try await iteratorB.next()
    #expect(completedA?.sequence == 3)
    #expect(completedB?.sequence == 3)
    if case .completed(let successA)? = completedA?.state {
        #expect(successA.id == "req-late")
    } else {
        Issue.record("Expected subscriber A to receive a completed update third.")
    }
    if case .completed(let successB)? = completedB?.state {
        #expect(successB.id == "req-late")
    } else {
        Issue.record("Expected subscriber B to receive a completed update third.")
    }

    #expect(try await iteratorA.next() == nil)
    #expect(try await iteratorB.next() == nil)

    var handleIterator = handle.events.makeAsyncIterator()
    let handleQueued = try await handleIterator.next()
    let handleStarted = try await handleIterator.next()
    let handleCompleted = try await handleIterator.next()
    if case .queued(let queued)? = handleQueued {
        #expect(queued == WorkerQueuedEvent(id: "req-late", reason: .waitingForResidentModel, queuePosition: 1))
    } else {
        Issue.record("Expected the original handle stream to retain the queued event history.")
    }
    if case .started(let started)? = handleStarted {
        #expect(started == WorkerStartedEvent(id: "req-late", op: "list_voice_profiles"))
    } else {
        Issue.record("Expected the original handle stream to retain the started event history.")
    }
    if case .completed(let success)? = handleCompleted {
        #expect(success.id == "req-late")
    } else {
        Issue.record("Expected the original handle stream to retain the completed event history.")
    }
    #expect(try await handleIterator.next() == nil)

    let completedSnapshot = await runtime.request(id: "req-late")
    #expect(completedSnapshot?.sequence == 3)
    if case .completed(let success)? = completedSnapshot?.state {
        #expect(success.id == "req-late")
    } else {
        Issue.record("Expected the retained request snapshot to stay completed after terminal success.")
    }
}

@Test func requestObservationReportsCancellationAsDataWhileHandleStreamStillThrows() async throws {
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

    _ = await runtime.voices.create(design: "bright-guide",
        from: "Hello there",
        vibe: .femme,
        voice: "Warm and bright"
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "started"
                && $0["op"] as? String == "create_voice_profile_from_description"
        }
    })

    let queuedHandle = await runtime.submit(.listProfiles(id: "req-cancelled"))
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-cancelled"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_active_request"
        }
    })

    let updates = await runtime.updates(for: "req-cancelled")
    var updatesIterator = updates.makeAsyncIterator()
    if case .queued(let queued)? = try await updatesIterator.next()?.state {
        #expect(queued == WorkerQueuedEvent(id: "req-cancelled", reason: .waitingForActiveRequest, queuePosition: 1))
    } else {
        Issue.record("Expected the reconnecting observer to replay the queued state first.")
    }

    let cancelID = await runtime.player.cancelRequest("req-cancelled").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == cancelID
                && $0["ok"] as? Bool == true
                && $0["cancelled_request_id"] as? String == "req-cancelled"
        }
    })

    let cancelledUpdate = try await updatesIterator.next()
    if case .cancelled(let failure)? = cancelledUpdate?.state {
        #expect(failure.id == "req-cancelled")
        #expect(failure.code == .requestCancelled)
    } else {
        Issue.record("Expected the reconnecting observer to receive cancellation as data.")
    }
    #expect(try await updatesIterator.next() == nil)

    let cancelledSnapshot = await runtime.request(id: "req-cancelled")
    if case .cancelled(let failure)? = cancelledSnapshot?.state {
        #expect(failure.code == .requestCancelled)
    } else {
        Issue.record("Expected the retained request snapshot to stay cancelled after terminal failure.")
    }

    var handleIterator = queuedHandle.events.makeAsyncIterator()
    do {
        while let _ = try await handleIterator.next() {}
        Issue.record("The original RequestHandle stream should still throw on cancellation for compatibility.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }

    await profileGate.open()
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

    let requestID = await runtime.generate.speech(
        text: "Hello there, galew.",
        with: "default-femme"
    ).id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == requestID
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

    let activeHandle = await runtime.generate.speech(text: "Hello there", with: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
                $0["id"] as? String == activeHandle.id
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

    await runtime.accept(line: #"{"id":"req-1","op":"list_voice_profiles"}"#)

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
        line: #"{"id":"req-1","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_voice_profile_from_description"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"delete_voice_profile","profile_name":"remove-me"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"generate_speech","text":"Hi there","profile_name":"default-femme"}"#)

    await profileGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-3"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_speech"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "delete_voice_profile"
        }
    })

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_voice_profile_from_description", "req-3:generate_speech", "req-2:delete_voice_profile"])
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
        line: #"{"id":"req-1","op":"create_voice_profile_from_description","profile_name":"brand-new","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "create_voice_profile_from_description"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"generate_speech","text":"Hi there","profile_name":"brand-new"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"list_voice_profiles"}"#)

    await profileGate.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "generate_speech"
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
                && $0["op"] as? String == "list_voice_profiles"
        }
    })

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_voice_profile_from_description", "req-2:generate_speech", "req-3:list_voice_profiles"])
}

private func rawTestAudioData(for samples: [Float]) -> Data {
    let bytes = samples.map(\.bitPattern).flatMap { value in
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
    return Data(bytes)
}
