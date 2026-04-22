import Foundation
@testable import SpeakSwiftly
import Testing
import TextForSpeech

// MARK: - Request Decoding

@Test func `decodes speak live request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"generate_speech","text":"Hello","profile_name":"default-femme"}"#)

    #expect(
        request == .queueSpeech(
            id: "req-1",
            text: "Hello",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            inputTextContext: nil,
            requestContext: nil,
        ),
    )
}

@Test func `decodes speak file request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-file","op":"generate_audio_file","text":"Hello","profile_name":"default-femme"}"#,
    )

    #expect(
        request == .queueSpeech(
            id: "req-file",
            text: "Hello",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .file,
            inputTextContext: nil,
            requestContext: nil,
        ),
    )
}

@Test func `decodes speak batch request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-batch","op":"generate_batch","profile_name":"default-femme","items":[{"text":"First file"},{"artifact_id":"custom-artifact","text":"Second file","text_profile_id":"logs","source_format":"swift_source"}]}"#,
    )

    #expect(
        request == .queueBatch(
            id: "req-batch",
            profileName: "default-femme",
            items: [
                SpeakSwiftly.GenerationJobItem(
                    artifactID: "req-batch-artifact-1",
                    text: "First file",
                    textProfile: nil,
                    inputTextContext: nil,
                    requestContext: nil,
                ),
                SpeakSwiftly.GenerationJobItem(
                    artifactID: "custom-artifact",
                    text: "Second file",
                    textProfile: "logs",
                    inputTextContext: .init(sourceFormat: .swift),
                    requestContext: nil,
                ),
            ],
        ),
    )
}

@Test func `decodes speak live request with text context and profile`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-1","op":"generate_speech","text":"Hello","profile_name":"default-femme","text_profile_id":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}"#,
    )

    #expect(
        request == .queueSpeech(
            id: "req-1",
            text: "Hello",
            profileName: "default-femme",
            textProfileID: "logs",
            jobType: .live,
            inputTextContext: .init(
                context: TextForSpeech.Context(
                    cwd: "/Users/galew/Workspace/SpeakSwiftly",
                    repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
                    textFormat: .cli,
                ),
                sourceFormat: nil,
            ),
            requestContext: nil,
        ),
    )
}

@Test func `decodes speak live request with nested source format`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-embedded","op":"generate_speech","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}"#,
    )

    #expect(
        request == .queueSpeech(
            id: "req-embedded",
            text: "```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            inputTextContext: .init(
                context: TextForSpeech.Context(
                    textFormat: .markdown,
                    nestedSourceFormat: .swift,
                ),
                sourceFormat: nil,
            ),
            requestContext: nil,
        ),
    )
}

@Test func `decodes speak live request with whole source format`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-source","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}"#,
    )

    #expect(
        request == .queueSpeech(
            id: "req-source",
            text: "struct WorkerRuntime { let sampleRate: Int }",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            inputTextContext: .init(sourceFormat: .swift),
            requestContext: nil,
        ),
    )
}

@Test func `decodes speak live request with request context without attributes`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-context","op":"generate_speech","text":"Hello","voice_profile":"default-femme","request_context":{"source":"status_panel","app":"SpeakSwiftlyOperator","project":"SpeakSwiftly"}} "#,
    )

    #expect(
        request == .queueSpeech(
            id: "req-context",
            text: "Hello",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            inputTextContext: nil,
            requestContext: .init(
                source: "status_panel",
                app: "SpeakSwiftlyOperator",
                project: "SpeakSwiftly",
            ),
        ),
    )
}

@Test func `decodes legacy whole source text format as source lane`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-legacy-source","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","text_format":"swift_source"}"#,
    )

    #expect(
        request == .queueSpeech(
            id: "req-legacy-source",
            text: "struct WorkerRuntime { let sampleRate: Int }",
            profileName: "default-femme",
            textProfileID: nil,
            jobType: .live,
            inputTextContext: .init(sourceFormat: .swift),
            requestContext: nil,
        ),
    )
}

@Test func `decodes create profile request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-2","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello","vibe":"femme","voice_description":"Warm and bright","output_path":"./voice.wav"}"#,
    )

    #expect(
        request == .createProfile(
            id: "req-2",
            profileName: "bright-guide",
            text: "Hello",
            vibe: .femme,
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav",
            cwd: nil,
        ),
    )
}

@Test func `decodes create profile request with caller working directory`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-2b","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello","vibe":"femme","voice_description":"Warm and bright","output_path":"./voice.wav","cwd":"/tmp/export-base"}"#,
    )

    #expect(
        request == .createProfile(
            id: "req-2b",
            profileName: "bright-guide",
            text: "Hello",
            vibe: .femme,
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav",
            cwd: "/tmp/export-base",
        ),
    )
}

@Test func `decodes create clone request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-clone","op":"create_voice_profile_from_audio","profile_name":"ghost-copy","reference_audio_path":"./voice.m4a","vibe":"masc","transcript":"Hello from imported audio"}"#,
    )

    #expect(
        request == .createClone(
            id: "req-clone",
            profileName: "ghost-copy",
            referenceAudioPath: "./voice.m4a",
            vibe: .masc,
            transcript: "Hello from imported audio",
            cwd: nil,
        ),
    )
}

@Test func `decodes create clone request with caller working directory`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-clone-cwd","op":"create_voice_profile_from_audio","profile_name":"ghost-copy","reference_audio_path":"./voice.m4a","vibe":"masc","transcript":"Hello from imported audio","cwd":"file:///tmp/clone-base"}"#,
    )

    #expect(
        request == .createClone(
            id: "req-clone-cwd",
            profileName: "ghost-copy",
            referenceAudioPath: "./voice.m4a",
            vibe: .masc,
            transcript: "Hello from imported audio",
            cwd: "file:///tmp/clone-base",
        ),
    )
}

@Test func `decodes list profiles request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-3","op":"list_voice_profiles"}"#)
    #expect(request == .listProfiles(id: "req-3"))
}

@Test func `decodes rename profile request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-rename","op":"update_voice_profile_name","profile_name":"bright-guide","new_profile_name":"clear-guide"}"#,
    )
    #expect(request == .renameProfile(id: "req-rename", profileName: "bright-guide", newProfileName: "clear-guide"))
}

@Test func `decodes reroll profile request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-reroll","op":"reroll_voice_profile","profile_name":"bright-guide"}"#,
    )
    #expect(request == .rerollProfile(id: "req-reroll", profileName: "bright-guide"))
}

@Test func `decodes generated file requests`() throws {
    let file = try WorkerRequest.decode(
        from: #"{"id":"req-generated-file","op":"get_generated_file","artifact_id":"req-file"}"#,
    )
    #expect(file == .generatedFile(id: "req-generated-file", artifactID: "req-file"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-generated-files","op":"list_generated_files"}"#)
    #expect(list == .generatedFiles(id: "req-generated-files"))

    let batch = try WorkerRequest.decode(
        from: #"{"id":"req-generated-batch","op":"get_generated_batch","batch_id":"batch-job-1"}"#,
    )
    #expect(batch == .generatedBatch(id: "req-generated-batch", batchID: "batch-job-1"))

    let batchList = try WorkerRequest.decode(from: #"{"id":"req-generated-batches","op":"list_generated_batches"}"#)
    #expect(batchList == .generatedBatches(id: "req-generated-batches"))
}

@Test func `decodes generation job requests`() throws {
    let job = try WorkerRequest.decode(
        from: #"{"id":"req-generation-job","op":"get_generation_job","job_id":"job-file-1"}"#,
    )
    #expect(job == .generationJob(id: "req-generation-job", jobID: "job-file-1"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-generation-jobs","op":"list_generation_jobs"}"#)
    #expect(list == .generationJobs(id: "req-generation-jobs"))

    let expire = try WorkerRequest.decode(
        from: #"{"id":"req-expire-job","op":"expire_generation_job","job_id":"job-file-1"}"#,
    )
    #expect(expire == .expireGenerationJob(id: "req-expire-job", jobID: "job-file-1"))
}

@Test func `decodes remove profile request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-4","op":"delete_voice_profile","profile_name":"bright-guide"}"#)
    #expect(request == .removeProfile(id: "req-4", profileName: "bright-guide"))
}

@Test func `decodes text profile read requests`() throws {
    let active = try WorkerRequest.decode(from: #"{"id":"req-text-active","op":"get_active_text_profile"}"#)
    #expect(active == .textProfileActive(id: "req-text-active"))

    let style = try WorkerRequest.decode(from: #"{"id":"req-text-style","op":"get_active_text_profile_style"}"#)
    #expect(style == .activeTextProfileStyle(id: "req-text-style"))

    let styles = try WorkerRequest.decode(from: #"{"id":"req-text-styles","op":"list_text_profile_styles"}"#)
    #expect(styles == .textProfileStyleOptions(id: "req-text-styles"))

    let named = try WorkerRequest.decode(
        from: #"{"id":"req-text-one","op":"get_text_profile","text_profile_id":"logs"}"#,
    )
    #expect(named == .textProfile(id: "req-text-one", profileID: "logs"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-text-list","op":"list_text_profiles"}"#)
    #expect(list == .textProfiles(id: "req-text-list"))

    let effective = try WorkerRequest.decode(from: #"{"id":"req-text-effective","op":"get_effective_text_profile"}"#)
    #expect(effective == .textProfileEffective(id: "req-text-effective"))

    let persistence = try WorkerRequest.decode(from: #"{"id":"req-text-persistence","op":"get_text_profile_persistence"}"#)
    #expect(persistence == .textProfilePersistence(id: "req-text-persistence"))
}

@Test func `decodes text profile mutation requests`() throws {
    let setStyle = try WorkerRequest.decode(
        from: #"{"id":"req-text-style-set","op":"set_active_text_profile_style","text_profile_style":"compact"}"#,
    )
    #expect(
        setStyle == .setActiveTextProfileStyle(
            id: "req-text-style-set",
            style: .compact,
        ),
    )

    let create = try WorkerRequest.decode(
        from: #"{"id":"req-text-create","op":"create_text_profile","profile_name":"Logs"}"#,
    )
    #expect(create == .createTextProfile(id: "req-text-create", profileName: "Logs"))

    let rename = try WorkerRequest.decode(
        from: #"{"id":"req-text-rename","op":"update_text_profile_name","text_profile_id":"logs","new_profile_name":"Ops Logs"}"#,
    )
    #expect(rename == .renameTextProfile(id: "req-text-rename", profileID: "logs", profileName: "Ops Logs"))

    let setActive = try WorkerRequest.decode(
        from: #"{"id":"req-text-set-active","op":"set_active_text_profile","text_profile_id":"logs"}"#,
    )
    #expect(setActive == .setActiveTextProfile(id: "req-text-set-active", profileID: "logs"))

    let delete = try WorkerRequest.decode(
        from: #"{"id":"req-text-delete","op":"delete_text_profile","text_profile_id":"logs"}"#,
    )
    #expect(delete == .deleteTextProfile(id: "req-text-delete", profileID: "logs"))

    let factoryReset = try WorkerRequest.decode(
        from: #"{"id":"req-text-factory-reset","op":"factory_reset_text_profiles"}"#,
    )
    #expect(factoryReset == .factoryResetTextProfiles(id: "req-text-factory-reset"))

    let reset = try WorkerRequest.decode(
        from: #"{"id":"req-text-reset","op":"reset_text_profile","text_profile_id":"logs"}"#,
    )
    #expect(reset == .resetTextProfile(id: "req-text-reset", profileID: "logs"))

    let add = try WorkerRequest.decode(
        from: #"{"id":"req-text-add","op":"create_text_replacement","text_profile_id":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"textFormats":[],"sourceFormats":[],"priority":0}}"#,
    )
    #expect(
        add == .addTextReplacement(
            id: "req-text-add",
            replacement: TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule"),
            profileID: "logs",
        ),
    )

    let replace = try WorkerRequest.decode(
        from: #"{"id":"req-text-replace","op":"replace_text_replacement","text_profile_id":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"textFormats":[],"sourceFormats":[],"priority":0}}"#,
    )
    #expect(
        replace == .replaceTextReplacement(
            id: "req-text-replace",
            replacement: TextForSpeech.Replacement("stderr", with: "standard standard error", id: "logs-rule"),
            profileID: "logs",
        ),
    )

    let remove = try WorkerRequest.decode(
        from: #"{"id":"req-text-remove-replacement","op":"delete_text_replacement","replacement_id":"logs-rule","text_profile_id":"logs"}"#,
    )
    #expect(
        remove == .removeTextReplacement(
            id: "req-text-remove-replacement",
            replacementID: "logs-rule",
            profileID: "logs",
        ),
    )
}

@Test func `decodes list queue request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-5","op":"list_generation_queue"}"#)
    #expect(request == .listQueue(id: "req-5", queueType: .generation))
}

@Test func `decodes status request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-status","op":"get_status"}"#)
    #expect(request == .status(id: "req-status"))
}

@Test func `decodes runtime overview request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-overview","op":"get_runtime_overview"}"#)
    #expect(request == .overview(id: "req-overview"))
}

@Test func `decodes switch speech backend request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-switch","op":"set_speech_backend","speech_backend":"marvis"}"#,
    )
    #expect(request == .switchSpeechBackend(id: "req-switch", speechBackend: .marvis))
}

@Test func `decodes chatterbox turbo switch speech backend request`() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-switch-chatterbox","op":"set_speech_backend","speech_backend":"chatterbox_turbo"}"#,
    )
    #expect(request == .switchSpeechBackend(id: "req-switch-chatterbox", speechBackend: .chatterboxTurbo))
}

@Test func `decodes reload models request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-reload","op":"reload_models"}"#)
    #expect(request == .reloadModels(id: "req-reload"))
}

@Test func `decodes unload models request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-unload","op":"unload_models"}"#)
    #expect(request == .unloadModels(id: "req-unload"))
}

@Test func `decodes playback queue request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-5b","op":"list_playback_queue"}"#)
    #expect(request == .listQueue(id: "req-5b", queueType: .playback))
}

@Test func `decodes playback pause request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-pause","op":"playback_pause"}"#)
    #expect(request == .playback(id: "req-pause", action: .pause))
}

@Test func `decodes clear queue request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-6","op":"clear_queue"}"#)
    #expect(request == .clearQueue(id: "req-6"))
}

@Test func `decodes cancel request`() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-7","op":"cancel_request","request_id":"req-target"}"#)
    #expect(request == .cancelRequest(id: "req-7", requestID: "req-target"))
}

@Test func `rejects malformed JSON`() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"generate_speech""#)
    }
}

@Test func `rejects unknown operation`() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func `rejects missing required fields`() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"generate_speech","text":"   ","profile_name":"default-femme"}"#)
    }
}

@Test func `rejects invalid profile name`() throws {
    let tempRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot)

    #expect(throws: SpeakSwiftly.Error.self) {
        try store.validateProfileName("Bad Name")
    }
}

// MARK: - Envelope Encoding

@Test func `encodes worker envelopes with expected keys`() throws {
    let queued = try jsonObject(
        SpeakSwiftly.QueuedEvent(
            id: "req-1",
            reason: .waitingForResidentModel,
            queuePosition: 2,
        ),
    )
    #expect(queued["event"] as? String == "queued")
    #expect(queued["reason"] as? String == "waiting_for_resident_model")
    #expect(queued["queue_position"] as? Int == 2)

    let started = try jsonObject(SpeakSwiftly.StartedEvent(id: "req-1", op: "generate_speech"))
    #expect(started["event"] as? String == "started")
    #expect(started["op"] as? String == "generate_speech")

    let progress = try jsonObject(SpeakSwiftly.ProgressEvent(id: "req-1", stage: .bufferingAudio))
    #expect(progress["event"] as? String == "progress")
    #expect(progress["stage"] as? String == "buffering_audio")

    let prerollReady = try jsonObject(SpeakSwiftly.ProgressEvent(id: "req-1", stage: .prerollReady))
    #expect(prerollReady["event"] as? String == "progress")
    #expect(prerollReady["stage"] as? String == "preroll_ready")

    let status = try jsonObject(
        SpeakSwiftly.StatusEvent(
            stage: .residentModelReady,
            residentState: .ready,
            speechBackend: .marvis,
        ),
    )
    #expect(status["event"] as? String == "worker_status")
    #expect(status["stage"] as? String == "resident_model_ready")
    #expect(status["resident_state"] as? String == "ready")
    #expect(status["speech_backend"] as? String == "marvis")

    let success = try jsonObject(
        SpeakSwiftly.Success(
            id: "req-1",
            profileName: "default-femme",
            profilePath: "/tmp/default-femme",
            profiles: nil,
            textProfileStyle: .compact,
            activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
            activeRequests: [
                SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
                SpeakSwiftly.ActiveRequest(id: "req-active-2", op: "generate_speech", voiceProfile: "default-masc", requestContext: nil),
            ],
            queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "list_voice_profiles", voiceProfile: nil, requestContext: nil, queuePosition: 1)],
            playbackState: SpeakSwiftly.PlaybackStateSnapshot(
                state: .playing,
                activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
                isStableForConcurrentGeneration: true,
                isRebuffering: false,
                stableBufferedAudioMS: 840,
                stableBufferTargetMS: 600,
            ),
            runtimeOverview: SpeakSwiftly.RuntimeOverview(
                status: SpeakSwiftly.StatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3),
                speechBackend: .qwen3,
                generationQueue: SpeakSwiftly.QueueSnapshot(
                    queueType: "generation",
                    activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
                    activeRequests: [
                        SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
                        SpeakSwiftly.ActiveRequest(id: "req-active-2", op: "generate_speech", voiceProfile: "default-masc", requestContext: nil),
                    ],
                    queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil, queuePosition: 1)],
                ),
                playbackQueue: SpeakSwiftly.QueueSnapshot(
                    queueType: "playback",
                    activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
                    queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil, queuePosition: 1)],
                ),
                playbackState: SpeakSwiftly.PlaybackStateSnapshot(
                    state: .playing,
                    activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", voiceProfile: "default-femme", requestContext: nil),
                    isStableForConcurrentGeneration: true,
                    isRebuffering: false,
                    stableBufferedAudioMS: 840,
                    stableBufferTargetMS: 600,
                ),
            ),
            status: SpeakSwiftly.StatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3),
            speechBackend: .qwen3,
            clearedCount: 2,
            cancelledRequestID: "req-queued",
        ),
    )
    #expect(success["ok"] as? Bool == true)
    #expect(success["profile_name"] as? String == "default-femme")
    #expect(success["profile_path"] as? String == "/tmp/default-femme")
    #expect(success["text_profile_style"] as? String == "compact")
    #expect((success["active_request"] as? [String: Any])?["id"] as? String == "req-active")
    #expect((success["active_requests"] as? [[String: Any]])?.count == 2)
    #expect(((success["queue"] as? [[String: Any]])?.first)?["queue_position"] as? Int == 1)
    #expect((success["playback_state"] as? [String: Any])?["is_stable_for_concurrent_generation"] as? Bool == true)
    #expect((success["playback_state"] as? [String: Any])?["stable_buffered_audio_ms"] as? Int == 840)
    #expect((success["runtime_overview"] as? [String: Any])?["speech_backend"] as? String == "qwen3")
    #expect((((success["runtime_overview"] as? [String: Any])?["generation_queue"] as? [String: Any])?["active_requests"] as? [[String: Any]])?.count == 2)
    #expect((success["status"] as? [String: Any])?["resident_state"] as? String == "ready")
    #expect((success["status"] as? [String: Any])?["speech_backend"] as? String == "qwen3")
    #expect(success["speech_backend"] as? String == "qwen3")
    #expect(success["cleared_count"] as? Int == 2)
    #expect(success["cancelled_request_id"] as? String == "req-queued")

    let textSuccess = try jsonObject(
        SpeakSwiftly.Success(
            id: "req-text-1",
            textProfile: SpeakSwiftly.TextProfileDetails(
                profileID: "logs",
                summary: SpeakSwiftly.TextProfileSummary(
                    id: "logs",
                    name: "Logs",
                    replacementCount: 1,
                ),
                replacements: [TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule")],
            ),
            textProfiles: [
                SpeakSwiftly.TextProfileSummary(
                    id: "logs",
                    name: "Logs",
                    replacementCount: 1,
                ),
            ],
            textProfileStyleOptions: [
                SpeakSwiftly.TextProfileStyleOption(style: .compact, summary: "Compact"),
            ],
            textProfileStyle: .compact,
            textProfilePath: "/tmp/text-profiles.json",
        ),
    )
    #expect((textSuccess["text_profile"] as? [String: Any])?["profile_id"] as? String == "logs")
    #expect((((textSuccess["text_profile"] as? [String: Any])?["summary"] as? [String: Any])?["replacement_count"] as? Int) == 1)
    #expect((textSuccess["text_profiles"] as? [[String: Any]])?.count == 1)
    #expect((((textSuccess["text_profiles"] as? [[String: Any]])?.first)?["replacement_count"] as? Int) == 1)
    #expect((textSuccess["text_profile_style_options"] as? [[String: Any]])?.count == 1)
    #expect(textSuccess["text_profile_style"] as? String == "compact")
    #expect(textSuccess["text_profile_path"] as? String == "/tmp/text-profiles.json")

    let failure = try jsonObject(
        SpeakSwiftly.Failure(
            id: "req-1",
            code: .audioPlaybackTimeout,
            message: "Profile 'ghost' was not found in the SpeakSwiftly profile store.",
        ),
    )
    #expect(failure["ok"] as? Bool == false)
    #expect(failure["code"] as? String == "audio_playback_timeout")
}
