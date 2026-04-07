import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

private actor LoadedBackendRecorder {
    private(set) var backends = [SpeakSwiftly.SpeechBackend]()

    func record(_ backend: SpeakSwiftly.SpeechBackend) {
        backends.append(backend)
    }
}

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
        line: #"{"id":"req-add-text","op":"add_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}"#
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
        line: #"{"id":"req-use-text","op":"use_text_profile","text_profile":"# + activeProfileJSON + #"}"#
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-use-text"
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "ops"
        }
    })

    await runtime.accept(line: #"{"id":"req-text-active","op":"text_profile_active"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-text-active"
                && (($0["text_profile"] as? [String: Any])?["id"] as? String) == "ops"
        }
    })

    await runtime.accept(line: #"{"id":"req-text-list","op":"text_profiles"}"#)
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
    await runtime.accept(line: #"{"id":"req-text-list","op":"text_profiles"}"#)

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
        line: #"{"id":"req-1","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"Warm and bright"}"#
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

// MARK: - Generated File Queueing

@Test func speakFileAcknowledgesQueueThenCompletesWithGeneratedFileMetadata() async throws {
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

    let requestID = await runtime.speak(
        text: "Hello from the generated file path.",
        with: "default-femme",
        as: .file,
        id: "req-file-1"
    ).id
    #expect(requestID == "req-file-1")

    #expect(await waitUntil {
        output.countJSONObjects {
            $0["id"] as? String == "req-file-1"
                && $0["ok"] as? Bool == true
        } == 2
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-file-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_file"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-file-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "writing_generated_file"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-file-1",
                let generatedFile = $0["generated_file"] as? [String: Any],
                generatedFile["artifact_id"] as? String == "req-file-1",
                generatedFile["profile_name"] as? String == "default-femme",
                let filePath = generatedFile["file_path"] as? String
            else {
                return false
            }

            return FileManager.default.fileExists(atPath: filePath)
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-file-1"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "playback_finished"
    })
}

@Test func generatedFileReadOperationsRunDuringResidentWarmupWithoutQueueing() async throws {
    let output = OutputRecorder()
    let preloadGate = AsyncGate()
    let rootURL = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let generatedFileStore = try makeGeneratedFileStore(rootURL: rootURL)
    _ = try generatedFileStore.createGeneratedFile(
        artifactID: "req-file-lookup",
        profileName: "default-femme",
        textProfileName: nil,
        sampleRate: 24_000,
        audioData: Data([0x01, 0x02, 0x03])
    )

    let runtime = try await makeRuntime(
        rootURL: rootURL,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in
            await preloadGate.wait()
            return makeResidentModel()
        }
    )

    await runtime.start()
    await runtime.accept(line: #"{"id":"req-generated-file","op":"generated_file","artifact_id":"req-file-lookup"}"#)
    await runtime.accept(line: #"{"id":"req-generated-files","op":"generated_files"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-generated-file"
                && $0["event"] as? String == "started"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generated-file",
                let generatedFile = $0["generated_file"] as? [String: Any]
            else {
                return false
            }

            return generatedFile["artifact_id"] as? String == "req-file-lookup"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            guard
                $0["id"] as? String == "req-generated-files",
                let generatedFiles = $0["generated_files"] as? [[String: Any]]
            else {
                return false
            }

            return generatedFiles.count == 1
                && generatedFiles.first?["artifact_id"] as? String == "req-file-lookup"
        }
    })
    #expect(!output.containsJSONObject {
        ($0["id"] as? String == "req-generated-file" || $0["id"] as? String == "req-generated-files")
            && $0["event"] as? String == "queued"
    })

    await preloadGate.open()
}

// MARK: - Live Playback Queueing

@Test func speakLiveBackgroundAcknowledgesQueueBeforePlaybackStartsAndOnlySucceedsOnce() async throws {
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

    let activeID = await runtime.speak(
        text: "Hello there",
        with: "default-femme",
        as: .live,
        id: "req-1"
    ).id
    #expect(activeID == "req-1")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let backgroundID = await runtime.speak(
        text: "Hi there",
        with: "default-femme",
        as: .live,
        id: "req-2"
    ).id
    #expect(backgroundID == "req-2")

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
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-2"
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "playback_finished"
    })

    await playbackDrain.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        }
    })
    #expect(output.countJSONObjects {
        $0["id"] as? String == "req-2"
            && $0["ok"] as? Bool == true
    } == 1)
}

@Test func speakLiveBackgroundCanFailAfterEnqueueAcknowledgement() async throws {
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
        playback: PlaybackSpy(
            behavior: .throw(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Background playback failed in the test playback controller after the request had already been accepted."
                )
            )
        ),
        residentModelLoader: { _ in makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.speak(
        text: "Hello there",
        with: "default-femme",
        as: .live,
        id: "req-fail"
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-fail"
                && $0["ok"] as? Bool == true
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-fail"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "audio_playback_failed"
        }
    })
    #expect(output.countJSONObjects {
        $0["id"] as? String == "req-fail"
            && $0["ok"] as? Bool == true
    } == 1)
}

// MARK: - Control Operations and Typed Surface

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
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-queued-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_live"
        }
    })

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

            return generatedFile["artifact_id"] as? String == "req-file-helper"
        }
    })

    let generatedFileID = await runtime.generatedFile(id: "req-file-helper", requestID: "req-file-read").id
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

            return generatedFile["artifact_id"] as? String == "req-file-helper"
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
                $0["artifact_id"] as? String == "req-file-helper"
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
    #expect(firstStatus == WorkerStatusEvent(stage: .warmingResidentModel))
    #expect(secondStatus == WorkerStatusEvent(stage: .residentModelReady))

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

    #expect(await iterator.next() == WorkerStatusEvent(stage: .residentModelReady))
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

    #expect(firstStatus == WorkerStatusEvent(stage: .warmingResidentModel))
    #expect(secondStatus == WorkerStatusEvent(stage: .residentModelReady))
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
    let started = try await iterator.next()

    #expect(acknowledged == .acknowledged(WorkerSuccessResponse(id: "req-stream-bg")))
    #expect(started == .started(WorkerStartedEvent(id: "req-stream-bg", op: "queue_speech_live")))

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

@Test func corruptListProfilesManifestBecomesFilesystemFailureResponse() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
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
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "filesystem_error"
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
                && $0["op"] as? String == "remove_profile"
        }
    })

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_profile", "req-3:queue_speech_live", "req-2:remove_profile"])
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
        line: #"{"id":"req-1","op":"create_profile","profile_name":"brand-new","text":"Hello there","voice_description":"Warm and bright"}"#
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
    let playbackDrain = AsyncGate()
    let profileGate = AsyncGate()
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
            voiceDescription: "Warm and bright",
            outputPath: nil
        )
    )
    var queuedIterator = queuedHandle.events.makeAsyncIterator()

    let queuedEvent = try await queuedIterator.next()
    #expect(queuedEvent == .started(WorkerStartedEvent(id: "req-queued-shutdown-stream", op: "create_profile")))

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

    await profileGate.open()
    await playbackDrain.open()
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
        line: #"{"id":"req-1","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"Warm and bright"}"#
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
