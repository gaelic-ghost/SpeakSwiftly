import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

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

    let activeID = await runtime.generate.speech(
        text: "Hello there",
        with: "default-femme"
    ).id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == activeID
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    let backgroundID = await runtime.generate.speech(
        text: "Hi there",
        with: "default-femme"
    ).id

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

    let failedID = await runtime.generate.speech(
        text: "Hello there",
        with: "default-femme"
    ).id

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

@Test func playbackEventsIncludeRuntimeCPUAndMemoryMetricsWhenAvailable() async throws {
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
        residentModelLoader: { _ in makeResidentModel() },
        readRuntimeMemory: {
            RuntimeMemorySnapshot(
                processResidentBytes: 1_000,
                processPhysFootprintBytes: 2_000,
                processUserCPUTimeNS: 3_000,
                processSystemCPUTimeNS: 4_000,
                mlxActiveMemoryBytes: 5_000,
                mlxCacheMemoryBytes: 6_000,
                mlxPeakMemoryBytes: 7_000,
                mlxCacheLimitBytes: 8_000,
                mlxMemoryLimitBytes: 9_000
            )
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_engine_ready",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_resident_bytes"] as? Int == 1_000
                && details["process_phys_footprint_bytes"] as? Int == 2_000
                && details["process_user_cpu_time_ns"] as? Int == 3_000
                && details["process_system_cpu_time_ns"] as? Int == 4_000
                && details["mlx_active_memory_bytes"] as? Int == 5_000
                && details["mlx_cache_memory_bytes"] as? Int == 6_000
                && details["mlx_peak_memory_bytes"] as? Int == 7_000
                && details["mlx_cache_limit_bytes"] as? Int == 8_000
                && details["mlx_memory_limit_bytes"] as? Int == 9_000
        }
    })

    let metricsID = await runtime.generate.speech(
        text: "Hello there",
        with: "default-femme"
    ).id

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["request_id"] as? String == metricsID,
                $0["event"] as? String == "playback_finished",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_resident_bytes"] as? Int == 1_000
                && details["process_phys_footprint_bytes"] as? Int == 2_000
                && details["process_user_cpu_time_ns"] as? Int == 3_000
                && details["process_system_cpu_time_ns"] as? Int == 4_000
        }
    })
}
