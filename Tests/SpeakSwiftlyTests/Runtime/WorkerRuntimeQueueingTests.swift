import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

// MARK: - Queueing and Preload

@Test func `requests queued during preload emit waiting status then process`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let playback = PlaybackSpy()
    let runtime = try await makeRuntime(
        output: output,
        playback: playback,
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        },
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-1","op":"list_voice_profiles"}"#)

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

@Test func `requests that start immediately do not emit queued events`() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
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
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-1"
            && $0["event"] as? String == "queued"
    })
}

@Test func `marvis live generation stays serialized across resident voices`() async throws {
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

    await runtime.accept(line: #"{"id":"req-live-1","op":"generate_speech","text":"Hello there","profile_name":"lane-a-primary"}"#)
    await runtime.accept(line: #"{"id":"req-live-2","op":"generate_speech","text":"Hi there","profile_name":"lane-b-secondary"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-2"
                && $0["event"] as? String == "queued"
                && (($0["reason"] as? String == "waiting_for_playback_stability")
                    || ($0["reason"] as? String == "waiting_for_active_request"))
        }
    })
    let generationQueueID = await (runtime.jobs.generationQueue()).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationQueueID,
                $0["ok"] as? Bool == true,
                let activeRequests = $0["active_requests"] as? [[String: Any]],
                let queuedRequests = $0["queue"] as? [[String: Any]]
            else {
                return false
            }

            let activeIDs = Set(activeRequests.compactMap { $0["id"] as? String })
            let queuedIDs = Set(queuedRequests.compactMap { $0["id"] as? String })
            return activeIDs == Set(["req-live-1"]) && queuedIDs == Set(["req-live-2"])
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-live-2"
            && $0["event"] as? String == "started"
    })
    #expect(output.containsStderrJSONObject {
        $0["request_id"] as? String == "req-live-1"
            && $0["event"] as? String == "marvis_generation_lane_reserved"
            && (($0["details"] as? [String: Any])?["marvis_lane"] as? String) == "conversational_a"
    })
    #expect(output.containsStderrJSONObject {
        $0["event"] as? String == "marvis_generation_scheduler_snapshot"
            && (($0["details"] as? [String: Any])?["active_generation_request_ids"] as? String) == "req-live-1"
    })

    await laneAGenerationDrain.open()
    await playbackDrain.open()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-2"
                && $0["event"] as? String == "started"
        }
    })
    #expect(output.containsStderrJSONObject {
        $0["request_id"] as? String == "req-live-2"
            && $0["event"] as? String == "marvis_generation_lane_reserved"
            && (($0["details"] as? [String: Any])?["marvis_lane"] as? String) == "conversational_b"
    })

    await laneBGenerationDrain.open()
}

@Test func `resident generation stays serialized while playback is already stable`() async throws {
    let output = OutputRecorder()
    let generationDrain = AsyncGate()
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
        speechBackend: .chatterboxTurbo,
        residentModelLoader: { _ in
            AnySpeechModel(
                sampleRate: 24000,
                generate: { _, _, _, _, _, _ in
                    [0.1, 0.2]
                },
                generateSamplesStream: { _, _, _, _, _, _, _ in
                    AsyncThrowingStream { continuation in
                        for _ in 0..<14 {
                            continuation.yield(Array(repeating: 0.1, count: 24000))
                        }
                        Task {
                            await generationDrain.wait()
                            continuation.finish()
                        }
                    }
                },
            )
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
                && $0["speech_backend"] as? String == "chatterbox_turbo"
        }
    })

    await runtime.accept(line: #"{"id":"req-live-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)
    await runtime.accept(line: #"{"id":"req-live-2","op":"generate_speech","text":"Hi there","profile_name":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-2"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_active_request"
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-live-2"
            && $0["event"] as? String == "started"
    })

    await generationDrain.open()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-2"
                && $0["event"] as? String == "started"
        }
    })
    await playbackDrain.open()
}

@Test func `preparing live speech blocks later resident control barriers`() async throws {
    let runtime = try await makeRuntime(
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    let preparingLiveJob = SpeechGenerationController.Job(
        request: .queueSpeech(
            id: "req-preparing-live",
            text: "Hello while playback state is still preparing.",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            inputTextContext: nil,
            requestContext: nil,
            qwenPreModelTextChunking: nil,
        ),
    )
    let reloadJob = SpeechGenerationController.Job(
        request: .reloadModels(id: "req-reload-models"),
    )

    let decision = try await runtime.evaluateGenerationSchedule(
        activeJobs: [],
        queuedJobs: [preparingLiveJob, reloadJob],
        preparingJobTokens: [preparingLiveJob.token],
        playbackAdmission: PlaybackController.GenerationAdmissionSnapshot(
            activeRequestID: nil,
            activeRequestTuningProfile: nil,
            allowsConcurrentGeneration: true,
        ),
    )

    #expect(decision.runnableJobs.isEmpty)
    #expect(decision.parkReasons == [preparingLiveJob.token: .waitingForActiveRequest])
}

@Test func `runtime uses configured speech backend for resident model preload`() async throws {
    let output = OutputRecorder()
    let recorder = LoadedBackendRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .marvis,
        residentModelLoader: { backend in
            await recorder.record(backend)
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
    #expect(await recorder.backends == [.marvis])
}

@Test func `resolved speech backend prefers explicit configuration over persisted value`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let profileRoot = rootURL.appendingPathComponent("profiles", isDirectory: true)
    let dependencies = makeSpeechBackendResolutionDependencies()
    try SpeakSwiftly.Configuration(speechBackend: .qwen3).saveDefault(
        profileRootOverride: profileRoot.path,
    )

    let resolved = WorkerRuntime.resolvedSpeechBackend(
        dependencies: dependencies,
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRoot.path],
        configuration: SpeakSwiftly.Configuration(speechBackend: .marvis),
    )

    #expect(resolved == .marvis)
}

@Test func `resolved speech backend prefers environment over persisted configuration`() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let profileRoot = rootURL.appendingPathComponent("profiles", isDirectory: true)
    let dependencies = makeSpeechBackendResolutionDependencies()
    try SpeakSwiftly.Configuration(speechBackend: .qwen3).saveDefault(
        profileRootOverride: profileRoot.path,
    )

    let resolved = WorkerRuntime.resolvedSpeechBackend(
        dependencies: dependencies,
        environment: [
            "SPEAKSWIFTLY_PROFILE_ROOT": profileRoot.path,
            SpeakSwiftly.SpeechBackend.environmentVariable: SpeakSwiftly.SpeechBackend.marvis.rawValue,
        ],
        configuration: nil,
    )

    #expect(resolved == .marvis)
}

@Test func `resolved qwen resident model prefers explicit configuration over environment`() {
    let resolved = WorkerRuntime.resolvedQwenResidentModel(
        environment: [
            SpeakSwiftly.QwenResidentModel.environmentVariable: SpeakSwiftly.QwenResidentModel.base17B8Bit.rawValue,
        ],
        configuration: SpeakSwiftly.Configuration(qwenResidentModel: .base06B8Bit),
    )

    #expect(resolved == .base06B8Bit)
}

@Test func `resolved qwen resident model falls back to environment`() {
    let resolved = WorkerRuntime.resolvedQwenResidentModel(
        environment: [
            SpeakSwiftly.QwenResidentModel.environmentVariable: SpeakSwiftly.QwenResidentModel.base17B8Bit.rawValue,
        ],
        configuration: nil,
    )

    #expect(resolved == .base17B8Bit)
}

@Test func `resident model preload failure fails queued requests`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Resident model preload failed while loading test-resident. The local test intentionally forced this failure.",
            )
        },
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-1","op":"list_voice_profiles"}"#)
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

@Test func `typed request stream fails when queued request dies during resident model preload failure`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Resident model preload failed while loading test-resident. The local test intentionally forced this failure.",
            )
        },
    )

    let handle = await runtime.submit(.listProfiles(id: "req-preload-stream-fail"))
    var iterator = handle.events.makeAsyncIterator()

    await runtime.start()

    let queued = try await iterator.next()
    #expect(
        queued == .queued(
            WorkerQueuedEvent(
                id: "req-preload-stream-fail",
                reason: .waitingForResidentModel,
                queuePosition: 1,
            ),
        ),
    )

    await preloadGate.open()

    do {
        while let _ = try await iterator.next() {}
        Issue.record("The typed request stream should have thrown when resident model preload failed.")
    } catch let error as WorkerError {
        #expect(error.code == .modelGenerationFailed)
    }
}

@Test func `persisted text profiles reload across runtime construction`() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let firstRuntime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    let logs = try await firstRuntime.normalizer.profiles.create(name: "Logs")
    _ = try await firstRuntime.normalizer.profiles.addReplacement(
        TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule"),
        toProfile: logs.id,
    )
    let ops = try await firstRuntime.normalizer.profiles.create(name: "Ops")
    _ = try await firstRuntime.normalizer.profiles.addReplacement(
        TextForSpeech.Replacement("stdout", with: "standard output", id: "ops-rule"),
        toProfile: ops.id,
    )
    try await firstRuntime.normalizer.profiles.setActive(id: ops.id)

    let secondRuntime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    let storedLogs = try await secondRuntime.normalizer.profiles.get(id: logs.id)
    let activeProfile = await secondRuntime.normalizer.profiles.getActive()
    let effectiveProfile = await secondRuntime.normalizer.profiles.getEffective()

    #expect(storedLogs.replacements.map(\.id) == ["logs-rule"])
    #expect(activeProfile.id == ops.id)
    #expect(activeProfile.replacements.map(\.id) == ["ops-rule"])
    #expect(effectiveProfile.replacements.map(\.id).contains("ops-rule"))
    #expect(effectiveProfile.replacements.map(\.id).contains("base-url"))
}

@Test func `text profile editing helpers mutate and persist stored profiles`() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    let created = try await runtime.normalizer.profiles.create(name: "Logs")
    #expect(created.replacements.isEmpty)

    let added = try await runtime.normalizer.profiles.addReplacement(
        TextForSpeech.Replacement("stderr", with: "standard error", id: "stderr-rule"),
        toProfile: created.id,
    )
    #expect(added.replacements.map(\.id) == ["stderr-rule"])

    let replaced = try await runtime.normalizer.profiles.patchReplacement(
        TextForSpeech.Replacement("stderr", with: "standard standard error", id: "stderr-rule"),
        inProfile: created.id,
    )
    #expect(replaced.replacements.first?.replacement == "standard standard error")
    #expect(try await runtime.normalizer.profiles.get(id: created.id).replacements.map(\.id) == ["stderr-rule"])

    let emptied = try await runtime.normalizer.profiles.removeReplacement(
        id: "stderr-rule",
        fromProfile: created.id,
    )
    #expect(emptied.replacements.isEmpty)

    let reloaded = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    #expect(try await reloaded.normalizer.profiles.get(id: created.id).replacements.isEmpty == true)
}

@Test func `active text profile editing helpers mutate and persist custom profile`() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    let added = try await runtime.normalizer.profiles.addReplacement(
        TextForSpeech.Replacement("stdout", with: "standard output", id: "stdout-rule"),
    )
    #expect(added.replacements.map(\.id) == ["stdout-rule"])

    let replaced = try await runtime.normalizer.profiles.patchReplacement(
        TextForSpeech.Replacement("stdout", with: "standard out", id: "stdout-rule"),
    )
    #expect(replaced.replacements.first?.replacement == "standard out")
    #expect(await (runtime.normalizer.profiles.getActive()).replacements.map(\.id) == ["stdout-rule"])

    let emptied = try await runtime.normalizer.profiles.removeReplacement(id: "stdout-rule")
    #expect(emptied.replacements.isEmpty)

    let reloaded = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    #expect(await (reloaded.normalizer.profiles.getActive()).replacements.isEmpty == true)
}

@Test func `text profile protocol operations mutate and expose normalizer state`() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.accept(
        line: #"{"id":"req-create-text","op":"create_text_profile","profile_name":"Logs"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create-text"
                && $0["ok"] as? Bool == true
                && ($0["text_profile"] as? [String: Any])?["profile_id"] as? String == "logs"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-add-text","op":"create_text_replacement","text_profile_id":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"textFormats":[],"sourceFormats":[],"priority":0}}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-add-text"
                && (($0["text_profile"] as? [String: Any])?["replacements"] as? [[String: Any]])?.count == 1
        }
    })

    await runtime.accept(line: #"{"id":"req-text-one","op":"get_text_profile","text_profile_id":"logs"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-one"
                && (($0["text_profile"] as? [String: Any])?["profile_id"] as? String) == "logs"
                && ((($0["text_profile"] as? [String: Any])?["replacements"] as? [[String: Any]])?.count ?? 0) == 1
        }
    })

    await runtime.accept(
        line: #"{"id":"req-create-ops","op":"create_text_profile","profile_name":"Ops"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create-ops"
                && ($0["ok"] as? Bool == true)
                && (($0["text_profile"] as? [String: Any])?["profile_id"] as? String) == "ops"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-set-active","op":"set_active_text_profile","text_profile_id":"ops"}"#,
    )
    await runtime.accept(line: #"{"id":"req-text-active","op":"get_active_text_profile"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-active"
                && (($0["text_profile"] as? [String: Any])?["profile_id"] as? String) == "ops"
                && ($0["text_profile_style"] as? String) == "balanced"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-text-style","op":"set_active_text_profile_style","text_profile_style":"explicit"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-style"
                && ($0["text_profile_style"] as? String) == "explicit"
        }
    })

    await runtime.accept(line: #"{"id":"req-text-styles","op":"list_text_profile_styles"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-styles"
                && $0["ok"] as? Bool == true
                && ($0["text_profile_style"] as? String) == "explicit"
        }
    })

    await runtime.accept(line: #"{"id":"req-text-list","op":"list_text_profiles"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-list"
                && (($0["text_profiles"] as? [[String: Any]])?.count ?? 0) >= 1
                && ($0["text_profile_style"] as? String) == "explicit"
                && ($0["text_profile_path"] as? String)?.hasSuffix("text-profiles.json") == true
        }
    })

    await runtime.accept(line: #"{"id":"req-reset-text","op":"reset_text_profile","text_profile_id":"ops"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-reset-text"
                && (($0["text_profile"] as? [String: Any])?["profile_id"] as? String) == "ops"
                && (((($0["text_profile"] as? [String: Any])?["replacements"] as? [[String: Any]])?.isEmpty) == true)
                && ($0["text_profile_style"] as? String) == "explicit"
        }
    })

    await runtime.accept(line: #"{"id":"req-delete-text","op":"delete_text_profile","text_profile_id":"logs"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-delete-text"
                && $0["ok"] as? Bool == true
        }
    })

    await runtime.accept(line: #"{"id":"req-factory-reset","op":"factory_reset_text_profiles"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-factory-reset"
                && (($0["text_profile"] as? [String: Any])?["profile_id"] as? String) == "default"
        }
    })
}

@Test func `text profile protocol operations run during resident warmup without queueing`() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        },
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-text-list","op":"list_text_profiles"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-list"
                && $0["event"] as? String == "started"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-list"
                && $0["ok"] as? Bool == true
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-text-list"
            && $0["event"] as? String == "queued"
    })

    await preloadGate.open()
}

@Test func `waiting requests report priority queue positions`() async throws {
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
        line: #"{"id":"req-1","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"list_voice_profiles"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"generate_speech","text":"Hi there","profile_name":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_active_request"
                && $0["queue_position"] as? Int == 1
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-3"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_active_request"
                && $0["queue_position"] as? Int == 1
        }
    })

    await profileGate.open()
}
