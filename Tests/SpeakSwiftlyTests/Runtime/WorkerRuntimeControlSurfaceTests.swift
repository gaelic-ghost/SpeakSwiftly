import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

@Test func `list queue returns active and queued requests without waiting for active playback`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeHandle = await runtime.generate.speech(text: "Hello there", voiceProfile: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let queuedHandle = await runtime.generate.speech(text: "Hi there", voiceProfile: "default-femme")

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

@Test func `playback state stays consistent while live playback owns the active request`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeHandle = await runtime.generate.speech(text: "Hello there", voiceProfile: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    _ = await runtime.generate.speech(text: "Hi there", voiceProfile: "default-femme")
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

@Test func `runtime overview captures serialized marvis generation`() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
    let laneAGenerationDrain = AsyncGate()
    let laneBGenerationDrain = AsyncGate()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    @Sendable func makeLaneModel(_ gate: AsyncGate) -> AnySpeechModel {
        AnySpeechModel(
            sampleRate: 24000,
            generate: { _, _, _, _, _, _ in
                [0.1, 0.2]
            },
            generateSamplesStream: { _, _, _, _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(Array(repeating: 0.1, count: 24000))
                    continuation.yield(Array(repeating: 0.1, count: 24000))
                    continuation.yield(Array(repeating: 0.1, count: 24000))
                    Task {
                        await gate.wait()
                        continuation.finish()
                    }
                }
            },
        )
    }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "lane-a-primary",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )
    _ = try store.createProfile(
        profileName: "lane-b-secondary",
        vibe: .masc,
        modelRepo: "test-model",
        voiceDescription: "Grounded and rich.",
        sourceText: "Reference transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x03, 0x04]),
    )
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        speechBackend: .marvis,
        residentModelLoader: { _ in
            ResidentSpeechModels.marvis(
                .dual(
                    conversationalA: makeLaneModel(laneAGenerationDrain),
                    conversationalB: makeLaneModel(laneBGenerationDrain),
                ),
            )
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "marvis"
        }
    })

    let firstHandle = await runtime.generate.speech(text: "First request", voiceProfile: "lane-a-primary")
    let secondHandle = await runtime.generate.speech(text: "Second request", voiceProfile: "lane-b-secondary")

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
                && $0["event"] as? String == "queued"
                && (($0["reason"] as? String == "waiting_for_playback_stability")
                    || ($0["reason"] as? String == "waiting_for_active_request"))
        }
    })
    let overviewID = await runtime.overview().id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == overviewID,
                $0["ok"] as? Bool == true,
                let overview = $0["runtime_overview"] as? [String: Any],
                let storage = overview["storage"] as? [String: Any],
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
                && storage["state_root_path"] as? String == storeRoot.standardizedFileURL.path
                && storage["profile_store_root_path"] as? String == storeRoot.standardizedFileURL.path
                && storage["configuration_path"] as? String == storeRoot.appendingPathComponent("configuration.json").path
                && storage["text_profiles_path"] as? String == storeRoot.appendingPathComponent("text-profiles.json").path
                && storage["generated_files_root_path"] as? String == storeRoot.appendingPathComponent("generated-files").path
                && storage["generation_jobs_root_path"] as? String == storeRoot.appendingPathComponent("generation-jobs").path
                && activeIDs == Set([firstHandle.id])
                && queuedIDs == Set([secondHandle.id])
                && playbackState["state"] as? String == "playing"
                && (playbackState["is_stable_for_concurrent_generation"] as? Bool) != nil
                && (playbackState["is_rebuffering"] as? Bool) != nil
                && (playbackState["stable_buffered_audio_ms"] as? Int ?? 0) >= 0
                && (playbackState["stable_buffer_target_ms"] as? Int ?? 0) >= 0
                && playbackActiveRequest["id"] as? String == firstHandle.id
        }
    })

    await laneAGenerationDrain.open()
    await laneBGenerationDrain.open()
    await playbackDrain.open()
}

@Test func `status returns current resident backend and stage`() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { _ in makeResidentModel() },
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

@Test func `switch speech backend reloads resident models without restarting runtime`() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { _ in makeResidentModel() },
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

@Test func `switch speech backend can move from qwen to chatterbox turbo`() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "qwen3"
        }
    })

    let switchID = await runtime.switchSpeechBackend(to: .chatterboxTurbo).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == switchID,
                $0["ok"] as? Bool == true,
                $0["speech_backend"] as? String == "chatterbox_turbo",
                let status = $0["status"] as? [String: Any]
            else {
                return false
            }

            return status["stage"] as? String == "resident_model_ready"
                && status["speech_backend"] as? String == "chatterbox_turbo"
        }
    })
}

@Test func `unload and reload models park resident generation until residency returns`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3,
        residentModelLoader: { backend in
            await backendLoads.record(backend)
            return makeResidentModel()
        },
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

    let queuedFileID = await runtime.generate
        .audio(
            text: "Save this request once the resident models are back.",
            voiceProfile: "default-femme",
        )
        .id
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

@Test func `switch speech backend acts as an ordered barrier while playback drains`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        speechBackend: .qwen3,
        residentModelLoader: { backend in
            await backendLoads.record(backend)
            return makeResidentModel()
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeHandle = await runtime.generate.speech(text: "Hello there", voiceProfile: "default-femme")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeHandle.id
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let switchID = await runtime.switchSpeechBackend(to: .marvis).id
    let queuedFileID = await runtime.generate
        .audio(
            text: "Save this request after the backend switch barrier.",
            voiceProfile: "default-femme",
        )
        .id

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

@Test func `clear queue fails queued requests when generation queue has waiting work`() async throws {
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
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeCreateID = await runtime.voices
        .create(design: "bright-guide",
                from: "Hello there",
                vibe: .femme,
                voiceDescription: "Warm and bright")
        .id
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
                queuePosition: 1,
            ),
        ),
    )

    let clearID = await runtime.clearQueue(.generation).id

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

@Test func `playback clear does not clear waiting generation work`() async throws {
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
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeCreateID = await runtime.voices
        .create(design: "bright-guide",
                from: "Hello there",
                vibe: .femme,
                voiceDescription: "Warm and bright")
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeCreateID
                && $0["event"] as? String == "started"
        }
    })

    let queuedHandle = await runtime.submit(.listProfiles(id: "req-generation-queued"))
    var iterator = queuedHandle.events.makeAsyncIterator()
    let queued = try await iterator.next()
    #expect(
        queued == .queued(
            WorkerQueuedEvent(
                id: "req-generation-queued",
                reason: .waitingForActiveRequest,
                queuePosition: 1,
            ),
        ),
    )

    let playbackClearID = await runtime.clearQueue(.playback).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == playbackClearID
                && $0["ok"] as? Bool == true
                && $0["cleared_count"] as? Int == 0
        }
    })

    let generationClearID = await runtime.clearQueue(.generation).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == generationClearID
                && $0["ok"] as? Bool == true
                && $0["cleared_count"] as? Int == 1
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-generation-queued"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "request_cancelled"
        }
    })

    do {
        while let _ = try await iterator.next() {}
        Issue.record("The queued request stream should have thrown after generation clear removed it.")
    } catch let error as WorkerError {
        #expect(error.code == .requestCancelled)
    }

    await profileGate.open()
}

@Test func `cancel request can cancel active playback immediately`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
    )

    let activeHandle = await runtime.submit(
        .queueSpeech(
            id: "req-active",
            text: "Hello there",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            sourceFormat: nil,
            requestContext: nil,
            qwenPreModelTextChunking: false,
        ),
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
        if case let .progress(progress) = event, progress.stage == .prerollReady {
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

@Test func `cancel request can cancel queued work immediately`() async throws {
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
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeCreateID = await runtime.voices
        .create(design: "bright-guide",
                from: "Hello there",
                vibe: .femme,
                voiceDescription: "Warm and bright")
        .id
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
                queuePosition: 1,
            ),
        ),
    )

    let cancelID = await runtime.cancel(.generation, requestID: "req-queued").id

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

@Test func `waiting speak live runs before waiting profile management after active work finishes`() async throws {
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
        },
    )
    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01]),
    )
    _ = try store.createProfile(
        profileName: "remove-me",
        modelRepo: "test-model",
        voiceDescription: "Remove me.",
        sourceText: "Remove me.",
        sampleRate: 24000,
        canonicalAudioData: Data([0x02]),
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-1","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#,
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

@Test func `waiting speak live for queued profile creation does not jump ahead of that profile`() async throws {
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
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-1","op":"create_voice_profile_from_description","profile_name":"brand-new","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#,
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
