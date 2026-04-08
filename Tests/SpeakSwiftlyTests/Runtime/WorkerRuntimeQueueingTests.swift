import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Queueing and Preload

@Test func requestsQueuedDuringPreloadEmitWaitingStatusThenProcess() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let playback = PlaybackSpy()
    let runtime = try await makeRuntime(
        output: output,
        playback: playback,
        residentModelLoader: { _ in
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

@Test func requestsThatStartImmediatelyDoNotEmitQueuedEvents() async throws {
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

    await runtime.accept(line: #"{"id":"req-1","op":"list_profiles"}"#)

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

@Test func runtimeUsesConfiguredSpeechBackendForResidentModelPreload() async throws {
    let output = OutputRecorder()
    let recorder = LoadedBackendRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .marvis,
        residentModelLoader: { backend in
            await recorder.record(backend)
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
    #expect(await recorder.backends == [.marvis])
}

@Test func resolvedSpeechBackendPrefersExplicitConfigurationOverPersistedValue() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let profileRoot = rootURL.appendingPathComponent("profiles", isDirectory: true)
    let dependencies = makeSpeechBackendResolutionDependencies()
    try SpeakSwiftly.Configuration(speechBackend: .qwen3).saveDefault(
        profileRootOverride: profileRoot.path
    )

    let resolved = WorkerRuntime.resolvedSpeechBackend(
        dependencies: dependencies,
        environment: [ "SPEAKSWIFTLY_PROFILE_ROOT": profileRoot.path ],
        configuration: SpeakSwiftly.Configuration(speechBackend: .marvis),
        explicitSpeechBackend: nil
    )

    #expect(resolved == .marvis)
}

@Test func resolvedSpeechBackendPrefersEnvironmentOverPersistedConfiguration() throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let profileRoot = rootURL.appendingPathComponent("profiles", isDirectory: true)
    let dependencies = makeSpeechBackendResolutionDependencies()
    try SpeakSwiftly.Configuration(speechBackend: .qwen3).saveDefault(
        profileRootOverride: profileRoot.path
    )

    let resolved = WorkerRuntime.resolvedSpeechBackend(
        dependencies: dependencies,
        environment: [
            "SPEAKSWIFTLY_PROFILE_ROOT": profileRoot.path,
            SpeakSwiftly.SpeechBackend.environmentVariable: SpeakSwiftly.SpeechBackend.marvis.rawValue,
        ],
        configuration: nil,
        explicitSpeechBackend: nil
    )

    #expect(resolved == .marvis)
}

@Test func residentModelPreloadFailureFailsQueuedRequests() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
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

@Test func typedRequestStreamFailsWhenQueuedRequestDiesDuringResidentModelPreloadFailure() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Resident model preload failed while loading test-resident. The local test intentionally forced this failure."
            )
        }
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
                queuePosition: 1
            )
        )
    )

    await preloadGate.open()

    do {
        while let _ = try await iterator.next() {}
        Issue.record("The typed request stream should have thrown when resident model preload failed.")
    } catch let error as WorkerError {
        #expect(error.code == .modelGenerationFailed)
    }
}

@Test func persistedTextProfilesReloadAcrossRuntimeConstruction() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let firstRuntime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )
    try await firstRuntime.normalizer.storeProfile(
        TextForSpeech.Profile(
            id: "logs",
            name: "Logs",
            replacements: [
                TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule")
            ]
        )
    )
    try await firstRuntime.normalizer.useProfile(
        TextForSpeech.Profile(
            id: "ops",
            name: "Ops",
            replacements: [
                TextForSpeech.Replacement("stdout", with: "standard output", id: "ops-rule")
            ]
        )
    )

    let secondRuntime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    #expect(await secondRuntime.normalizer.profile(named: "logs")?.replacements.map(\.id) == ["logs-rule"])
    #expect(await secondRuntime.normalizer.activeProfile().id == "ops")
    #expect(await secondRuntime.normalizer.activeProfile().replacements.map(\.id) == ["ops-rule"])
    #expect(await secondRuntime.normalizer.effectiveProfile(named: "logs").replacements.map(\.id) == ["logs-rule"])
}

@Test func textProfileEditingHelpersMutateAndPersistStoredProfiles() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    let created = try await runtime.normalizer.createProfile(id: "logs", named: "Logs")
    #expect(created.replacements.isEmpty)

    let added = try await runtime.normalizer.addReplacement(
        TextForSpeech.Replacement("stderr", with: "standard error", id: "stderr-rule"),
        toStoredProfileNamed: "logs"
    )
    #expect(added.replacements.map(\.id) == ["stderr-rule"])

    let replaced = try await runtime.normalizer.replaceReplacement(
        TextForSpeech.Replacement("stderr", with: "standard standard error", id: "stderr-rule"),
        inStoredProfileNamed: "logs"
    )
    #expect(replaced.replacements.first?.replacement == "standard standard error")

    let emptied = try await runtime.normalizer.removeReplacement(
        id: "stderr-rule",
        fromStoredProfileNamed: "logs"
    )
    #expect(emptied.replacements.isEmpty)

    let reloaded = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )
    #expect(await reloaded.normalizer.profile(named: "logs")?.replacements.isEmpty == true)
}

@Test func activeTextProfileEditingHelpersMutateAndPersistCustomProfile() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    let added = try await runtime.normalizer.addReplacement(
        TextForSpeech.Replacement("stdout", with: "standard output", id: "stdout-rule")
    )
    #expect(added.replacements.map(\.id) == ["stdout-rule"])

    let replaced = try await runtime.normalizer.replaceReplacement(
        TextForSpeech.Replacement("stdout", with: "standard out", id: "stdout-rule")
    )
    #expect(replaced.replacements.first?.replacement == "standard out")

    let emptied = try await runtime.normalizer.removeReplacement(id: "stdout-rule")
    #expect(emptied.replacements.isEmpty)

    let reloaded = try await makeRuntime(
        rootURL: rootURL,
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )
    #expect(await reloaded.normalizer.activeProfile().replacements.isEmpty)
}

@Test func textProfileProtocolOperationsMutateAndExposeNormalizerState() async throws {
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.accept(
        line: #"{"id":"req-create-text","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create-text"
                && $0["ok"] as? Bool == true
                && ($0["text_profile"] as? [String: Any])?["id"] as? String == "logs"
        }
    })

    await runtime.accept(
        line: #"{"id":"req-add-text","op":"create_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-add-text"
                && (($0["text_profile"] as? [String: Any])?["replacements"] as? [[String: Any]])?.count == 1
        }
    })

    let activeProfile = TextForSpeech.Profile(
        id: "ops",
        name: "Ops",
        replacements: [TextForSpeech.Replacement("stdout", with: "standard output", id: "ops-rule")]
    )
    let activeProfileJSON = try String(decoding: JSONEncoder().encode(activeProfile), as: UTF8.self)
    await runtime.accept(
        line: #"{"id":"req-use-text","op":"replace_active_text_profile","text_profile":"# + activeProfileJSON + #"}"#
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
        }
    })

    await runtime.accept(line: #"{"id":"req-text-list","op":"list_text_profiles"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-list"
                && (($0["text_profiles"] as? [[String: Any]])?.count ?? 0) >= 1
                && ($0["text_profile_path"] as? String)?.hasSuffix("text-profiles.json") == true
        }
    })

    await runtime.accept(line: #"{"id":"req-reset-text","op":"reset_text_profile"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-reset-text"
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "default"
        }
    })
}

@Test func textProfileProtocolOperationsRunDuringResidentWarmupWithoutQueueing() async throws {
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

@Test func waitingRequestsReportPriorityQueuePositions() async throws {
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
        line: #"{"id":"req-1","op":"create_profile","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "started"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"list_profiles"}"#)
    await runtime.accept(line: #"{"id":"req-3","op":"queue_speech_live","text":"Hi there","profile_name":"default-femme"}"#)

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
