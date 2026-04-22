import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

@Test func `request observation returns nil and finished stream for unknown request ID`() async throws {
    let runtime = try await makeRuntime(
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()

    #expect(await runtime.request(id: "missing-request") == nil)

    let updates = await runtime.updates(for: "missing-request")
    var iterator = updates.makeAsyncIterator()
    let first = try await iterator.next()
    #expect(first == nil)
}

@Test func `request observation exposes replayable generation events for qwen requests`() async throws {
    let output = OutputRecorder()
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
        qwenConditioningStrategy: .preparedConditioning,
        residentModelLoader: { _ in makeResidentModel(chunkCount: 2) },
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
        with: "default-femme",
    )

    let runtimeEvents = await runtime.generationEvents(for: handle.id)
    var runtimeIterator = runtimeEvents.makeAsyncIterator()

    if case let .token(token)? = try await runtimeIterator.next()?.event {
        #expect(token == 202)
    } else {
        Issue.record("Expected the first replayed generation event to be a qwen token.")
    }

    if case let .info(info)? = try await runtimeIterator.next()?.event {
        #expect(info.promptTokenCount == 8)
        #expect(info.generationTokenCount == 8)
        #expect(info.prefillTime == 0.08)
        #expect(info.generateTime == 0.21)
        #expect(info.tokensPerSecond == 73.2)
        #expect(info.peakMemoryUsage == 0.92)
    } else {
        Issue.record("Expected the second replayed generation event to carry qwen generation info.")
    }

    if case let .audioChunk(sampleCount)? = try await runtimeIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the third replayed generation event to describe the first audio chunk.")
    }

    if case let .audioChunk(sampleCount)? = try await runtimeIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the fourth replayed generation event to describe the second audio chunk.")
    }

    #expect(try await runtimeIterator.next() == nil)

    var handleIterator = handle.generationEvents.makeAsyncIterator()
    if case let .token(token)? = try await handleIterator.next()?.event {
        #expect(token == 202)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the qwen token event.")
    }
    if case let .info(info)? = try await handleIterator.next()?.event {
        #expect(info.promptTokenCount == 8)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the qwen info event.")
    }
    if case let .audioChunk(sampleCount)? = try await handleIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the first audio chunk event.")
    }
    if case let .audioChunk(sampleCount)? = try await handleIterator.next()?.event {
        #expect(sampleCount == 2)
    } else {
        Issue.record("Expected the original RequestHandle generation stream to retain the second audio chunk event.")
    }
    #expect(try await handleIterator.next() == nil)
}

@Test func `request observation replays queued state and fans out to multiple subscribers`() async throws {
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
            case let .queued(queued):
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
    if case let .queued(queuedA)? = replayA?.state {
        #expect(queuedA.reason == .waitingForResidentModel)
    } else {
        Issue.record("Expected subscriber A to replay a queued update first.")
    }
    if case let .queued(queuedB)? = replayB?.state {
        #expect(queuedB.reason == .waitingForResidentModel)
    } else {
        Issue.record("Expected subscriber B to replay a queued update first.")
    }

    await preloadGate.open()

    let startedA = try await iteratorA.next()
    let startedB = try await iteratorB.next()
    #expect(startedA?.sequence == 2)
    #expect(startedB?.sequence == 2)
    if case let .started(eventA)? = startedA?.state {
        #expect(eventA == WorkerStartedEvent(id: "req-late", op: "list_voice_profiles"))
    } else {
        Issue.record("Expected subscriber A to receive a started update second.")
    }
    if case let .started(eventB)? = startedB?.state {
        #expect(eventB == WorkerStartedEvent(id: "req-late", op: "list_voice_profiles"))
    } else {
        Issue.record("Expected subscriber B to receive a started update second.")
    }

    let completedA = try await iteratorA.next()
    let completedB = try await iteratorB.next()
    #expect(completedA?.sequence == 3)
    #expect(completedB?.sequence == 3)
    if case let .completed(successA)? = completedA?.state {
        #expect(successA.id == "req-late")
    } else {
        Issue.record("Expected subscriber A to receive a completed update third.")
    }
    if case let .completed(successB)? = completedB?.state {
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
    if case let .queued(queued)? = handleQueued {
        #expect(queued == WorkerQueuedEvent(id: "req-late", reason: .waitingForResidentModel, queuePosition: 1))
    } else {
        Issue.record("Expected the original handle stream to retain the queued event history.")
    }
    if case let .started(started)? = handleStarted {
        #expect(started == WorkerStartedEvent(id: "req-late", op: "list_voice_profiles"))
    } else {
        Issue.record("Expected the original handle stream to retain the started event history.")
    }
    if case let .completed(success)? = handleCompleted {
        #expect(success.id == "req-late")
    } else {
        Issue.record("Expected the original handle stream to retain the completed event history.")
    }
    #expect(try await handleIterator.next() == nil)

    let completedSnapshot = await runtime.request(id: "req-late")
    #expect(completedSnapshot?.sequence == 3)
    if case let .completed(success)? = completedSnapshot?.state {
        #expect(success.id == "req-late")
    } else {
        Issue.record("Expected the retained request snapshot to stay completed after terminal success.")
    }
}

@Test func `request observation reports cancellation as data while handle stream still throws`() async throws {
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

    _ = await runtime.voices.create(design: "bright-guide",
                                    from: "Hello there",
                                    vibe: .femme,
                                    voice: "Warm and bright")
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
    if case let .queued(queued)? = try await updatesIterator.next()?.state {
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
    if case let .cancelled(failure)? = cancelledUpdate?.state {
        #expect(failure.id == "req-cancelled")
        #expect(failure.code == .requestCancelled)
    } else {
        Issue.record("Expected the reconnecting observer to receive cancellation as data.")
    }
    #expect(try await updatesIterator.next() == nil)

    let cancelledSnapshot = await runtime.request(id: "req-cancelled")
    if case let .cancelled(failure)? = cancelledSnapshot?.state {
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

@Test func `speak live uses stable resident generation parameters`() async throws {
    let output = OutputRecorder()
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

    let recorder = ResidentModelRecorder()
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel(recorder: recorder) },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let requestID = await runtime.generate
        .speech(
            text: "Hello there, galew.",
            with: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == requestID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    #expect(recorder.lastText == "Hello there, gale wumbo.")
    #expect(recorder.lastGenerationParameters?.maxTokens == 4096)
    #expect(recorder.lastGenerationParameters?.temperature == 0.9)
    #expect(recorder.lastGenerationParameters?.topP == 1.0)
    #expect(recorder.lastGenerationParameters?.repetitionPenalty == 1.05)
}

@Test func `late status subscribers receive current ready snapshot`() async throws {
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

    let statuses = await runtime.statusEvents()
    var iterator = statuses.makeAsyncIterator()

    #expect(await iterator.next() == WorkerStatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3))
}

@Test func `dropping status subscription does not retain runtime`() async throws {
    let output = OutputRecorder()
    let weakRuntime = WeakRuntimeBox()

    var runtime: WorkerRuntime? = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { _ in makeResidentModel() },
    )
    weakRuntime.value = runtime

    var statuses: AsyncStream<SpeakSwiftly.StatusEvent>? = await runtime?.statusEvents()
    _ = statuses?.makeAsyncIterator()

    statuses = nil
    runtime = nil

    #expect(await waitUntil { weakRuntime.value == nil })
}

@Test func `start is idempotent for library consumers`() async throws {
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
        },
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
        } == 1,
    )
    #expect(
        output.countJSONObjects {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        } == 1,
    )
}

@Test func `typed request stream keeps background acknowledgement and later completion separate`() async throws {
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
            textProfileID: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: nil,
        ),
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

@Test func `list profiles skips corrupt entries and still returns healthy profiles`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "healthy",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Healthy transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01]),
    )

    let brokenDirectory = store.profileDirectoryURL(for: "broken")
    try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: false)
    try Data("not-json".utf8).write(to: store.manifestURL(for: brokenDirectory))

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
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
