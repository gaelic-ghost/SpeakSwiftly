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

@Test func `marvis queued live generation resumes across resident lanes after playback becomes stable`() async throws {
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
    _ = try store.createProfile(
        profileName: "lane-a-tertiary",
        vibe: .androgenous,
        modelRepo: "test-model",
        voiceDescription: "Balanced and clear.",
        sourceText: "Reference transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x05, 0x06]),
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
    await runtime.accept(line: #"{"id":"req-live-3","op":"generate_speech","text":"Hey there","profile_name":"lane-a-tertiary"}"#)

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
                && $0["event"] as? String == "started"
        }
    })
    let req1PrerollReadyIndex = output.firstStdoutJSONObjectIndex {
        $0["id"] as? String == "req-live-1"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "preroll_ready"
    }
    let req2StartedIndex = output.firstStdoutJSONObjectIndex {
        $0["id"] as? String == "req-live-2"
            && $0["event"] as? String == "started"
    }
    #expect(req1PrerollReadyIndex != nil)
    #expect(req2StartedIndex != nil)
    if let req1PrerollReadyIndex, let req2StartedIndex {
        #expect(req1PrerollReadyIndex < req2StartedIndex)
    }
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-3"
                && $0["event"] as? String == "queued"
                && $0["reason"] as? String == "waiting_for_marvis_generation_lane"
        }
    })
    let generationQueueID = await (runtime.jobs.generationQueue()).id
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == generationQueueID,
                $0["ok"] as? Bool == true,
                let activeRequests = $0["active_requests"] as? [[String: Any]]
            else {
                return false
            }

            let activeIDs = Set(activeRequests.compactMap { $0["id"] as? String })
            return activeIDs == Set(["req-live-1", "req-live-2"])
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-live-2"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "playback_finished"
    })
    #expect(output.containsStderrJSONObject {
        $0["request_id"] as? String == "req-live-2"
            && $0["event"] as? String == "marvis_generation_lane_reserved"
            && (($0["details"] as? [String: Any])?["marvis_lane"] as? String) == "conversational_b"
    })
    #expect(output.containsStderrJSONObject {
        $0["event"] as? String == "marvis_generation_scheduler_snapshot"
            && (($0["details"] as? [String: Any])?["playback_is_stable_for_concurrency"] as? Bool) == true
    })

    await laneAGenerationDrain.open()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-live-3"
                && $0["event"] as? String == "started"
        }
    })

    await laneBGenerationDrain.open()
    await playbackDrain.open()
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
    try await firstRuntime.normalizer.profiles.store(
        TextForSpeech.Profile(
            id: "logs",
            name: "Logs",
            replacements: [
                TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule"),
            ],
        ),
    )
    try await firstRuntime.normalizer.profiles.use(
        TextForSpeech.Profile(
            id: "ops",
            name: "Ops",
            replacements: [
                TextForSpeech.Replacement("stdout", with: "standard output", id: "ops-rule"),
            ],
        ),
    )

    let secondRuntime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    #expect(await secondRuntime.normalizer.profiles.stored(id: "logs")?.replacements.map(\.id) == ["logs-rule"])
    #expect(await secondRuntime.normalizer.profiles.active()?.id == "ops")
    #expect(await secondRuntime.normalizer.profiles.active()?.replacements.map(\.id) == ["ops-rule"])
    let effectiveLogsReplacementIDs = await secondRuntime.normalizer.profiles.effective(id: "logs")?.replacements.map(\.id) ?? []
    #expect(effectiveLogsReplacementIDs.contains("logs-rule"))
    #expect(effectiveLogsReplacementIDs.contains("base-url"))
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

    let created = try await runtime.normalizer.profiles.create(id: "logs", name: "Logs")
    #expect(created.replacements.isEmpty)

    let added = try await runtime.normalizer.profiles.add(
        TextForSpeech.Replacement("stderr", with: "standard error", id: "stderr-rule"),
        toStoredProfileID: "logs",
    )
    #expect(added.replacements.map(\.id) == ["stderr-rule"])

    let replaced = try await runtime.normalizer.profiles.replace(
        TextForSpeech.Replacement("stderr", with: "standard standard error", id: "stderr-rule"),
        inStoredProfileID: "logs",
    )
    #expect(replaced.replacements.first?.replacement == "standard standard error")
    #expect(await runtime.normalizer.profiles.replacements(inStoredProfileID: "logs")?.map(\.id) == ["stderr-rule"])

    let emptied = try await runtime.normalizer.profiles.clearReplacements(
        fromStoredProfileID: "logs",
    )
    #expect(emptied.replacements.isEmpty)

    let reloaded = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    #expect(await reloaded.normalizer.profiles.stored(id: "logs")?.replacements.isEmpty == true)
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

    let added = try await runtime.normalizer.profiles.add(
        TextForSpeech.Replacement("stdout", with: "standard output", id: "stdout-rule"),
    )
    #expect(added.replacements.map(\.id) == ["stdout-rule"])

    let replaced = try await runtime.normalizer.profiles.replace(
        TextForSpeech.Replacement("stdout", with: "standard out", id: "stdout-rule"),
    )
    #expect(replaced.replacements.first?.replacement == "standard out")
    #expect(await runtime.normalizer.profiles.replacements().map(\.id) == ["stdout-rule"])

    let emptied = try await runtime.normalizer.profiles.clearReplacements()
    #expect(emptied.replacements.isEmpty)

    let reloaded = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    #expect(await reloaded.normalizer.profiles.active()?.replacements.isEmpty == true)
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
        line: #"{"id":"req-create-text","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create-text"
                && $0["ok"] as? Bool == true
                && ($0["text_profile"] as? [String: Any])?["id"] as? String == "logs"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-add-text","op":"create_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"textFormats":[],"sourceFormats":[],"priority":0}}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-add-text"
                && (($0["text_profile"] as? [String: Any])?["replacements"] as? [[String: Any]])?.count == 1
        }
    })

    await runtime.accept(line: #"{"id":"req-list-replacements","op":"list_text_replacements","text_profile_name":"logs"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-list-replacements"
                && (($0["replacements"] as? [[String: Any]])?.count ?? 0) == 1
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "logs"
        }
    })

    let activeProfile = TextForSpeech.Profile(
        id: "ops",
        name: "Ops",
        replacements: [TextForSpeech.Replacement("stdout", with: "standard output", id: "ops-rule")],
    )
    let activeProfileJSON = try String(decoding: JSONEncoder().encode(activeProfile), as: UTF8.self)
    await runtime.accept(
        line: #"{"id":"req-use-text","op":"replace_active_text_profile","text_profile":"# + activeProfileJSON + #"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-use-text"
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "ops"
        }
    })

    await runtime.accept(line: #"{"id":"req-text-active","op":"get_active_text_profile"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-active"
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "ops"
                && ($0["text_profile_style"] as? String) == "balanced"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-text-style","op":"set_text_profile_style","text_profile_style":"explicit"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-style"
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

    await runtime.accept(line: #"{"id":"req-reset-text","op":"reset_text_profile"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-reset-text"
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "default"
                && ($0["text_profile_style"] as? String) == "explicit"
        }
    })

    await runtime.accept(line: #"{"id":"req-clear-replacements","op":"clear_text_replacements"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-clear-replacements"
                && (($0["text_profile"] as? [String: Any])?["replacements"] as? [[String: Any]])?.isEmpty == true
                && (($0["replacements"] as? [[String: Any]])?.isEmpty) == true
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
