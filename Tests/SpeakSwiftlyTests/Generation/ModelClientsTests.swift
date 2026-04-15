import Foundation
@preconcurrency import MLX
import MLXAudioTTS
@testable import SpeakSwiftly
import Testing
import TextForSpeech

// MARK: - Adaptive Playback Thresholds

@Test func `adaptive playback thresholds seed from text complexity classes`() {
    let compact = PlaybackThresholdController(text: "Hello there.").thresholds
    let balanced = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
    ).thresholds
    let extended = PlaybackThresholdController(
        text: String(
            repeating: "This is a deliberately long spoken paragraph used to seed playback buffering from length alone. ",
            count: 9,
        ),
    ).thresholds

    #expect(compact.complexityClass == .compact)
    #expect(balanced.complexityClass == .balanced)
    #expect(extended.complexityClass == .extended)
    #expect(compact.startupBufferTargetMS < balanced.startupBufferTargetMS)
    #expect(balanced.startupBufferTargetMS < extended.startupBufferTargetMS)
    #expect(compact.resumeBufferTargetMS < balanced.resumeBufferTargetMS)
    #expect(balanced.resumeBufferTargetMS < extended.resumeBufferTargetMS)
}

@Test func `adaptive playback thresholds start from warmup biased targets`() {
    let compact = PlaybackThresholdController(text: "Hello there.").thresholds
    let balanced = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
    ).thresholds
    let extended = PlaybackThresholdController(
        text: String(
            repeating: "This is a deliberately long spoken paragraph used to seed playback buffering from length alone. ",
            count: 9,
        ),
    ).thresholds

    #expect(compact.startupBufferTargetMS == 480)
    #expect(compact.lowWaterTargetMS == 220)
    #expect(compact.resumeBufferTargetMS == 540)
    #expect(balanced.startupBufferTargetMS == 720)
    #expect(balanced.lowWaterTargetMS == 340)
    #expect(balanced.resumeBufferTargetMS == 800)
    #expect(extended.startupBufferTargetMS == 13120)
    #expect(extended.lowWaterTargetMS == 5000)
    #expect(extended.resumeBufferTargetMS == 16480)
}

@Test func `first drained live marvis tuning raises compact and balanced warmup floors`() {
    let compact = PlaybackThresholdController(
        text: "Hello there.",
        tuningProfile: .firstDrainedLiveMarvis,
    ).thresholds
    let balanced = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
        tuningProfile: .firstDrainedLiveMarvis,
    ).thresholds
    let extended = PlaybackThresholdController(
        text: String(
            repeating: "This is a deliberately long spoken paragraph used to seed playback buffering from length alone. ",
            count: 9,
        ),
        tuningProfile: .firstDrainedLiveMarvis,
    ).thresholds

    #expect(compact.startupBufferTargetMS == 1440)
    #expect(compact.lowWaterTargetMS == 640)
    #expect(compact.resumeBufferTargetMS == 1700)
    #expect(balanced.startupBufferTargetMS == 2320)
    #expect(balanced.lowWaterTargetMS == 1040)
    #expect(balanced.resumeBufferTargetMS == 2700)
    #expect(extended.startupBufferTargetMS == 13120)
    #expect(extended.lowWaterTargetMS == 5000)
    #expect(extended.resumeBufferTargetMS == 16480)
}

@Test func `adaptive playback thresholds ignore content shape when lengths match`() {
    let plainText = String(repeating: "Please explain this clearly. ", count: 8)
    let codeishSeed = """
    /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift
    user?.displayName ?? defaults["voice_profile"]
    NSApplication.didFinishLaunchingNotification
    """
    let paddedCodeishText = codeishSeed + String(repeating: ".", count: max(0, plainText.count - codeishSeed.count))

    let plain = PlaybackThresholdController(text: plainText).thresholds
    let codeish = PlaybackThresholdController(text: paddedCodeishText).thresholds

    #expect(plain.complexityClass == codeish.complexityClass)
    #expect(plain.startupBufferTargetMS == codeish.startupBufferTargetMS)
    #expect(plain.lowWaterTargetMS == codeish.lowWaterTargetMS)
    #expect(plain.resumeBufferTargetMS == codeish.resumeBufferTargetMS)
    #expect(plain.chunkGapWarningMS == codeish.chunkGapWarningMS)
    #expect(plain.scheduleGapWarningMS == codeish.scheduleGapWarningMS)
}

@Test func `adaptive playback thresholds raise targets for slow cadence and starvation`() {
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
    #expect(starved.resumeBufferTargetMS >= adapted.resumeBufferTargetMS)
    #expect(starved.startupBufferTargetMS >= starved.resumeBufferTargetMS)
    #expect(starved.lowWaterTargetMS >= adapted.lowWaterTargetMS)
}

@Test func `adaptive playback thresholds raise targets for repeated rebuffers`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this file path and code-heavy explanation carefully.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    let adapted = controller.thresholds
    controller.recordRebuffer()
    let afterFirstRebuffer = controller.thresholds
    controller.recordRebuffer()
    let afterSecondRebuffer = controller.thresholds
    controller.recordRebuffer()
    let afterThirdRebuffer = controller.thresholds

    #expect(afterFirstRebuffer == adapted)
    #expect(afterSecondRebuffer.startupBufferTargetMS > adapted.startupBufferTargetMS)
    #expect(afterSecondRebuffer.lowWaterTargetMS > adapted.lowWaterTargetMS)
    #expect(afterSecondRebuffer.resumeBufferTargetMS > adapted.resumeBufferTargetMS)
    #expect(afterSecondRebuffer.chunkGapWarningMS >= adapted.chunkGapWarningMS)
    #expect(afterSecondRebuffer.scheduleGapWarningMS >= adapted.scheduleGapWarningMS)
    #expect(afterThirdRebuffer.resumeBufferTargetMS > afterSecondRebuffer.resumeBufferTargetMS)
}

@Test func `first drained live marvis tuning escalates on the first rebuffer`() {
    var controller = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
        tuningProfile: .firstDrainedLiveMarvis,
    )

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    let adapted = controller.thresholds
    controller.recordRebuffer()
    let afterFirstRebuffer = controller.thresholds

    #expect(afterFirstRebuffer.startupBufferTargetMS > adapted.startupBufferTargetMS)
    #expect(afterFirstRebuffer.lowWaterTargetMS > adapted.lowWaterTargetMS)
    #expect(afterFirstRebuffer.resumeBufferTargetMS > adapted.resumeBufferTargetMS)
}

@Test func `adaptive playback thresholds keep escalated rebuffer targets across later chunks`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this code-heavy diagnostic trace.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/PlaybackController.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    controller.recordRebuffer()
    controller.recordRebuffer()
    let escalated = controller.thresholds

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 182)
    }

    let afterMoreChunks = controller.thresholds

    #expect(afterMoreChunks.startupBufferTargetMS >= escalated.startupBufferTargetMS)
    #expect(afterMoreChunks.lowWaterTargetMS >= escalated.lowWaterTargetMS)
    #expect(afterMoreChunks.resumeBufferTargetMS >= escalated.resumeBufferTargetMS)
    #expect(afterMoreChunks.chunkGapWarningMS >= escalated.chunkGapWarningMS)
    #expect(afterMoreChunks.scheduleGapWarningMS >= escalated.scheduleGapWarningMS)
}

@Test func `first drained live marvis tuning keeps stronger recovery floors during later chunks`() {
    var controller = PlaybackThresholdController(
        text: String(repeating: "This is ordinary spoken prose for playback buffering. ", count: 7),
        tuningProfile: .firstDrainedLiveMarvis,
    )

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 205)
    }

    controller.recordRebuffer()
    let escalated = controller.thresholds

    for _ in 0..<6 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 190)
    }

    let afterMoreChunks = controller.thresholds

    #expect(controller.phase == .recovery || controller.phase == .steady)
    #expect(afterMoreChunks.startupBufferTargetMS >= 1660)
    #expect(afterMoreChunks.lowWaterTargetMS >= 760)
    #expect(afterMoreChunks.resumeBufferTargetMS >= 2000)
    #expect(afterMoreChunks.startupBufferTargetMS >= escalated.startupBufferTargetMS)
    #expect(afterMoreChunks.lowWaterTargetMS >= escalated.lowWaterTargetMS)
    #expect(afterMoreChunks.resumeBufferTargetMS >= escalated.resumeBufferTargetMS)
}

@Test func `adaptive playback thresholds leave warmup after stable chunk cadence`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this code-heavy diagnostic trace.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/PlaybackController.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    #expect(controller.phase == .warmup)

    for _ in 0..<12 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 182)
    }

    #expect(controller.phase == .steady)
}

@Test func `adaptive playback thresholds stay in warmup while early cadence trails realtime playback`() {
    var controller = PlaybackThresholdController(
        text: String(
            repeating: "This is ordinary spoken prose for playback buffering. ",
            count: 7,
        ),
    )

    #expect(controller.phase == .warmup)

    for _ in 0..<7 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 250)
    }

    #expect(controller.phase == .warmup)
    #expect(controller.thresholds.startupBufferTargetMS >= 1600)
    #expect(controller.thresholds.lowWaterTargetMS >= 600)
    #expect(controller.thresholds.resumeBufferTargetMS >= 1400)
}

@Test func `adaptive playback thresholds enter recovery after rebuffer and return to steady after stable chunks`() {
    var controller = PlaybackThresholdController(
        text: """
        Please read this code-heavy diagnostic trace.
        /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/PlaybackController.swift
        let greeting = user?.displayName ?? "friend"
        """,
    )

    for _ in 0..<12 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 182)
    }
    #expect(controller.phase == .steady)

    controller.recordRebuffer()
    #expect(controller.phase == .recovery)

    for _ in 0..<8 {
        controller.recordChunk(durationMS: 160, interChunkGapMS: 184)
    }

    #expect(controller.phase == .steady)
}

// MARK: - Runtime Playback Integration

@Test func `speak live uses stored profile data waits for playback drain and reuses playback controller`() async throws {
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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)
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

    await runtime.accept(line: #"{"id":"req-2","op":"generate_speech","text":"Hello again","profile_name":"default-femme"}"#)
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

// MARK: - Deep Trace and Normalization

@Test func `speech text deep trace features capture code heavy and weird text shapes`() {
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

    let normalized = TextForSpeech.Normalize.text(original)
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

@Test func `speech text normalization makes paths and identifiers more speakable`() {
    let original = """
    Please read /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift, NSApplication.didFinishLaunchingNotification, camelCaseStuff, snake_case_stuff, and `profile?.sampleRate ?? 24000`.
    """

    let normalized = TextForSpeech.Normalize.text(original)

    #expect(normalized.contains("gale wumbo slash Workspace slash Speak Swiftly"))
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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)
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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)

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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)

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

    let runtime = try await makeRuntime(
        rootURL: storeRoot,
        output: output,
        playback: PlaybackSpy(behavior: .emitObservabilityBurst),
        residentModelLoader: { _ in makeResidentModel(chunkCount: 2) },
    )

    await runtime.start()
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["event"] as? String == "worker_status"
                && $0["stage"] as? String == "resident_model_ready"
        }
    })

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Longer playback diagnostics check","profile_name":"default-femme"}"#)

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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)

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

    await firstRuntime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)
    #expect(await waitUntil {
        output.containsJSONObject {
            $0["id"] as? String == "req-1"
                && $0["ok"] as? Bool == true
        }
    })

    let storedAfterFirstRun = try store.loadProfile(named: "default-femme")
    #expect(storedAfterFirstRun.qwenConditioningArtifact(for: .qwen3) != nil)
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

    await secondRuntime.accept(line: #"{"id":"req-2","op":"generate_speech","text":"Hello again","profile_name":"default-femme"}"#)
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
        backend: .qwen3,
        modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
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

    await runtime.accept(line: #"{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}"#)
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
        {"id":"req-1","op":"generate_speech","text":"Please read `fooBar()` and this block:\n```swift\nlet greeting = user?.displayName ?? \"friend\"\n```","profile_name":"default-femme"}
        """#,
    )

    #expect(await waitUntil { residentRecorder.lastText != nil })

    let normalized = try #require(residentRecorder.lastText)
    #expect(!normalized.contains("```"))
    #expect(!normalized.contains("`"))
    #expect(normalized.contains("foo Bar open parenthesis close parenthesis"))
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

    try await runtime.normalizer.profiles.store(
        TextForSpeech.Profile(
            id: "logs",
            name: "Logs",
            replacements: [
                TextForSpeech.Replacement("stderr", with: "standard error"),
                TextForSpeech.Replacement(
                    "snake case stuff",
                    with: "settings token",
                    during: .afterBuiltIns,
                ),
            ],
        ),
    )
    await runtime.start()

    await runtime.accept(
        line: #"""
        {"id":"req-1","op":"generate_speech","text":"Please read stderr and snake_case_stuff once.","profile_name":"default-femme","text_profile_name":"logs","text_format":"plain_text"}
        """#,
    )

    #expect(await waitUntil { residentRecorder.lastText != nil })

    let normalized = try #require(residentRecorder.lastText)
    #expect(normalized.contains("standard error"))
    #expect(normalized.contains("settings token"))
}

@Test func `speak live uses explicit whole source lane before resident generation`() async throws {
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

    await runtime.accept(
        line: #"""
        {"id":"req-source","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}
        """#,
    )

    #expect(await waitUntil { residentRecorder.lastText != nil })

    let normalized = try #require(residentRecorder.lastText)
    #expect(normalized.contains("open brace"))
    #expect(normalized.contains("sample Rate"))
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
