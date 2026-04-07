import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Request Decoding

@Test func decodesSpeakLiveRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"queue_speech_live","text":"Hello","profile_name":"default-femme"}"#)

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
        from: #"{"id":"req-file","op":"queue_speech_file","text":"Hello","profile_name":"default-femme"}"#
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

@Test func decodesSpeakLiveRequestWithTextContextAndProfile() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-1","op":"queue_speech_live","text":"Hello","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}"#
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
        from: #"{"id":"req-embedded","op":"queue_speech_live","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}"#
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
        from: #"{"id":"req-source","op":"queue_speech_live","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}"#
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
        from: #"{"id":"req-legacy-source","op":"queue_speech_live","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","text_format":"swift_source"}"#
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
        from: #"{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello","vibe":"femme","voice_description":"Warm and bright","output_path":"./voice.wav"}"#
    )

    #expect(
        request == .createProfile(
            id: "req-2",
            profileName: "bright-guide",
            text: "Hello",
            vibe: .femme,
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav"
        )
    )
}

@Test func decodesCreateCloneRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-clone","op":"create_clone","profile_name":"ghost-copy","reference_audio_path":"./voice.m4a","vibe":"masc","transcript":"Hello from imported audio"}"#
    )

    #expect(
        request == .createClone(
            id: "req-clone",
            profileName: "ghost-copy",
            referenceAudioPath: "./voice.m4a",
            vibe: .masc,
            transcript: "Hello from imported audio"
        )
    )
}

@Test func decodesListProfilesRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-3","op":"list_profiles"}"#)
    #expect(request == .listProfiles(id: "req-3"))
}

@Test func decodesGeneratedFileRequests() throws {
    let file = try WorkerRequest.decode(
        from: #"{"id":"req-generated-file","op":"generated_file","artifact_id":"req-file"}"#
    )
    #expect(file == .generatedFile(id: "req-generated-file", artifactID: "req-file"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-generated-files","op":"generated_files"}"#)
    #expect(list == .generatedFiles(id: "req-generated-files"))
}

@Test func decodesRemoveProfileRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-4","op":"remove_profile","profile_name":"bright-guide"}"#)
    #expect(request == .removeProfile(id: "req-4", profileName: "bright-guide"))
}

@Test func decodesTextProfileReadRequests() throws {
    let active = try WorkerRequest.decode(from: #"{"id":"req-text-active","op":"text_profile_active"}"#)
    #expect(active == .textProfileActive(id: "req-text-active"))

    let base = try WorkerRequest.decode(from: #"{"id":"req-text-base","op":"text_profile_base"}"#)
    #expect(base == .textProfileBase(id: "req-text-base"))

    let named = try WorkerRequest.decode(
        from: #"{"id":"req-text-one","op":"text_profile","text_profile_name":"logs"}"#
    )
    #expect(named == .textProfile(id: "req-text-one", name: "logs"))

    let list = try WorkerRequest.decode(from: #"{"id":"req-text-list","op":"text_profiles"}"#)
    #expect(list == .textProfiles(id: "req-text-list"))

    let effective = try WorkerRequest.decode(
        from: #"{"id":"req-text-effective","op":"text_profile_effective","text_profile_name":"logs"}"#
    )
    #expect(effective == .textProfileEffective(id: "req-text-effective", name: "logs"))
}

@Test func decodesTextProfileMutationRequests() throws {
    let create = try WorkerRequest.decode(
        from: #"{"id":"req-text-create","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs","replacements":[{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]}"#
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
        from: #"{"id":"req-text-store","op":"store_text_profile","text_profile":"# + storePayload + #"}"#
    )
    #expect(store == .storeTextProfile(id: "req-text-store", profile: profile))

    let add = try WorkerRequest.decode(
        from: #"{"id":"req-text-add","op":"add_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}"#
    )
    #expect(
        add == .addTextReplacement(
            id: "req-text-add",
            replacement: TextForSpeech.Replacement("stderr", with: "standard error", id: "logs-rule"),
            profileName: "logs"
        )
    )

    let remove = try WorkerRequest.decode(
        from: #"{"id":"req-text-remove-replacement","op":"remove_text_replacement","replacement_id":"logs-rule","text_profile_name":"logs"}"#
    )
    #expect(
        remove == .removeTextReplacement(
            id: "req-text-remove-replacement",
            replacementID: "logs-rule",
            profileName: "logs"
        )
    )
}

@Test func decodesListQueueRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-5","op":"list_queue_generation"}"#)
    #expect(request == .listQueue(id: "req-5", queueType: .generation))
}

@Test func decodesPlaybackQueueRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-5b","op":"list_queue_playback"}"#)
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
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"queue_speech_live""#)
    }
}

@Test func rejectsUnknownOperation() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func rejectsMissingRequiredFields() throws {
    #expect(throws: SpeakSwiftly.Error.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"queue_speech_live","text":"   ","profile_name":"default-femme"}"#)
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

    let started = try jsonObject(SpeakSwiftly.StartedEvent(id: "req-1", op: "queue_speech_live"))
    #expect(started["event"] as? String == "started")
    #expect(started["op"] as? String == "queue_speech_live")

    let progress = try jsonObject(SpeakSwiftly.ProgressEvent(id: "req-1", stage: .bufferingAudio))
    #expect(progress["event"] as? String == "progress")
    #expect(progress["stage"] as? String == "buffering_audio")

    let prerollReady = try jsonObject(SpeakSwiftly.ProgressEvent(id: "req-1", stage: .prerollReady))
    #expect(prerollReady["event"] as? String == "progress")
    #expect(prerollReady["stage"] as? String == "preroll_ready")

    let success = try jsonObject(
        SpeakSwiftly.Success(
            id: "req-1",
            profileName: "default-femme",
            profilePath: "/tmp/default-femme",
            profiles: nil,
            activeRequest: SpeakSwiftly.ActiveRequest(id: "req-active", op: "queue_speech_live", profileName: "default-femme"),
            queue: [SpeakSwiftly.QueuedRequest(id: "req-queued", op: "list_profiles", profileName: nil, queuePosition: 1)],
            clearedCount: 2,
            cancelledRequestID: "req-queued"
        )
    )
    #expect(success["ok"] as? Bool == true)
    #expect(success["profile_name"] as? String == "default-femme")
    #expect(success["profile_path"] as? String == "/tmp/default-femme")
    #expect((success["active_request"] as? [String: Any])?["id"] as? String == "req-active")
    #expect(((success["queue"] as? [[String: Any]])?.first)?["queue_position"] as? Int == 1)
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
            textProfilePath: "/tmp/text-profiles.json"
        )
    )
    #expect((textSuccess["text_profile"] as? [String: Any])?["id"] as? String == "logs")
    #expect((textSuccess["text_profiles"] as? [[String: Any]])?.count == 1)
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
