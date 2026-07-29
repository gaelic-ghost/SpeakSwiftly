import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@testable import SpeakSwiftly
import Testing

private let longPlaybackPlannerFixtureText = """
Hello from the real resident SpeakSwiftly playback path. This end to end test now uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.
"""

private actor ProfileModelLoadObservation {
    private(set) var repo: String?
    private(set) var loadDeviceType: DeviceType?
    private(set) var generateDeviceType: DeviceType?

    func recordLoad(repo: String, deviceType: DeviceType?) {
        self.repo = repo
        loadDeviceType = deviceType
    }

    func recordGenerate(deviceType: DeviceType?) {
        generateDeviceType = deviceType
    }
}

// MARK: - Profile Model Loading

@Test func `profile model load rejects missing metal device by default`() async throws {
    do {
        _ = try await ModelFactory.loadProfileModel(
            hasDefaultMetalDevice: { false },
            modelLoader: { _ in makeProfileModel() },
        )
        Issue.record("Expected profile model loading to reject missing Metal without explicit CPU fallback.")
    } catch let error as WorkerError {
        #expect(error.code == .modelLoading)
        #expect(error.message.contains("Metal did not provide a default GPU device"))
        #expect(error.message.contains("explicitly allow CPU profile-model fallback"))
    } catch {
        Issue.record("Expected WorkerError, got \(error).")
    }
}

@Test func `profile model load uses cpu fallback only when explicitly allowed`() async throws {
    let observation = ProfileModelLoadObservation()

    let model = try await ModelFactory.loadProfileModel(
        allowsCPUFallback: true,
        hasDefaultMetalDevice: { false },
        modelLoader: { repo in
            await observation.recordLoad(repo: repo, deviceType: Device.defaultDevice().deviceType)
            return AnySpeechModel(
                sampleRate: 24000,
                generate: { _, _, _, _, _, _ in
                    await observation.recordGenerate(deviceType: Device.defaultDevice().deviceType)
                    return [0.1, 0.2, 0.3]
                },
                generateSamplesStream: { _, _, _, _, _, _, _ in
                    AsyncThrowingStream { continuation in
                        continuation.finish()
                    }
                },
            )
        },
    )
    _ = try await model.generate(
        text: "Hello",
        voice: "Clear",
        refAudio: nil,
        refText: nil,
        language: nil,
        generationParameters: GenerationPolicy.profileModelParameters(for: "Hello"),
    )

    #expect(await observation.repo == ModelFactory.profileModelRepo)
    #expect(await observation.loadDeviceType == .cpu)
    #expect(await observation.generateDeviceType == .cpu)
}

@Test func `profile model load uses default device when metal device is available`() async throws {
    let observation = ProfileModelLoadObservation()

    _ = try await Device.withDefaultDevice(.gpu) {
        try await ModelFactory.loadProfileModel(
            hasDefaultMetalDevice: { true },
            modelLoader: { repo in
                await observation.recordLoad(repo: repo, deviceType: Device.defaultDevice().deviceType)
                return makeProfileModel()
            },
        )
    }

    #expect(await observation.repo == ModelFactory.profileModelRepo)
    #expect(await observation.loadDeviceType == .gpu)
}

@Test func `resident cadence uses qwen baseline`() {
    let qwenStandardInterval = SpeakSwiftly.Runtime.PlaybackConfiguration.residentStreamingInterval(
        for: .qwen3_smol,
        cadenceProfile: .standard,
    )

    #expect(qwenStandardInterval == 0.32)
}

@Test func `resident cadence profile stays standard for qwen requests`() {
    let qwenProfile = SpeakSwiftly.Runtime.PlaybackConfiguration.residentStreamingCadenceProfile(
        speechBackend: .qwen3_smol,
    )

    #expect(qwenProfile == .standard)
}

@Test func `concurrent generation stays closed below the claimed reserve target`() {
    #expect(
        PlaybackQueue.allowsConcurrentGeneration(
            bufferedAudioMS: 2160,
            targetMS: 3160,
        ) == false,
    )
    #expect(
        PlaybackQueue.allowsConcurrentGeneration(
            bufferedAudioMS: 3200,
            targetMS: 3160,
        ) == true,
    )
}

@Test func `fragile overlap window requires a brief healthy hold and re closes when reserve sags`() {
    let progress = PlaybackQueue.FragileOverlapWindowProgress(
        configuration: .init(
            holdBufferTargetMS: 3800,
            requiredStableBufferEventCount: 4,
        ),
        stableBufferEventCount: 0,
        hasSatisfiedHold: false,
    )

    let firstHealthyEvent = PlaybackQueue.resolveConcurrentGenerationAdmission(
        bufferedAudioMS: 3900,
        concurrentGenerationTargetMS: 3160,
        fragileOverlapWindowProgress: progress,
    )
    #expect(firstHealthyEvent.allowsConcurrentGeneration == false)
    #expect(firstHealthyEvent.effectiveTargetMS == 3800)
    #expect(firstHealthyEvent.fragileOverlapWindowProgress?.stableBufferEventCount == 1)
    #expect(firstHealthyEvent.fragileOverlapWindowProgress?.hasSatisfiedHold == false)

    let secondHealthyEvent = PlaybackQueue.resolveConcurrentGenerationAdmission(
        bufferedAudioMS: 3920,
        concurrentGenerationTargetMS: 3160,
        fragileOverlapWindowProgress: firstHealthyEvent.fragileOverlapWindowProgress,
    )
    #expect(secondHealthyEvent.allowsConcurrentGeneration == false)
    #expect(secondHealthyEvent.effectiveTargetMS == 3800)
    #expect(secondHealthyEvent.fragileOverlapWindowProgress?.stableBufferEventCount == 2)
    #expect(secondHealthyEvent.fragileOverlapWindowProgress?.hasSatisfiedHold == false)

    let thirdHealthyEvent = PlaybackQueue.resolveConcurrentGenerationAdmission(
        bufferedAudioMS: 3940,
        concurrentGenerationTargetMS: 3160,
        fragileOverlapWindowProgress: secondHealthyEvent.fragileOverlapWindowProgress,
    )
    #expect(thirdHealthyEvent.allowsConcurrentGeneration == false)
    #expect(thirdHealthyEvent.effectiveTargetMS == 3800)
    #expect(thirdHealthyEvent.fragileOverlapWindowProgress?.stableBufferEventCount == 3)
    #expect(thirdHealthyEvent.fragileOverlapWindowProgress?.hasSatisfiedHold == false)

    let fourthHealthyEvent = PlaybackQueue.resolveConcurrentGenerationAdmission(
        bufferedAudioMS: 3960,
        concurrentGenerationTargetMS: 3160,
        fragileOverlapWindowProgress: thirdHealthyEvent.fragileOverlapWindowProgress,
    )
    #expect(fourthHealthyEvent.allowsConcurrentGeneration == true)
    #expect(fourthHealthyEvent.effectiveTargetMS == 3160)
    #expect(fourthHealthyEvent.fragileOverlapWindowProgress?.hasSatisfiedHold == true)

    let collapsingReserveEvent = PlaybackQueue.resolveConcurrentGenerationAdmission(
        bufferedAudioMS: 3600,
        concurrentGenerationTargetMS: 3160,
        fragileOverlapWindowProgress: fourthHealthyEvent.fragileOverlapWindowProgress,
    )
    #expect(collapsingReserveEvent.allowsConcurrentGeneration == false)
    #expect(collapsingReserveEvent.effectiveTargetMS == 3800)
    #expect(collapsingReserveEvent.fragileOverlapWindowProgress?.stableBufferEventCount == 0)
    #expect(collapsingReserveEvent.fragileOverlapWindowProgress?.hasSatisfiedHold == false)
}

// MARK: - Runtime Playback Integration

@Test func `speak live uses stored profile data waits for playback drain and reuses playback queue`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        qwenConditioningStrategy: .legacyRaw,
        audioLoadRecorder: residentRecorder,
        loadedAudioSamples: nil,
        residentModelLoader: { _ in
            makeResidentModel(recorder: residentRecorder)
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)
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
    await playbackDrain.open()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-2","op":"generate_speech","text":"Hello again","voice_profile":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    await runtime.shutdown()

    #expect(residentRecorder.lastRefText == "Reference transcript")
    #expect(residentRecorder.lastRefAudioWasProvided == false)
    #expect(residentRecorder.audioLoadCallCount == 2)
    #expect(playback.playCount == 2)
    #expect(playback.prepareCount >= 1)
    #expect(playback.stopCount >= 1)
}

// MARK: - Deep Trace and Normalization

@Test func `speech text deep trace features capture code heavy and weird text shapes`() async throws {
    let original = """
    # Header

    The path is /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift and the symbol is NSApplication.didFinishLaunchingNotification.

    Please read `dot.syntax.stuff`, camelCaseStuff, snake_case_stuff, [a markdown link](https://example.com/docs), and https://example.com/reference.

    ```objc
    @property(nonatomic, strong) NSString *displayName;
    [NSFileManager.defaultManager fileExistsAtPath:@"/tmp/Thing"];
    ```

    Also say chrommmaticallly and qqqwweerrtyy once.
    """

    let normalized = try await normalizeTextForTest(original)
    let features = SpeakSwiftly.DeepTrace.features(
        originalText: original,
        normalizedText: normalized,
    )

    #expect(features.originalCharacterCount > 0)
    #expect(features.normalizedCharacterCount > 0)
    #expect(features.markdownHeaderCount == 1)
    #expect(features.fencedCodeBlockCount == 1)
    #expect(features.inlineCodeSpanCount >= 1)
    #expect(features.markdownLinkCount == 1)
    #expect(features.urlCount >= 1)
    #expect(features.filePathCount >= 2)
    #expect(features.dottedIdentifierCount >= 1)
    #expect(features.camelCaseTokenCount >= 1)
    #expect(features.snakeCaseTokenCount >= 1)
    #expect(features.objcSymbolCount >= 1)
    #expect(features.repeatedLetterRunCount >= 2)
}

@Test func `speech text deep trace sections and windows track segmented markdown structure`() {
    let original = """
    # Section One

    Please read this paragraph once and keep a natural tone.

    ## Section Two

    Read these identifiers carefully: NSApplication.didFinishLaunchingNotification, camelCaseStuff, snake_case_stuff, and `profile?.sampleRate ?? 24000`.

    ## Section Three

    ```objc
    @property(nonatomic, strong) NSString *displayName;
    [NSFileManager.defaultManager fileExistsAtPath:@"/tmp/Thing"];
    ```

    ## Footer

    End this probe clearly and without looping.
    """

    let sections = SpeakSwiftly.DeepTrace.sections(originalText: original)
    #expect(sections.map(\.title) == ["Section One", "Section Two", "Section Three", "Footer"])
    #expect(sections.allSatisfy { $0.kind == .markdownHeader })
    #expect(sections.allSatisfy { $0.normalizedCharacterCount > 0 })
    #expect(abs(sections.map(\.normalizedCharacterShare).reduce(0, +) - 1.0) < 0.0001)

    let windows = SpeakSwiftly.DeepTrace.sectionWindows(
        originalText: original,
        totalDurationMS: 12000,
        totalChunkCount: 75,
    )
    #expect(windows.count == 4)
    #expect(windows.first?.estimatedStartMS == 0)
    #expect(windows.first?.estimatedStartChunk == 0)
    #expect(windows.last?.estimatedEndMS == 12000)
    #expect(windows.last?.estimatedEndChunk == 75)
    let windowsAreContiguous = zip(windows, windows.dropFirst()).allSatisfy { lhs, rhs in
        lhs.estimatedEndMS == rhs.estimatedStartMS
            && lhs.estimatedEndChunk == rhs.estimatedStartChunk
    }
    #expect(windowsAreContiguous)
}

@Test func `speech text normalization makes paths and identifiers more speakable`() async throws {
    let original = """
    Please read /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift, NSApplication.didFinishLaunchingNotification, camelCaseStuff, snake_case_stuff, and `profile?.sampleRate ?? 24000`.
    """

    let normalized = try await normalizeTextForTest(original)

    #expect(normalized.contains("gale wumbo Workspace Speak Swiftly"))
    #expect(normalized.contains("NSApplication dot did Finish Launching Notification"))
    #expect(normalized.contains("camel Case Stuff"))
    #expect(normalized.contains("snake case stuff"))
    #expect(normalized.contains("profile optional chaining sample Rate nil coalescing 24000"))
}

// MARK: - Playback Failure and Observability

@Test func `playback timeout fails only that request and worker keeps running`() async throws {
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

    let playback = PlaybackSpy(
        behavior: .throw(
            WorkerError(
                code: .audioPlaybackTimeout,
                message: "Live playback timed out after generated audio finished because the local audio player did not report drain completion within 5 seconds.",
            ),
        ),
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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)
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

    await runtime.accept(line: #"{"id":"req-2","op":"list_voice_profiles"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == true
        }
    })
}

@Test func `stderr logs use JSONL and include expanded playback metrics`() async throws {
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
        playback: PlaybackSpy(behavior: .immediate),
        residentModelLoader: { _ in makeResidentModel(chunkCount: 3) },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "resident_model_preload_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)

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
                && details["streaming_interval"] as? Double == 0.32
                && (details["startup_buffer_target_ms"] as? Int ?? 0) >= 360
                && (details["low_water_target_ms"] as? Int ?? 0) >= 140
                && (details["chunk_gap_warning_threshold_ms"] as? Int ?? 0) >= 450
                && (details["schedule_gap_warning_threshold_ms"] as? Int ?? 0) >= 180
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

@Test func `stderr logs queue depth warnings starvation and expanded durations`() async throws {
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
        playback: PlaybackSpy(behavior: .emitLowQueueThenStarve),
        residentModelLoader: { _ in makeResidentModel(chunkCount: 1) },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_rebuffer_started",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return (details["low_water_target_ms"] as? Int ?? 0) >= 140
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

@Test func `stderr logs playback warnings trace and buffer shape summaries`() async throws {
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
    let residentModel = makeResidentModel(chunkCount: 2)

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(behavior: .emitObservabilityBurst),
        residentModelLoader: { _ in residentModel },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Longer playback diagnostics check","voice_profile":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_chunk_gap_warning"
                && $0["level"] as? String == "warning"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_schedule_gap_warning"
                && $0["level"] as? String == "warning"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_rebuffer_thrash_warning"
                && $0["level"] as? String == "warning"
                && $0["request_id"] as? String == "req-1"
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            guard
                $0["event"] as? String == "playback_generation_quality_warning",
                $0["level"] as? String == "warning",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["reason"] as? String == "repeated_non_silent_window"
                && details["quality_chunk_index"] as? Int == 2
                && details["total_generated_duration_ms"] as? Int == 12000
                && details["repeated_window_similarity"] as? Double == 0.998
        }
    })
    #expect(await waitUntil {
        output.containsSystemLogEvent {
            $0.event == "playback_generation_quality_warning"
                && $0.level == .warning
                && $0.requestID == "req-1"
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
            guard
                $0["event"] as? String == "playback_trace_generation_quality_chunk",
                $0["request_id"] as? String == "req-1",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["generated_duration_ms"] as? Int == 400
                && details["total_generated_duration_ms"] as? Int == 400
                && details["non_finite_sample_count"] as? Int == 0
                && details["peak_amplitude"] as? Double == 0.31
                && details["near_silence_ratio"] as? Double == 0.04
        }
    })
    #expect(await waitUntil {
        output.containsStderrJSONObject {
            $0["event"] as? String == "playback_trace_buffer_scheduled"
                && $0["request_id"] as? String == "req-1"
        }
    })
}

@Test func `speak live passes non nil reference audio into resident generation`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        qwenConditioningStrategy: .legacyRaw,
        audioLoadRecorder: residentRecorder,
        loadedAudioSamples: .mlxNone,
        residentModelLoader: { _ in
            makeResidentModel(recorder: residentRecorder)
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })

    #expect(residentRecorder.lastRefAudioWasProvided == true)
    #expect(residentRecorder.audioLoadCallCount == 1)
}

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `speak live prepared qwen conditioning persists and reloads across runtime restarts`() async throws {
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

    let firstRecorder = ResidentModelRecorder()
    let firstRuntime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        qwenConditioningStrategy: .preparedConditioning,
        audioLoadRecorder: firstRecorder,
        loadedAudioSamples: MLXArray([Float(0.1), 0.2]).reshaped([1, 2]),
        residentModelLoader: { _ in
            makeResidentModel(recorder: firstRecorder)
        },
    )

    await firstRuntime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await firstRuntime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    let storedAfterFirstRun = try store.loadProfile(named: "default-femme")
    #expect(
        storedAfterFirstRun.qwenConditioningArtifact(
            for: .qwen3_smol,
            modelRepo: ModelFactory.qwenResidentModelRepo,
        ) != nil,
    )
    #expect(firstRecorder.prepareConditioningCallCount == 1)
    #expect(firstRecorder.conditionedGenerationCallCount == 1)
    #expect(firstRecorder.audioLoadCallCount == 1)

    let secondOutput = OutputRecorder()
    let secondRecorder = ResidentModelRecorder()
    let secondRuntime = try await makeRuntime(
        rootURL: storeRoot,
        output: secondOutput,
        playback: PlaybackSpy(),
        qwenConditioningStrategy: .preparedConditioning,
        audioLoadRecorder: secondRecorder,
        loadedAudioSamples: MLXArray([Float(0.3), 0.4]).reshaped([1, 2]),
        residentModelLoader: { _ in
            makeResidentModel(recorder: secondRecorder)
        },
    )

    await secondRuntime.start()
    #expect(await waitUntil {
        secondOutput.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await secondRuntime.accept(line: #"{"id":"req-2","op":"generate_speech","text":"Hello again","voice_profile":"default-femme"}"#)
    #expect(await waitUntil {
        secondOutput.containsJSONObject {
            $0["id"] as? String == "req-2"
                && $0["ok"] as? Bool == true
        }
    })

    #expect(secondRecorder.prepareConditioningCallCount == 0)
    #expect(secondRecorder.conditionedGenerationCallCount == 1)
    #expect(secondRecorder.audioLoadCallCount == 0)
}

#if DEBUG
@Test func `identical retained qwen generations preserve conditioning and debug fingerprints`() async throws {
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
    let residentModel = makeResidentModel(recorder: recorder, chunkCount: 2)
    _ = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3_smol,
        modelRepo: ModelFactory.qwenResidentModelRepo,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning(
            speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
            referenceSpeechCodes: MLXArray([Int32(10), 11, 12, 13]).reshaped([1, 2, 2]),
            referenceTextTokenIDs: MLXArray([Int32(101), 102, 103]).reshaped([1, 3]),
            resolvedLanguage: "English",
            codecLanguageID: 7,
        ),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        qwenConditioningStrategy: .preparedConditioning,
        residentModelLoader: { _ in residentModel },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let text = "The same retained-file request should keep the same voice conditioning."
    let firstHandle = await runtime.generate.audio(
        text: text,
        voiceProfile: "default-femme",
    )
    _ = try await firstHandle.completion()

    let secondHandle = await runtime.generate.audio(
        text: text,
        voiceProfile: "default-femme",
    )
    _ = try await secondHandle.completion()

    #expect(recorder.prepareConditioningCallCount == 0)
    #expect(recorder.conditionedGenerationCallCount == 2)
    #expect(recorder.recordedTexts.count == 2)
    if recorder.recordedTexts.count == 2 {
        #expect(recorder.recordedTexts[0] == recorder.recordedTexts[1])
    }
    #expect(output.containsSystemLogEvent { $0.event == "qwen_reference_conditioning_loaded" })
    #expect(output.containsSystemLogEvent { $0.event == "qwen_reference_conditioning_cache_hit" })

    let finishedEvents = output.recordedSystemLogEvents {
        $0.event == "qwen_generation_debug_finished"
    }
    #expect(finishedEvents.count == 2)

    let completedFingerprints = finishedEvents.compactMap { event -> (String, String, String)? in
        guard
            case let .string(outcome)? = event.details?["outcome"],
            outcome == "completed",
            case let .bool(referenceUnchanged)? = event.details?["reference_unchanged"],
            referenceUnchanged,
            case let .string(referenceFingerprint)? = event.details?["reference_fingerprint_after"],
            case let .string(tokenDigest)? = event.details?["primary_codec_token_digest"],
            case let .string(audioDigest)? = event.details?["audio_sample_digest"]
        else {
            return nil
        }

        return (referenceFingerprint, tokenDigest, audioDigest)
    }
    #expect(completedFingerprints.count == 2)
    if completedFingerprints.count == 2 {
        #expect(completedFingerprints[0].0 == completedFingerprints[1].0)
        #expect(completedFingerprints[0].1 == completedFingerprints[1].1)
        #expect(completedFingerprints[0].2 == completedFingerprints[1].2)
    }
}
#endif

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `prepared qwen conditioning is lazy per resident model repo`() async throws {
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
    _ = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3_smol,
        modelRepo: ModelFactory.qwenResidentModelRepo,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning(
            speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
            referenceSpeechCodes: MLXArray([Int32(10), 11, 12, 13]).reshaped([1, 2, 2]),
            referenceTextTokenIDs: MLXArray([Int32(101), 102, 103]).reshaped([1, 3]),
            resolvedLanguage: "English",
            codecLanguageID: 7,
        ),
    )

    let recorder = ResidentModelRecorder()
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3_BIG,
        qwenConditioningStrategy: .preparedConditioning,
        audioLoadRecorder: recorder,
        loadedAudioSamples: MLXArray([Float(0.3), 0.4]).reshaped([1, 2]),
        residentModelLoader: { _ in
            makeResidentModel(recorder: recorder)
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-17b","op":"generate_speech","text":"Hello on the larger model","voice_profile":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-17b"
                && $0["ok"] as? Bool == true
        }
    })
    #expect(await waitUntil {
        recorder.conditionedGenerationCallCount == 1
    })

    let storedAfterGeneration = try store.loadProfile(named: "default-femme")
    #expect(storedAfterGeneration.manifest.qwenConditioningArtifacts.count == 2)
    #expect(storedAfterGeneration.qwenConditioningArtifact(for: .qwen3_smol, modelRepo: ModelFactory.qwenResidentModelRepo) != nil)
    #expect(storedAfterGeneration.qwenConditioningArtifact(for: .qwen3_BIG, modelRepo: ModelFactory.qwen17B8BitResidentModelRepo) != nil)
    #expect(recorder.prepareConditioningCallCount == 1)
    #expect(recorder.audioLoadCallCount == 1)
}

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `create profile prepares qwen conditioning for selected resident model`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let recorder = ResidentModelRecorder()
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3_BIG,
        qwenConditioningStrategy: .preparedConditioning,
        audioLoadRecorder: recorder,
        loadedAudioSamples: MLXArray([Float(0.3), 0.4]).reshaped([1, 2]),
        residentModelLoader: { _ in
            makeResidentModel(recorder: recorder)
        },
        profileModelLoader: {
            makeProfileModel()
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
        line: #"{"id":"req-create","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"Warm and bright"}"#,
    )
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-create"
                && $0["ok"] as? Bool == true
        }
    })

    let store = try makeProfileStore(rootURL: storeRoot)
    let storedProfile = try store.loadProfile(named: "bright-guide")
    #expect(storedProfile.qwenConditioningArtifact(for: .qwen3_BIG, modelRepo: ModelFactory.qwen17B8BitResidentModelRepo) != nil)
    #expect(recorder.prepareConditioningCallCount == 1)
    #expect(recorder.audioLoadCallCount == 1)
}

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `reroll profile prepares qwen conditioning for selected resident model`() async throws {
    let output = OutputRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "bright-guide",
        vibe: .femme,
        modelRepo: ModelFactory.profileModelRepo,
        voiceDescription: "Warm and bright.",
        sourceText: "Hello there",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )
    _ = try store.storeQwenConditioningArtifact(
        named: "bright-guide",
        backend: .qwen3_smol,
        modelRepo: ModelFactory.qwenResidentModelRepo,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning(
            speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
            referenceSpeechCodes: MLXArray([Int32(10), 11, 12, 13]).reshaped([1, 2, 2]),
            referenceTextTokenIDs: MLXArray([Int32(101), 102, 103]).reshaped([1, 3]),
            resolvedLanguage: "English",
            codecLanguageID: 7,
        ),
    )

    let recorder = ResidentModelRecorder()
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        speechBackend: .qwen3_BIG,
        qwenConditioningStrategy: .preparedConditioning,
        audioLoadRecorder: recorder,
        loadedAudioSamples: MLXArray([Float(0.3), 0.4]).reshaped([1, 2]),
        residentModelLoader: { _ in
            makeResidentModel(recorder: recorder)
        },
        profileModelLoader: {
            makeProfileModel()
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let rerollID = await runtime.voices.reroll("bright-guide").id
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == rerollID
                && $0["ok"] as? Bool == true
        }
    })

    let rerolledProfile = try store.loadProfile(named: "bright-guide")
    #expect(rerolledProfile.manifest.qwenConditioningArtifacts.count == 1)
    #expect(rerolledProfile.qwenConditioningArtifact(for: .qwen3_smol, modelRepo: ModelFactory.qwenResidentModelRepo) != nil)
    #expect(rerolledProfile.qwenConditioningArtifact(for: .qwen3_BIG, modelRepo: ModelFactory.qwen17B8BitResidentModelRepo) != nil)
    #expect(recorder.prepareConditioningCallCount == 2)
    #expect(recorder.audioLoadCallCount == 2)
}

@Test(
    .enabled(
        if: mlxConditioningPersistenceTestsEnabled(),
        "This persistence round-trip test is opt-in and requires SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1.",
    ),
) func `speak live legacy raw strategy ignores prepared qwen conditioning artifacts`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )
    _ = try store.storeQwenConditioningArtifact(
        named: "default-femme",
        backend: .qwen3_smol,
        modelRepo: ModelFactory.residentModelRepo(for: .qwen3_smol),
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning(
            speakerEmbedding: MLXArray([Float(0.25), 0.5]).reshaped([1, 2]),
            referenceSpeechCodes: MLXArray([Int32(10), 11, 12, 13]).reshaped([1, 2, 2]),
            referenceTextTokenIDs: MLXArray([Int32(101), 102, 103]).reshaped([1, 3]),
            resolvedLanguage: "English",
            codecLanguageID: 7,
        ),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        qwenConditioningStrategy: .legacyRaw,
        audioLoadRecorder: residentRecorder,
        loadedAudioSamples: MLXArray([Float(0.1), 0.2]).reshaped([1, 2]),
        residentModelLoader: { _ in
            makeResidentModel(recorder: residentRecorder)
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    #expect(residentRecorder.prepareConditioningCallCount == 0)
    #expect(residentRecorder.conditionedGenerationCallCount == 0)
    #expect(residentRecorder.audioLoadCallCount == 1)
    #expect(residentRecorder.lastRefAudioWasProvided == true)
    #expect(residentRecorder.lastRefText == "Reference transcript")
}

@Test func `speak live normalizes code heavy markdown before resident generation`() async throws {
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
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(),
        audioLoadRecorder: residentRecorder,
        residentModelLoader: { _ in
            makeResidentModel(recorder: residentRecorder)
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
        line: #"""
        {"id":"req-1","op":"generate_speech","text":"Please read `fooBar()` and this block:\n```swift\nlet greeting = user?.displayName ?? \"friend\"\n```","voice_profile":"default-femme"}
        """#,
    )

    #expect(await waitUntil { residentRecorder.lastText != nil })

    let normalized = residentRecorder.recordedTexts.joined(separator: " ")
    #expect(!normalized.contains("```"))
    #expect(!normalized.contains("`"))
    #expect(normalized.contains("foo Bar"))
    #expect(normalized.contains("Code sample."))
    #expect(normalized.contains("optional chaining"))
    #expect(normalized.contains("nil coalescing"))
}

@Test func `speak live applies stored text profile before resident generation`() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let residentRecorder = ResidentModelRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel(recorder: residentRecorder) },
    )

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
    )

    let logs = try await runtime.normalizer.profiles.create(name: "Logs")
    _ = try await runtime.normalizer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement("stderr", with: "standard error"),
        toProfile: logs.id,
    )
    _ = try await runtime.normalizer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement(
            "snake case stuff",
            with: "settings token",
            during: .afterBuiltIns,
        ),
        toProfile: logs.id,
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
        {"id":"req-1","op":"generate_speech","text":"Please read stderr and snake_case_stuff once.","voice_profile":"default-femme","text_profile":"logs"}
        """#,
    )

    #expect(await waitUntil { residentRecorder.lastText != nil })

    let normalized = try #require(residentRecorder.lastText)
    #expect(normalized.contains("standard error"))
    #expect(normalized.contains("settings token"))
}

@Test func `speak live lets SpeakSwiftly detect source before resident generation`() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let residentRecorder = ResidentModelRecorder()
    let storeRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: playback,
        residentModelLoader: { _ in makeResidentModel(recorder: residentRecorder) },
    )

    let store = try makeProfileStore(rootURL: storeRoot)
    _ = try store.createProfile(
        profileName: "default-femme",
        modelRepo: "test-model",
        voiceDescription: "Warm and bright.",
        sourceText: "Reference transcript",
        sampleRate: 24000,
        canonicalAudioData: Data([0x01, 0x02]),
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
        {"id":"req-source","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","voice_profile":"default-femme"}
        """#,
    )

    #expect(await waitUntil { residentRecorder.lastText != nil })

    let normalized = try #require(residentRecorder.lastText)
    #expect(normalized.contains("struct Worker Runtime"))
    #expect(normalized.contains("sample Rate"))
    #expect(normalized.contains("sample Rate: Int"))
}

@Test func `live speech chunk planner groups three sentences first and two sentences thereafter`() {
    let text = """
    Please read this first sentence slowly and clearly for testing.
    Please read this second sentence slowly and clearly for testing.
    Please read this third sentence slowly and clearly for testing.
    Please read this fourth sentence slowly and clearly for testing.
    """

    let chunks = LiveSpeechChunkPlanner.chunks(for: text)

    #expect(chunks.count == 2)
    #expect(chunks.map(\.text) == [
        "Please read this first sentence slowly and clearly for testing. Please read this second sentence slowly and clearly for testing. Please read this third sentence slowly and clearly for testing.",
        "Please read this fourth sentence slowly and clearly for testing.",
    ])
    #expect(chunks[0].wordCount > chunks[1].wordCount)
}

@Test func `live speech chunk planner keeps oversized sentences intact when chunking by sentence`() {
    let text = longPlaybackPlannerFixtureText

    let chunks = LiveSpeechChunkPlanner.chunks(for: text)

    #expect(chunks.count == 1)
    #expect(chunks.map(\.text) == [
        "Hello from the real resident SpeakSwiftly playback path. This end to end test now uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.",
    ])
    #expect(chunks[0].wordCount > 0)
}

@Test func `qwen live speech chunk planner groups four paragraphs per chunk`() {
    let text = """
    Please read this first paragraph slowly and clearly for testing. It should stay paired with the next paragraph.

    Please read this second paragraph slowly and clearly for testing. It should stay paired with the first paragraph.

    Please read this third paragraph slowly and clearly for testing. It should stay grouped with the first three paragraphs.

    Please read this fourth paragraph slowly and clearly for testing. It should stay grouped with the first three paragraphs.

    Please read this fifth paragraph slowly and clearly for testing. It should stay grouped with the fourth paragraph.
    """

    let chunks = LiveSpeechChunkPlanner.chunks(for: text, strategy: .smartParagraphGroups())

    #expect(chunks.count == 2)
    #expect(chunks.map(\.text) == [
        """
        Please read this first paragraph slowly and clearly for testing. It should stay paired with the next paragraph.

        Please read this second paragraph slowly and clearly for testing. It should stay paired with the first paragraph.

        Please read this third paragraph slowly and clearly for testing. It should stay grouped with the first three paragraphs.

        Please read this fourth paragraph slowly and clearly for testing. It should stay grouped with the first three paragraphs.
        """,
        """
        Please read this fifth paragraph slowly and clearly for testing. It should stay grouped with the fourth paragraph.
        """,
    ])
    #expect(chunks[0].segmentation == .paragraphGroup)
    #expect(chunks[1].segmentation == .punctuationBoundary)
}

@Test func `qwen live speech chunk planner falls back at punctuation boundaries when a paragraph is oversized`() {
    let text = """
    Please read this first sentence slowly and clearly for testing. Please read this second sentence slowly and clearly for testing. Please read this third sentence slowly and clearly for testing. Please read this fourth sentence slowly and clearly for testing. Please read this fifth sentence slowly and clearly for testing. Please read this sixth sentence slowly and clearly for testing.
    """

    let chunks = LiveSpeechChunkPlanner.chunks(
        for: text,
        strategy: .smartParagraphGroups(targetParagraphCount: 3, softCharacterLimit: 180),
    )

    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.text.last == "." })
    #expect(chunks.allSatisfy { $0.segmentation == .punctuationBoundary || $0.segmentation == .forcedBreak })
}

@Test func `qwen pre-model text chunking is opt in for live playback`() async throws {
    let output = OutputRecorder()
    let playback = PlaybackSpy()
    let residentRecorder = ResidentModelRecorder()
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
        audioLoadRecorder: residentRecorder,
        residentModelLoader: { _ in
            makeResidentModel(recorder: residentRecorder, chunkCount: 1)
        },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    let text = """
    Please read this first paragraph slowly and clearly for testing. It should stay grouped with the next paragraph.

    Please read this second paragraph slowly and clearly for testing. It should stay grouped with the first paragraph.

    Please read this third paragraph slowly and clearly for testing. It should stay grouped with the fourth paragraph.

    Please read this fourth paragraph slowly and clearly for testing. It should stay grouped with the third paragraph.

    Please read this fifth paragraph slowly and clearly for testing. It should force live playback to use a second Qwen generation call.
    """
    let escapedText = text.replacingOccurrences(of: "\n", with: "\\n")
    let expectedLiveChunkTexts = LiveSpeechChunkPlanner.chunks(
        for: text,
        strategy: .smartParagraphGroups(),
    )
    .map(\.text)
    #expect(expectedLiveChunkTexts.count > 1)

    await runtime.accept(
        line: """
        {"id":"req-qwen-live","op":"generate_speech","text":"\(escapedText)","voice_profile":"default-femme"}
        """,
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-qwen-live"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })
    #expect(await waitUntil { residentRecorder.recordedTexts.count == 1 })
    #expect(try #require(residentRecorder.recordedTexts.last).contains("first paragraph"))
    #expect(try #require(residentRecorder.recordedTexts.last).contains("fifth paragraph"))

    await runtime.accept(
        line: """
        {"id":"req-qwen-file","op":"generate_audio_file","text":"\(escapedText)","voice_profile":"default-femme"}
        """,
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-qwen-file"
                && $0["ok"] as? Bool == true
        }
    })
    #expect(await waitUntil { residentRecorder.recordedTexts.count == 2 })
    #expect(try #require(residentRecorder.recordedTexts.last).contains("first paragraph"))
    #expect(try #require(residentRecorder.recordedTexts.last).contains("fifth paragraph"))

    await runtime.accept(
        line: """
        {"id":"req-qwen-live-chunked","op":"generate_speech","text":"\(escapedText)","voice_profile":"default-femme","qwen_pre_model_text_chunking":true}
        """,
    )

    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-qwen-live-chunked"
                && $0["event"] as? String == "progress"
                && $0["stage"] as? String == "preroll_ready"
        }
    })
    #expect(await waitUntil { residentRecorder.recordedTexts.count == 2 + expectedLiveChunkTexts.count })
    #expect(Array(residentRecorder.recordedTexts.suffix(expectedLiveChunkTexts.count)) == expectedLiveChunkTexts)
}

// MARK: - Sample Shaping

@Test func `shape playback samples smooths boundary jumps and sanitizes invalid values`() {
    let shaped = shapePlaybackSamples(
        [Float.nan, 1.8, -1.6, 0.25],
        sampleRate: 24000,
        previousTrailingSample: 0.35,
        applyFadeIn: false,
    )

    #expect(shaped.count == 4)
    #expect(shaped.allSatisfy { $0.isFinite && $0 >= -1 && $0 <= 1 })
    #expect(abs(shaped[0] - 0.35) < 0.000_1)
}
