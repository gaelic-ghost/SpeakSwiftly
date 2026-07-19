import Foundation
@testable import SpeakSwiftly
import Testing

private actor EnvironmentEventRecorder {
    private var storedEvents = [PlaybackEnvironmentEvent]()

    func record(_ event: PlaybackEnvironmentEvent) {
        storedEvents.append(event)
    }

    func events() -> [PlaybackEnvironmentEvent] {
        storedEvents
    }
}

// MARK: - Playback Utilities

private func makeStreamOnlyResidentModel() -> AnySpeechModel {
    AnySpeechModel(
        sampleRate: 24000,
        generate: { _, _, _, _, _, _ in
            [0.1, 0.2]
        },
        generateSamplesStream: { _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield([0.1, 0.2])
                continuation.finish()
            }
        },
    )
}

@discardableResult
private func seedRecentGeneratedAudio(
    in store: SpeakSwiftly.RecentGeneratedAudioStore,
    id: String,
    requestID: String,
    text: String,
) async throws -> SpeakSwiftly.RecentGeneratedAudioItem {
    await store.begin(
        SpeakSwiftly.RecentGeneratedAudioMetadata(
            id: id,
            requestID: requestID,
            textPreview: text,
            voiceProfileName: "default-femme",
        ),
    )
    try await store.append(
        SpeakSwiftly.GeneratedAudioChunk(
            requestID: requestID,
            sequenceNumber: 0,
            sampleRate: 24000,
            channelCount: 1,
            samples: [0.1, 0.2],
        ),
        to: id,
    )
    try await store.append(
        SpeakSwiftly.GeneratedAudioChunk(
            requestID: requestID,
            sequenceNumber: 1,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ),
        to: id,
    )
    return try #require(await store.finish(id: id))
}

@Test func `inter job boop samples are short faded and audible`() {
    let sampleRate = 24000.0
    let samples = makeInterJobBoopSamples(sampleRate: sampleRate)

    #expect(!samples.isEmpty)
    #expect(samples.count == Int((sampleRate * 90.0) / 1000.0))
    #expect(abs(samples.first ?? 1) < 0.01)
    #expect(abs(samples.last ?? 1) < 0.02)
    #expect(samples.contains { abs($0) > 0.05 })
    #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.14 })
}

@Test func `generated audio quality monitor records raw chunk shape before sample shaping`() {
    var monitor = GeneratedAudioQualityMonitor(sampleRate: 4, repeatedWindowSampleCount: 4)

    let first = monitor.observe(
        samples: [0, 0.5, -0.5, 1.2, .nan, -1],
        chunkIndex: 1,
    )

    #expect(first.chunkIndex == 1)
    #expect(first.sampleCount == 6)
    #expect(first.generatedDurationMS == 1500)
    #expect(first.totalGeneratedDurationMS == 1500)
    #expect(first.nonFiniteSampleCount == 1)
    #expect(abs(first.peakAmplitude - 1.2) < 0.000_1)
    #expect(abs(first.rmsAmplitude - 0.766_8) < 0.000_1)
    #expect(abs(first.nearSilenceRatio - (1.0 / 6.0)) < 0.000_1)
    #expect(abs(first.clippingRatio - (2.0 / 6.0)) < 0.000_1)
    #expect(abs(first.dcOffset - 0.04) < 0.000_1)
    #expect(abs(first.zeroCrossingRate - 1.0) < 0.000_1)
    #expect(first.boundaryJump == nil)
    #expect(first.repeatedWindowSimilarity == nil)

    let second = monitor.observe(
        samples: [0, 0.5, -0.5, 1.2, 0, -1],
        chunkIndex: 2,
    )

    #expect(second.totalGeneratedDurationMS == 3000)
    #expect(abs((second.boundaryJump ?? 0) - 1.0) < 0.000_1)
    #expect(abs((second.repeatedWindowSimilarity ?? 0) - 1.0) < 0.000_1)
}

@Test func `generated audio quality monitor warns only on high signal suspicious chunks`() {
    var invalidMonitor = GeneratedAudioQualityMonitor(sampleRate: 4, repeatedWindowSampleCount: 4)
    let invalid = invalidMonitor.observe(
        samples: [0.1, .nan, 0.2, .infinity],
        chunkIndex: 1,
    )
    #expect(invalidMonitor.warning(for: invalid)?.reason == .nonFiniteSamples)

    var quietRepeatedMonitor = GeneratedAudioQualityMonitor(sampleRate: 1, repeatedWindowSampleCount: 4)
    _ = quietRepeatedMonitor.observe(
        samples: [0.000_1, 0.000_1, 0.000_1, 0.000_1],
        chunkIndex: 1,
    )
    _ = quietRepeatedMonitor.observe(
        samples: [0.000_1, 0.000_1, 0.000_1, 0.000_1],
        chunkIndex: 2,
    )
    let quietRepeated = quietRepeatedMonitor.observe(
        samples: [0.000_1, 0.000_1, 0.000_1, 0.000_1],
        chunkIndex: 3,
    )
    #expect(quietRepeated.repeatedWindowSimilarity == 1)
    #expect(quietRepeatedMonitor.warning(for: quietRepeated) == nil)

    var loudRepeatedMonitor = GeneratedAudioQualityMonitor(sampleRate: 1, repeatedWindowSampleCount: 4)
    _ = loudRepeatedMonitor.observe(samples: [0.2, -0.2, 0.2, -0.2], chunkIndex: 1)
    _ = loudRepeatedMonitor.observe(samples: [0.2, -0.2, 0.2, -0.2], chunkIndex: 2)
    let loudRepeated = loudRepeatedMonitor.observe(samples: [0.2, -0.2, 0.2, -0.2], chunkIndex: 3)
    #expect(loudRepeatedMonitor.warning(for: loudRepeated)?.reason == .repeatedNonSilentWindow)
}

@MainActor
@Test func `playback drain waiter clears stored continuation when cancelled`() async throws {
    let driver = AudioPlaybackDriver()
    let state = AudioPlaybackRequestState(
        requestID: 1,
        text: "queued drain test",
        tuningProfile: .standard,
    )
    state.queuedSampleCount = 2400

    let waitTask = Task {
        try await driver.awaitPlaybackDrainSignal(
            state: state,
            sampleRate: 24000,
        )
    }

    await Task.yield()
    #expect(state.drainContinuation != nil)

    waitTask.cancel()
    _ = try? await waitTask.value

    for _ in 0..<20 where state.drainContinuation != nil {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(state.drainContinuation == nil)
}

// MARK: - Live Playback Queueing

@Test func `speak live background acknowledges queue before playback starts and only succeeds once`() async throws {
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

    let activeID = await runtime.generate
        .speech(
            text: "Hello there",
            voiceProfile: "default-femme",
        )
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let backgroundID = await runtime.generate
        .speech(
            text: "Hi there",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == backgroundID
                && $0["ok"] as? Bool == true
        }
    })
    #expect(!output.containsJSONObject {
        $0["id"] as? String == backgroundID
            && $0["event"] as? String == "progress"
            && $0["stage"] as? String == "playback_finished"
    })

    await playbackDrain.open()

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == backgroundID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        }
    })
    #expect(output.countJSONObjects {
        $0["id"] as? String == backgroundID
            && $0["ok"] as? Bool == true
    } == 1)
}

@Test func `speak live playback records recent generated audio chunks`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel(chunkCount: 2) },
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
            text: "Replay this live speech later.",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == requestID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        }
    })
    #expect(playback.playCount == 1)

    let recentSnapshot = await runtime.playback.recentGeneratedAudio()
    let recentItem = try #require(recentSnapshot.items.first)
    #expect(recentSnapshot.items.count == 1)
    #expect(recentItem.requestID == requestID)
    #expect(recentItem.textPreview == "Replay this live speech later.")
    #expect(recentItem.voiceProfileName == "default-femme")
    #expect(recentItem.bufferState == .complete)
    #expect(recentItem.sampleRate == 24000)
    #expect(recentItem.channelCount == 1)
    #expect(recentItem.bufferedChunkCount == 3)

    let recentChunks = await runtime.playback.recentGeneratedAudioChunks(for: recentItem.id)
    #expect(recentChunks.map(\.sequenceNumber) == [0, 1, 2])
    #expect(recentChunks.map(\.samples) == [[0.1, 0.2], [0.2, 0.3], []])
    #expect(recentChunks.map(\.isFinal) == [false, false, true])

    let replay = await runtime.playback.replayRecent(id: recentItem.id)
    #expect(replay.kind == .replayRecentAudio)
    let completion = try await replay.completion()
    #expect(completion == .empty)
    #expect(playback.playCount == 2)
}

@Test func `replay recent generated audio fails clearly when item is missing`() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
    )

    let replay = await runtime.playback.replayRecent(id: "missing-recent-audio")
    await #expect(throws: WorkerError.self) {
        try await replay.completion()
    }
    #expect(playback.playCount == 0)
}

@Test func `replay recent all queues complete items in snapshot order ahead of waiting speech`() async throws {
    let output = OutputRecorder()
    let playbackGate = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackGate))
    let recentStore = SpeakSwiftly.RecentGeneratedAudioStore(limit: 5)
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

    try await seedRecentGeneratedAudio(
        in: recentStore,
        id: "recent-oldest",
        requestID: "recent-request-1",
        text: "Oldest replay.",
    )
    try await seedRecentGeneratedAudio(
        in: recentStore,
        id: "recent-newest",
        requestID: "recent-request-2",
        text: "Newest replay.",
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        recentGeneratedAudioStore: recentStore,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeID = await runtime.generate
        .speech(text: "Hold active playback open.", voiceProfile: "default-femme")
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let waitingID = await runtime.generate
        .speech(text: "This generated request should wait behind replays.", voiceProfile: "default-femme")
        .id

    let completeRecentIDs = await runtime.playback
        .recentGeneratedAudio()
        .items
        .filter { $0.bufferState == .complete }
        .map(\.id)
    let handles = await runtime.playback.replayRecentAll()
    #expect(handles.count == completeRecentIDs.count)
    #expect(handles.map(\.voiceProfile) == Array(repeating: "default-femme", count: completeRecentIDs.count))

    let snapshot = await runtime.playback.snapshot()
    let queuedIDs = snapshot.queuedRequests.map(\.id)
    #expect(Array(queuedIDs.prefix(handles.count)) == handles.map(\.id))
    #expect(queuedIDs.dropFirst(handles.count).first == waitingID)

    await playbackGate.open()
}

@Test func `replay recent all enqueue after current preserves snapshot order ahead of waiting speech`() async throws {
    let output = OutputRecorder()
    let playbackGate = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackGate))
    let recentStore = SpeakSwiftly.RecentGeneratedAudioStore(limit: 5)
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

    try await seedRecentGeneratedAudio(
        in: recentStore,
        id: "recent-oldest",
        requestID: "recent-request-1",
        text: "Oldest replay.",
    )
    try await seedRecentGeneratedAudio(
        in: recentStore,
        id: "recent-newest",
        requestID: "recent-request-2",
        text: "Newest replay.",
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        recentGeneratedAudioStore: recentStore,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let activeID = await runtime.generate
        .speech(text: "Hold active playback open.", voiceProfile: "default-femme")
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let waitingID = await runtime.generate
        .speech(text: "This generated request should wait behind replays.", voiceProfile: "default-femme")
        .id

    let completeRecentIDs = await runtime.playback
        .recentGeneratedAudio()
        .items
        .filter { $0.bufferState == .complete }
        .map(\.id)
    let handles = await runtime.playback.replayRecentAll(mode: .enqueueAfterCurrent)
    #expect(handles.count == completeRecentIDs.count)

    let snapshot = await runtime.playback.snapshot()
    let queuedIDs = snapshot.queuedRequests.map(\.id)
    #expect(Array(queuedIDs.prefix(handles.count)) == handles.map(\.id))
    #expect(queuedIDs.dropFirst(handles.count).first == waitingID)

    await playbackGate.open()
}

@Test func `recent generated audio disabled by configuration leaves snapshot empty and direct replay fails`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        recentGeneratedAudioLimit: 0,
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let requestID = await runtime.generate
        .speech(text: "Do not retain this.", voiceProfile: "default-femme")
        .id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == requestID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        }
    })

    let recentSnapshot = await runtime.playback.recentGeneratedAudio()
    #expect(recentSnapshot.limit == 0)
    #expect(recentSnapshot.items.isEmpty)

    let replay = await runtime.playback.replayRecent(id: "any-recent-audio")
    await #expect(throws: WorkerError.self) {
        try await replay.completion()
    }
}

@Test func `recent generated audio JSONL operations emit stable success shapes`() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let recentStore = SpeakSwiftly.RecentGeneratedAudioStore(limit: 5)
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    try await seedRecentGeneratedAudio(
        in: recentStore,
        id: "recent-jsonl",
        requestID: "recent-request-jsonl",
        text: "Replay through JSONL.",
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        recentGeneratedAudioStore: recentStore,
        residentModelLoader: { _ in makeResidentModel() },
        startsResidentModelsAutomatically: false,
    )

    await runtime.accept(line: #"{"id":"req-list-recent","op":"list_recent_generated_audio"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            guard $0["id"] as? String == "req-list-recent",
                  let snapshot = $0["recent_generated_audio"] as? [String: Any],
                  let items = snapshot["items"] as? [[String: Any]] else {
                return false
            }

            return items.map { $0["id"] as? String } == ["recent-jsonl"]
        }
    })

    await runtime.accept(
        line: #"{"id":"req-recent-chunks","op":"get_recent_generated_audio_chunks","recent_audio_id":"recent-jsonl"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            guard $0["id"] as? String == "req-recent-chunks",
                  let chunks = $0["recent_generated_audio_chunks"] as? [[String: Any]] else {
                return false
            }

            return chunks.map { $0["sequenceNumber"] as? Int } == [0, 1]
        }
    })

    await runtime.accept(
        line: #"{"id":"req-replay-all","op":"replay_recent_audio_all","replay_mode":"enqueue_next"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            guard $0["id"] as? String == "req-replay-all",
                  let requestIDs = $0["replay_request_ids"] as? [String] else {
                return false
            }

            return requestIDs.count == 1
        }
    })

    await runtime.accept(line: #"{"id":"req-clear-recent","op":"clear_recent_generated_audio"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            guard $0["id"] as? String == "req-clear-recent",
                  let snapshot = $0["recent_generated_audio"] as? [String: Any],
                  let items = snapshot["items"] as? [[String: Any]] else {
                return false
            }

            return items.isEmpty
        }
    })
}

@Test func `speak live background can fail after enqueue acknowledgement`() async throws {
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
        playback: PlaybackSpy(
            behavior: .throw(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Background playback failed in the test playback driver after the request had already been accepted.",
                ),
            ),
        ),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let failedID = await runtime.generate
        .speech(
            text: "Hello there",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == failedID
                && $0["ok"] as? Bool == true
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == failedID
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "audio_playback_failed"
        }
    })
    #expect(output.countJSONObjects {
        $0["id"] as? String == failedID
            && $0["ok"] as? Bool == true
    } == 1)
}

@Test func `speech uses configured nonlocal output when call does not override destination`() async throws {
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
        qwenConditioningStrategy: .legacyRaw,
        audioOutputDestination: .httpResponseStream,
        loadedAudioSamples: nil,
        residentModelLoader: { _ in makeStreamOnlyResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let failedID = await runtime.generate
        .speech(
            text: "Hello there",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == failedID
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "invalid_request"
                && (($0["message"] as? String)?.contains("HTTP audio streaming") ?? false)
        }
    })

    let rejectedOutputSnapshot = await runtime.playback.snapshot()
    #expect(rejectedOutputSnapshot.activeRequest == nil)
    #expect(rejectedOutputSnapshot.queuedRequests.isEmpty)

    let playedID = await runtime.generate
        .speech(
            text: "Hello locally",
            voiceProfile: "default-femme",
            output: .localPlayback,
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == playedID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        }
    })
}

@Test func `explicit local playback output overrides configured nonlocal destination`() async throws {
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
        qwenConditioningStrategy: .legacyRaw,
        audioOutputDestination: .httpResponseStream,
        loadedAudioSamples: nil,
        residentModelLoader: { _ in makeStreamOnlyResidentModel() },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let playedID = await runtime.generate
        .speech(
            text: "Hello there",
            voiceProfile: "default-femme",
            output: .localPlayback,
        )
        .id

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == playedID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "playback_finished"
        }
    })
}

@Test func `saving runtime configuration preserves configured audio output destination`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        audioOutputDestination: .networkService(name: "Mac mini"),
        loadedAudioSamples: nil,
        residentModelLoader: { _ in makeStreamOnlyResidentModel() },
        startsResidentModelsAutomatically: false,
    )

    try await runtime.setDefaultVoiceProfile("testing-profile")

    let configuration = try SpeakSwiftly.Configuration.load(
        from: storeRoot.appendingPathComponent(ProfileStore.configurationFileName),
    )

    #expect(configuration.audioOutputDestination == .networkService(name: "Mac mini"))
}

@Test func `resident preload stays playback cold until the first audible request`() async throws {
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

    #expect(playback.prepareCount == 0)
    #expect(!output.containsStderrJSONObject {
        $0["event"] as? String == "playback_engine_ready"
    })

    let playbackID = await runtime.generate
        .speech(
            text: "Hello there",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_engine_ready",
                $0["request_id"] as? String == playbackID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["sample_rate"] as? Int == 24000
        }
    })
    #expect(playback.prepareCount >= 1)
}

@Test func `playback events include runtime CPU and memory metrics when available`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel() },
        readRuntimeMemory: {
            RuntimeMemorySnapshot(
                processResidentBytes: 1000,
                processPhysFootprintBytes: 2000,
                processUserCPUTimeNS: 3000,
                processSystemCPUTimeNS: 4000,
                mlxActiveMemoryBytes: 5000,
                mlxCacheMemoryBytes: 6000,
                mlxPeakMemoryBytes: 7000,
                mlxCacheLimitBytes: 8000,
                mlxMemoryLimitBytes: 9000,
            )
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })
    #expect(playback.prepareCount == 0)

    let metricsID = await runtime.generate
        .speech(
            text: "Hello there",
            voiceProfile: "default-femme",
        )
        .id

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["request_id"] as? String == metricsID,
                $0["event"] as? String == "playback_engine_ready",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_resident_bytes"] as? Int == 1000
                && details["process_phys_footprint_bytes"] as? Int == 2000
                && details["process_user_cpu_time_ns"] as? Int == 3000
                && details["process_system_cpu_time_ns"] as? Int == 4000
                && details["mlx_active_memory_bytes"] as? Int == 5000
                && details["mlx_cache_memory_bytes"] as? Int == 6000
                && details["mlx_peak_memory_bytes"] as? Int == 7000
                && details["mlx_cache_limit_bytes"] as? Int == 8000
                && details["mlx_memory_limit_bytes"] as? Int == 9000
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["request_id"] as? String == metricsID,
                $0["event"] as? String == "playback_finished",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_resident_bytes"] as? Int == 1000
                && details["process_phys_footprint_bytes"] as? Int == 2000
                && details["process_user_cpu_time_ns"] as? Int == 3000
                && details["process_system_cpu_time_ns"] as? Int == 4000
        }
    })
}

@MainActor
@Test func `binding playback environment sink does not emit output device observation until playback preparation`() async throws {
    let driver = AudioPlaybackDriver()
    let recorder = EnvironmentEventRecorder()

    driver.setEnvironmentEventSink { event in
        await recorder.record(event)
    }

    try await Task.sleep(for: .milliseconds(50))
    #expect(await recorder.events().isEmpty)
}

@MainActor
@Test func `non resumable interruption immediately fails the active playback request`() async throws {
    let driver = AudioPlaybackDriver()
    let state = AudioPlaybackRequestState(
        requestID: 7,
        text: "interruption test",
        tuningProfile: .standard,
    )
    state.queuedSampleCount = 2400
    driver.activeRequestState = state

    let waitTask = Task {
        try await driver.awaitPlaybackDrainSignal(
            state: state,
            sampleRate: 24000,
        )
    }

    await Task.yield()
    #expect(state.drainContinuation != nil)

    driver.handleInterruptionStateChange(
        isInterrupted: false,
        shouldResume: false,
    )

    await #expect(throws: WorkerError.self) {
        try await waitTask.value
    }

    let failure = try #require(driver.activeRuntimeFailure)
    #expect(failure.code == .audioPlaybackFailed)
    #expect(failure.message == "Live playback was interrupted and the active audio session reported that this request must not resume automatically.")
    #expect(driver.playbackRecoveryReason == nil)
}

@Test func `playback environment events are logged for power session and recovery changes`() async throws {
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
        playback: PlaybackSpy(
            environmentEvents: [
                .systemSleepStateChanged(isSleeping: true),
                .systemSleepStateChanged(isSleeping: false),
                .screenSleepStateChanged(isSleeping: true),
                .screenSleepStateChanged(isSleeping: false),
                .sessionActivityChanged(isActive: false),
                .sessionActivityChanged(isActive: true),
                .interruptionStateChanged(isInterrupted: true, shouldResume: nil),
                .interruptionStateChanged(isInterrupted: false, shouldResume: true),
                .recoveryStateChanged(
                    reason: "output_device_change",
                    stage: "recovered",
                    attempt: 2,
                    currentDevice: "AirPods Pro [42]",
                ),
            ],
        ),
        residentModelLoader: { _ in makeResidentModel() },
    )

    await runtime.start()

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_system_sleep_started"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_system_woke"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_screen_sleep_started"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_screen_woke"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_session_resigned_active"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_interruption_began"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_interruption_ended",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["should_resume"] as? Bool == true
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_recovery_state_changed",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["reason"] as? String == "output_device_change"
                && details["stage"] as? String == "recovered"
                && details["attempt"] as? Int == 2
                && details["current_device"] as? String == "AirPods Pro [42]"
        }
    })
}
