import Foundation
import Testing
@testable import SpeakSwiftlyCore

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

@Test func requestsThatStartImmediatelyDoNotEmitQueuedEvents() async throws {
    let output = OutputRecorder()
    let runtime = try await makeRuntime(
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { makeResidentModel() }
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

@Test func typedRequestStreamFailsWhenQueuedRequestDiesDuringResidentModelPreloadFailure() async throws {
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

@Test func waitingRequestsReportPriorityQueuePositions() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let profileGate = AsyncGate()
    let runtime = try await makeRuntime(
        output: output,
        playback: playback,
        residentModelLoader: { makeResidentModel() },
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
        residentModelLoader: { makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeID = await runtime.queueSpeech(
        text: "Hello there",
        profileName: "default-femme",
        as: .live,
        id: "req-1"
    )
    #expect(activeID == "req-1")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let backgroundID = await runtime.queueSpeech(
        text: "Hi there",
        profileName: "default-femme",
        as: .live,
        id: "req-2"
    )
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
        residentModelLoader: { makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.queueSpeech(
        text: "Hello there",
        profileName: "default-femme",
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
        residentModelLoader: { makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.queueSpeech(text: "Hello there", profileName: "default-femme", as: .live, id: "req-active")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-active"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    _ = await runtime.queueSpeech(text: "Hi there", profileName: "default-femme", as: .live, id: "req-queued-1")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-queued-1"
                && $0["event"] as? String == "started"
                && $0["op"] as? String == "queue_speech_live"
        }
    })

    let listID = await runtime.listQueue(.playback, id: "req-list-queue")
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
        residentModelLoader: { makeResidentModel() },
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
        profileName: "bright-guide",
        text: "Hello there",
        voiceDescription: "Warm and bright",
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

    let clearID = await runtime.clearQueue(id: "req-clear")
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
        residentModelLoader: { makeResidentModel() }
    )

    let activeHandle = await runtime.submit(
        .queueSpeech(
            id: "req-active",
            text: "Hello there",
            profileName: "default-femme",
            jobType: .live,
            normalizationContext: nil
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

    let cancelID = await runtime.cancelRequest(with: "req-active", requestID: "req-cancel")
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
        residentModelLoader: { makeResidentModel() },
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
        profileName: "bright-guide",
        text: "Hello there",
        voiceDescription: "Warm and bright",
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

    let cancelID = await runtime.cancelRequest(with: "req-queued", requestID: "req-cancel")
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

@Test func libraryCreateListAndRemoveHelpersSubmitWorkerProtocolRequests() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        residentModelLoader: { makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let createID = await runtime.createProfile(
        profileName: "bright-guide",
        text: "Hello there",
        voiceDescription: "Warm and bright",
        outputPath: nil,
        id: "req-create"
    )
    #expect(createID == "req-create")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
        }
    })

    let listID = await runtime.listProfiles(id: "req-list")
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

    let removeID = await runtime.removeProfile(profileName: "bright-guide", id: "req-remove")
    #expect(removeID == "req-remove")
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-remove"
                && $0["ok"] as? Bool == true
                && $0["profile_name"] as? String == "bright-guide"
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
        residentModelLoader: { makeResidentModel() }
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
        residentModelLoader: { makeResidentModel(recorder: recorder) }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.queueSpeech(
        text: "Hello there, galew.",
        profileName: "default-femme",
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
        residentModelLoader: { makeResidentModel() }
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
        residentModelLoader: {
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
        residentModelLoader: { makeResidentModel() }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    _ = await runtime.queueSpeech(text: "Hello there", profileName: "default-femme", as: .live, id: "req-active")
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
            jobType: .live,
            normalizationContext: nil
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
        residentModelLoader: { makeResidentModel() }
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
        residentModelLoader: { makeResidentModel() },
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

    let startedOps = output.startedEvents()
    #expect(startedOps == ["req-1:create_profile", "req-2:queue_speech_live", "req-3:list_profiles"])
}

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
        residentModelLoader: { makeResidentModel() }
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
        residentModelLoader: { makeResidentModel() }
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
        residentModelLoader: { makeResidentModel() }
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
            jobType: .live,
            normalizationContext: nil
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
        .listProfiles(id: "req-queued-shutdown-stream")
    )
    var queuedIterator = queuedHandle.events.makeAsyncIterator()

    let queuedEvent = try await queuedIterator.next()
    #expect(queuedEvent == .started(WorkerStartedEvent(id: "req-queued-shutdown-stream", op: "list_profiles")))

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
        residentModelLoader: { makeResidentModel() }
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
        residentModelLoader: { makeResidentModel() },
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
