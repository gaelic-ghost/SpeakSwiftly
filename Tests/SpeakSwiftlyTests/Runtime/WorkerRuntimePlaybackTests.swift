import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

// MARK: - EnvironmentEventRecorder

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
            with: "default-femme",
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
            with: "default-femme",
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
                    message: "Background playback failed in the test playback controller after the request had already been accepted.",
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
            with: "default-femme",
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
            with: "default-femme",
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
            with: "default-femme",
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
