import Foundation
@preconcurrency import MLX
import Testing
@testable import SpeakSwiftly

@Test func adaptivePlaybackThresholdsSeedFromTextComplexityClasses() {
    let compact = PlaybackThresholdController(text: "Hello there.").thresholds
    let balanced = PlaybackThresholdController(
        text: "Please read /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift and explain why optionals like user?.displayName matter."
    ).thresholds
    let extended = PlaybackThresholdController(
        text: """
        Please read this markdown block and path dump carefully.
        ```swift
        let greeting = user?.displayName ?? "friend"
        let path = "/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift"
        let fallback = settings["voice_profile"] ?? defaults["voice_profile"]
        print(greeting, path, fallback)
        ```
        Also compare /tmp/speakswiftly-forensic-capture-run2/stderr.jsonl with ~/Library/Logs/speak-to-user-mcp/v0.3.1/stderr.log and spell out qqqwweerrtyy carefully.
        """
    ).thresholds

    #expect(compact.complexityClass == .compact)
    #expect(balanced.complexityClass == .balanced)
    #expect(extended.complexityClass == .extended)
    #expect(compact.startupBufferTargetMS < balanced.startupBufferTargetMS)
    #expect(balanced.startupBufferTargetMS < extended.startupBufferTargetMS)
    #expect(compact.resumeBufferTargetMS < balanced.resumeBufferTargetMS)
    #expect(balanced.resumeBufferTargetMS < extended.resumeBufferTargetMS)
}

@Test func adaptivePlaybackThresholdsRaiseTargetsForSlowCadenceAndStarvation() {
    var controller = PlaybackThresholdController(text: "Hello there.")
    let seeded = controller.thresholds

    for _ in 0..<4 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 315)
    }
    let adapted = controller.thresholds
    controller.recordStarvation()
    let starved = controller.thresholds

    #expect(adapted.startupBufferTargetMS > seeded.startupBufferTargetMS)
    #expect(adapted.lowWaterTargetMS > seeded.lowWaterTargetMS)
    #expect(adapted.resumeBufferTargetMS > seeded.resumeBufferTargetMS)
    #expect(starved.resumeBufferTargetMS > adapted.resumeBufferTargetMS)
    #expect(starved.startupBufferTargetMS >= starved.resumeBufferTargetMS)
    #expect(starved.lowWaterTargetMS >= adapted.lowWaterTargetMS)
}

@Test func speakLiveUsesStoredProfileDataWaitsForPlaybackDrainAndReusesPlaybackController() async throws {
    let output = OutputRecorder()
    let playbackDrain = AsyncGate()
    let playback = PlaybackSpy(behavior: .gate(playbackDrain))
    let residentRecorder = ResidentModelRecorder()
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
        audioLoadRecorder: residentRecorder,
        residentModelLoader: {
            makeResidentModel(recorder: residentRecorder)
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}"#)
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
    #expect(!output.containsJSONObject {
        $0["id"] as? String == "req-1"
            && $0["ok"] as? Bool == true
    })

    await playbackDrain.open()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"speak_live","text":"Hello again","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == true
        }
    })

    await runtime.shutdown()

    #expect(residentRecorder.lastRefText == "Reference transcript")
    #expect(residentRecorder.lastRefAudioWasProvided == false)
    #expect(residentRecorder.audioLoadCallCount == 2)
    #expect(playback.playCount == 2)
    #expect(playback.prepareCount >= 1)
    #expect(playback.stopCount == 1)
}

@Test func playbackTimeoutFailsOnlyThatRequestAndWorkerKeepsRunning() async throws {
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

    let playback = PlaybackSpy(
        behavior: .throw(
            WorkerError(
                code: .audioPlaybackTimeout,
                message: "Live playback timed out after generated audio finished because the local audio player did not report drain completion within 5 seconds."
            )
        )
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

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == false
                && $0["code"] as? String == "audio_playback_timeout"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_first_chunk"
                && $0["request_id"] as? String == "req-1"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"list_profiles"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == true
        }
    })
}

@Test func stderrLogsUseJSONLAndIncludeExpandedPlaybackMetrics() async throws {
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
        playback: PlaybackSpy(behavior: .immediate),
        residentModelLoader: { makeResidentModel(chunkCount: 3) }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "resident_model_preload_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_finished",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["chunk_count"] as? Int == 3
                && details["streaming_interval"] as? Double == 0.18
                && details["startup_buffer_target_ms"] as? Int == 360
                && details["low_water_target_ms"] as? Int == 140
                && details["chunk_gap_warning_threshold_ms"] as? Int == 450
                && details["schedule_gap_warning_threshold_ms"] as? Int == 180
                && details["rebuffer_event_count"] as? Int == 0
                && details["starvation_event_count"] as? Int == 0
                && details["startup_buffered_audio_ms"] as? Int != nil
                && details["min_queued_audio_ms"] as? Int != nil
                && details["max_queued_audio_ms"] as? Int != nil
                && details["avg_queued_audio_ms"] as? Int != nil
                && details["queue_depth_sample_count"] as? Int != nil
                && details["schedule_callback_count"] as? Int != nil
                && details["played_back_callback_count"] as? Int != nil
                && details["fade_in_chunk_count"] as? Int != nil
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_engine_ready"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "request_succeeded"
                && $0["request_id"] as? String == "req-1"
        }
    })
}

@Test func stderrLogsQueueDepthWarningsStarvationAndExpandedDurations() async throws {
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
        playback: PlaybackSpy(behavior: .emitLowQueueThenStarve),
        residentModelLoader: { makeResidentModel(chunkCount: 1) }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_rebuffer_started",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["low_water_target_ms"] as? Int == 140
                && details["queued_audio_ms"] as? Int == 120
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_starved"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_finished",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["rebuffer_event_count"] as? Int == 1
                && details["rebuffer_total_duration_ms"] as? Int == 90
                && details["longest_rebuffer_duration_ms"] as? Int == 90
                && details["starvation_event_count"] as? Int == 1
                && details["max_inter_chunk_gap_ms"] as? Int == 510
                && details["max_schedule_gap_ms"] as? Int == 220
        }
    })
}

@Test func stderrLogsPlaybackWarningsTraceAndBufferShapeSummaries() async throws {
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
        playback: PlaybackSpy(behavior: .emitObservabilityBurst),
        residentModelLoader: { makeResidentModel(chunkCount: 2) }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Longer playback diagnostics check","profile_name":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_chunk_gap_warning"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_schedule_gap_warning"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_rebuffer_thrash_warning"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_buffer_shape_summary",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["max_boundary_discontinuity"] as? Double == 0.42
                && details["fade_in_chunk_count"] as? Int == 1
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_trace_chunk_received"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_trace_buffer_scheduled"
                && $0["request_id"] as? String == "req-1"
        }
    })
}

@Test func speakLivePassesNonNilReferenceAudioIntoResidentGeneration() async throws {
    let output = OutputRecorder()
    let residentRecorder = ResidentModelRecorder()
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
        audioLoadRecorder: residentRecorder,
        loadedAudioSamples: .mlxNone,
        residentModelLoader: {
            makeResidentModel(recorder: residentRecorder)
        }
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    #expect(residentRecorder.lastRefAudioWasProvided == true)
    #expect(residentRecorder.audioLoadCallCount == 1)
}

@Test func speakLiveNormalizesCodeHeavyMarkdownBeforeResidentGeneration() async throws {
    let output = OutputRecorder()
    let residentRecorder = ResidentModelRecorder()
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
        audioLoadRecorder: residentRecorder,
        residentModelLoader: {
            makeResidentModel(recorder: residentRecorder)
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
        line: #"""
        {"id":"req-1","op":"speak_live","text":"Please read `fooBar()` and this block:\n```swift\nlet greeting = user?.displayName ?? \"friend\"\n```","profile_name":"default-femme"}
        """#
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    let normalized = try #require(residentRecorder.lastText)
    #expect(!normalized.contains("```"))
    #expect(!normalized.contains("`"))
    #expect(normalized.contains("foo Bar open parenthesis close parenthesis"))
    #expect(normalized.contains("Code sample."))
    #expect(normalized.contains("optional chaining"))
    #expect(normalized.contains("nil coalescing"))
}

@Test func shapePlaybackSamplesSmoothsBoundaryJumpsAndSanitizesInvalidValues() {
    let shaped = shapePlaybackSamples(
        [Float.nan, 1.8, -1.6, 0.25],
        sampleRate: 24_000,
        previousTrailingSample: 0.35,
        applyFadeIn: false
    )

    #expect(shaped.count == 4)
    #expect(shaped.allSatisfy { $0.isFinite && $0 >= -1 && $0 <= 1 })
    #expect(abs(shaped[0] - 0.35) < 0.000_1)
}
