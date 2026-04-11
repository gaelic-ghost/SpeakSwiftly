import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Request Decoding

@Test func decodesSpeakLiveRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"generate_speech","text":"Hello","profile_name":"default-femme"}"#)

    #expect(
        request == .queueSpeech(
            id: "req-1",
            text: "Hello",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: nil
        )
    )
}

@Test func decodesSpeakFileRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-file","op":"generate_audio_file","text":"Hello","profile_name":"default-femme"}"#
    )

    #expect(
        request == .queueSpeech(
            id: "req-file",
            text: "Hello",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .file,
            textContext: nil,
            sourceFormat: nil
        )
    )
}

@Test func decodesSpeakBatchRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-batch","op":"generate_batch","profile_name":"default-femme","items":[{"text":"First file"},{"artifact_id":"custom-artifact","text":"Second file","text_profile_name":"logs","source_format":"swift_source"}]}"#
    )

    #expect(
        request == .queueBatch(
            id: "req-batch",
            profileName: "default-femme",
            items: [
                SpeakSwiftly.GenerationJobItem(
                    artifactID: "req-batch-artifact-1",
                    text: "First file",
                    textProfileName: nil,
                    textContext: nil,
                    sourceFormat: nil
                ),
                SpeakSwiftly.GenerationJobItem(
                    artifactID: "custom-artifact",
                    text: "Second file",
                    textProfileName: "logs",
                    textContext: nil,
                    sourceFormat: .swift
                ),
            ]
        )
    )
}

@Test func decodesSpeakLiveRequestWithTextContextAndProfile() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-1","op":"generate_speech","text":"Hello","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}"#
    )

    #expect(
        request == .queueSpeech(
            id: "req-1",
            text: "Hello",
            profileName: "default-femme",
            textProfileName: "logs",
            jobType: .live,
            textContext: TextForSpeech.Context(
                cwd: "/Users/galew/Workspace/SpeakSwiftly",
                repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
                textFormat: .cli
            ),
            sourceFormat: nil
        )
    )
}

@Test func decodesSpeakLiveRequestWithNestedSourceFormat() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-embedded","op":"generate_speech","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}"#
    )

    #expect(
        request == .queueSpeech(
            id: "req-embedded",
            text: "```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: TextForSpeech.Context(
                textFormat: .markdown,
                nestedSourceFormat: .swift
            ),
            sourceFormat: nil
        )
    )
}

@Test func decodesSpeakLiveRequestWithWholeSourceFormat() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-source","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}"#
    )

    #expect(
        request == .queueSpeech(
            id: "req-source",
            text: "struct WorkerRuntime { let sampleRate: Int }",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: .swift
        )
    )
}

@Test func decodesLegacyWholeSourceTextFormatAsSourceLane() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-legacy-source","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","text_format":"swift_source"}"#
    )

    #expect(
        request == .queueSpeech(
            id: "req-legacy-source",
            text: "struct WorkerRuntime { let sampleRate: Int }",
            profileName: "default-femme",
            textProfileName: nil,
            jobType: .live,
            textContext: nil,
            sourceFormat: .swift
        )
    )
}

@Test func decodesCreateProfileRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-2","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello","vibe":"femme","voice_description":"Warm and bright","output_path":"./voice.wav"}"#
    )

    #expect(
        request == .createProfile(
            id: "req-2",
            profileName: "bright-guide",
            text: "Hello",
            vibe: .femme,
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav",
            cwd: nil
        )
    )
}

@Test func decodesCreateProfileRequestWithCallerWorkingDirectory() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-2b","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello","vibe":"femme","voice_description":"Warm and bright","output_path":"./voice.wav","cwd":"/tmp/export-base"}"#
    )

    #expect(
        request == .createProfile(
            id: "req-2b",
            profileName: "bright-guide",
            text: "Hello",
            vibe: .femme,
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav",
            cwd: "/tmp/export-base"
        )
    )
}

@Test func decodesCreateCloneRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-clone","op":"create_voice_profile_from_audio","profile_name":"ghost-copy","reference_audio_path":"./voice.m4a","vibe":"masc","transcript":"Hello from imported audio"}"#
    )

    #expect(
        request == .createClone(
            id: "req-clone",
            profileName: "ghost-copy",
            referenceAudioPath: "./voice.m4a",
            vibe: .masc,
            transcript: "Hello from imported audio",
            cwd: nil
        )
    )
}

@Test func decodesCreateCloneRequestWithCallerWorkingDirectory() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-clone-cwd","op":"create_voice_profile_from_audio","profile_name":"ghost-copy","reference_audio_path":"./voice.m4a","vibe":"masc","transcript":"Hello from imported audio","cwd":"file:///tmp/clone-base"}"#
    )

    #expect(
        request == .createClone(
            id: "req-clone-cwd",
            profileName: "ghost-copy",
            referenceAudioPath: "./voice.m4a",
            vibe: .masc,
            transcript: "Hello from imported audio",
            cwd: "file:///tmp/clone-base"
        )
    )
}

@Test func decodesListProfilesRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-3","op":"list_voice_profiles"}"#)
    #expect(request == .listProfiles(id: "req-3"))
}

@Test func decodesRenameProfileRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-rename","op":"update_voice_profile_name","profile_name":"bright-guide","new_profile_name":"clear-guide"}"#
    )
    #expect(request == .renameProfile(id: "req-rename", profileName: "bright-guide", newProfileName: "clear-guide"))
}

@Test func decodesRerollProfileRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-reroll","op":"reroll_voice_profile","profile_name":"bright-guide"}"#
    )
    #expect(request == .rerollProfile(id: "req-reroll", profileName: "bright-guide"))
}

@Test func decodesGeneratedFileRequests() throws {
    let file = try WorkerRequest.decode(
        from: #"{"id":"req-generated-file","op":"get_generated_file","artifact_id":"req-file"}"#
    )
    #expect(file == .generatedFile(id: "req-generated-file", artifactID: "req-file"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-generated-files","op":"list_generated_files"}"#)
    #expect(list == .generatedFiles(id: "req-generated-files"))

    let batch = try WorkerRequest.decode(
        from: #"{"id":"req-generated-batch","op":"get_generated_batch","batch_id":"batch-job-1"}"#
    )
    #expect(batch == .generatedBatch(id: "req-generated-batch", batchID: "batch-job-1"))

    let batchList = try WorkerRequest.decode(from: #"{"id":"req-generated-batches","op":"list_generated_batches"}"#)
    #expect(batchList == .generatedBatches(id: "req-generated-batches"))
}

@Test func decodesGenerationJobRequests() throws {
    let job = try WorkerRequest.decode(
        from: #"{"id":"req-generation-job","op":"get_generation_job","job_id":"job-file-1"}"#
    )
    #expect(job == .generationJob(id: "req-generation-job", jobID: "job-file-1"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-generation-jobs","op":"list_generation_jobs"}"#)
    #expect(list == .generationJobs(id: "req-generation-jobs"))

    let expire = try WorkerRequest.decode(
        from: #"{"id":"req-expire-job","op":"expire_generation_job","job_id":"job-file-1"}"#
    )
    #expect(expire == .expireGenerationJob(id: "req-expire-job", jobID: "job-file-1"))
}

@Test func decodesRemoveProfileRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-4","op":"delete_voice_profile","profile_name":"bright-guide"}"#)
    #expect(request == .removeProfile(id: "req-4", profileName: "bright-guide"))
}

@Test func decodesTextProfileReadRequests() throws {
    let active = try WorkerRequest.decode(from: #"{"id":"req-text-active","op":"get_active_text_profile"}"#)
    #expect(active == .textProfileActive(id: "req-text-active"))

    let style = try WorkerRequest.decode(from: #"{"id":"req-text-style","op":"get_text_profile_style"}"#)
    #expect(style == .textProfileStyle(id: "req-text-style"))

    let named = try WorkerRequest.decode(
        from: #"{"id":"req-text-one","op":"get_text_profile","text_profile_name":"logs"}"#
    )
    #expect(named == .textProfile(id: "req-text-one", name: "logs"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-text-list","op":"list_text_profiles"}"#)
    #expect(list == .textProfiles(id: "req-text-list"))

    let effective = try WorkerRequest.decode(
        from: #"{"id":"req-text-effective","op":"get_effective_text_profile","text_profile_name":"logs"}"#
    )
    #expect(effective == .textProfileEffective(id: "req-text-effective", name: "logs"))

    let replacements = try WorkerRequest.decode(
        from: #"{"id":"req-text-replacements","op":"list_text_replacements","text_profile_name":"logs"}"#
    )
    #expect(replacements == .textReplacements(id: "req-text-replacements", profileName: "logs"))
}

@Test func decodesTextProfileMutationRequests() throws {
    let setStyle = try WorkerRequest.decode(
        from: #"{"id":"req-text-style-set","op":"set_text_profile_style","text_profile_style":"compact"}"#
    )
    #expect(
        setStyle == .setTextProfileStyle(
            id: "req-text-style-set",
            style: .compact
        )
    )

    let create = try WorkerRequest.decode(
        from: #"{"id":"req-text-create","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs","replacements":[{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"textFormats":[],"sourceFormats":[],"priority":0}]}"#
    )
    #expect(
        create == .createTextProfile(
            id: "req-text-create",
            profileID: "logs",
            profileName: "Logs",
            replacements: [
                TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule")
            ]
        )
    )

    let profile = TextForSpeech.Profile(
        id: "ops",
        name: "Ops",
        replacements: [TextForSpeech.Replacement("stdout", with: "standard output", id: "ops-rule")]
    )
    let storePayload = try String(decoding: JSONEncoder().encode(profile), as: UTF8.self)
    let store = try WorkerRequest.decode(
        from: #"{"id":"req-text-store","op":"replace_text_profile","text_profile":"# + storePayload + #"}"#
    )
    #expect(store == .storeTextProfile(id: "req-text-store", profile: profile))

    let add = try WorkerRequest.decode(
        from: #"{"id":"req-text-add","op":"create_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"textFormats":[],"sourceFormats":[],"priority":0}}"#
    )
    #expect(
        add == .addTextReplacement(
            id: "req-text-add",
            replacement: TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule"),
            profileName: "logs"
        )
    )

    let remove = try WorkerRequest.decode(
        from: #"{"id":"req-text-remove-replacement","op":"delete_text_replacement","replacement_id":"logs-rule","text_profile_name":"logs"}"#
    )
    #expect(
        remove == .removeTextReplacement(
            id: "req-text-remove-replacement",
            replacementID: "logs-rule",
            profileName: "logs"
        )
    )

    let clear = try WorkerRequest.decode(
        from: #"{"id":"req-text-clear","op":"clear_text_replacements","text_profile_name":"logs"}"#
    )
    #expect(
        clear == .clearTextReplacements(
            id: "req-text-clear",
            profileName: "logs"
        )
    )
}

@Test func decodesListQueueRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-5","op":"list_generation_queue"}"#)
    #expect(request == .listQueue(id: "req-5", queueType: .generation))
}

@Test func decodesStatusRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-status","op":"get_status"}"#)
    #expect(request == .status(id: "req-status"))
}

@Test func decodesRuntimeOverviewRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-overview","op":"get_runtime_overview"}"#)
    #expect(request == .overview(id: "req-overview"))
}

@Test func decodesSwitchSpeechBackendRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-switch","op":"set_speech_backend","speech_backend":"marvis"}"#
    )
    #expect(request == .switchSpeechBackend(id: "req-switch", speechBackend: .marvis))
}

@Test func decodesReloadModelsRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-reload","op":"reload_models"}"#)
    #expect(request == .reloadModels(id: "req-reload"))
}

@Test func decodesUnloadModelsRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-unload","op":"unload_models"}"#)
    #expect(request == .unloadModels(id: "req-unload"))
}

@Test func decodesPlaybackQueueRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-5b","op":"list_playback_queue"}"#)
    #expect(request == .listQueue(id: "req-5b", queueType: .playback))
}

@Test func decodesPlaybackPauseRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-pause","op":"playback_pause"}"#)
    #expect(request == .playback(id: "req-pause", action: .pause))
}

@Test func decodesClearQueueRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-6","op":"clear_queue"}"#)
    #expect(request == .clearQueue(id: "req-6"))
}

@Test func decodesCancelRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-7","op":"cancel_request","request_id":"req-target"}"#)
    #expect(request == .cancelRequest(id: "req-7", requestID: "req-target"))
}

@Test func rejectsMalformedJSON() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"generate_speech""#)
    }
}

@Test func rejectsUnknownOperation() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func rejectsMissingRequiredFields() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"generate_speech","text":"   ","profile_name":"default-femme"}"#)
    }
}

@Test func rejectsInvalidProfileName() throws {
    let tempRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot)

    #expect(throws: SpeakSwiftly.Error.self) {
        try store.validateProfileName("Bad Name")
    }
}

// MARK: - Envelope Encoding

@Test func encodesWorkerEnvelopesWithExpectedKeys() throws {
    let queued = try jsonObject(
        SpeakSwiftly.QueuedEvent(
            id: "req-1",
            reason: .waitingForResidentModel,
            queuePosition: 2
        )
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
            speechBackend: .marvis
        )
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
            activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
            activeRequests: [
                SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
                SpeakSwiftly.ActiveRequest(id: "req-active-2", op: "generate_speech", profileName: "default-masc"),
            ],
            queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "list_voice_profiles", profileName: nil, queuePosition: 1)],
            playbackState: SpeakSwiftly.PlaybackStateSnapshot(
                state: .playing,
                activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
                isStableForConcurrentGeneration: true,
                isRebuffering: false,
                stableBufferedAudioMS: 840,
                stableBufferTargetMS: 600
            ),
            runtimeOverview: SpeakSwiftly.RuntimeOverview(
                status: SpeakSwiftly.StatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3),
                speechBackend: .qwen3,
                generationQueue: SpeakSwiftly.QueueSnapshot(
                    queueType: "generation",
                    activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
                    activeRequests: [
                        SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
                        SpeakSwiftly.ActiveRequest(id: "req-active-2", op: "generate_speech", profileName: "default-masc"),
                    ],
                    queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "generate_speech", profileName: "default-femme", queuePosition: 1)]
                ),
                playbackQueue: SpeakSwiftly.QueueSnapshot(
                    queueType: "playback",
                    activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
                    queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "generate_speech", profileName: "default-femme", queuePosition: 1)]
                ),
                playbackState: SpeakSwiftly.PlaybackStateSnapshot(
                    state: .playing,
                    activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "generate_speech", profileName: "default-femme"),
                    isStableForConcurrentGeneration: true,
                    isRebuffering: false,
                    stableBufferedAudioMS: 840,
                    stableBufferTargetMS: 600
                )
            ),
            status: SpeakSwiftly.StatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3),
            speechBackend: .qwen3,
            clearedCount: 2,
            cancelledRequestID: "req-queued"
        )
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
            textProfile: TextForSpeech.Profile(
                id: "logs",
                name: "Logs",
                replacements: [TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule")]
            ),
            textProfiles: [TextForSpeech.Profile(id: "logs", name: "Logs")],
            replacements: [TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule")],
            textProfilePath: "/tmp/text-profiles.json"
        )
    )
    #expect((textSuccess["text_profile"] as? [String: Any])?["id"] as? String == "logs")
    #expect((textSuccess["text_profiles"] as? [[String: Any]])?.count == 1)
    #expect((textSuccess["replacements"] as? [[String: Any]])?.count == 1)
    #expect(textSuccess["text_profile_path"] as? String == "/tmp/text-profiles.json")

    let failure = try jsonObject(
        SpeakSwiftly.Failure(
            id: "req-1",
            code: .audioPlaybackTimeout,
            message: "Profile 'ghost' was not found in the SpeakSwiftly profile store."
        )
    )
    #expect(failure["ok"] as? Bool == false)
    #expect(failure["code"] as? String == "audio_playback_timeout")
}
