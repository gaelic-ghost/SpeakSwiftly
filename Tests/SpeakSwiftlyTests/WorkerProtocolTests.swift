import Foundation
import Testing
@testable import SpeakSwiftlyCore
import TextForSpeechCore

// MARK: - Request Decoding

@Test func decodesSpeakLiveRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"queue_speech_live","text":"Hello","profile_name":"default-femme"}"#)

    #expect(
        request == .queueSpeech(
            id: "req-1",
            text: "Hello",
            profileName: "default-femme",
            jobType: .live,
            normalizationContext: nil
        )
    )
}

@Test func decodesSpeakLiveRequestWithNormalizationContext() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-1","op":"queue_speech_live","text":"Hello","profile_name":"default-femme","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly"}"#
    )

    #expect(
        request == .queueSpeech(
            id: "req-1",
            text: "Hello",
            profileName: "default-femme",
            jobType: .live,
            normalizationContext: SpeechNormalizationContext(
                cwd: "/Users/galew/Workspace/SpeakSwiftly",
                repoRoot: "/Users/galew/Workspace/SpeakSwiftly"
            )
        )
    )
}

@Test func decodesCreateProfileRequest() throws {
    let request = try WorkerRequest.decode(
        from: #"{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello","voice_description":"Warm and bright","output_path":"./voice.wav"}"#
    )

    #expect(
        request == .createProfile(
            id: "req-2",
            profileName: "bright-guide",
            text: "Hello",
            voiceDescription: "Warm and bright",
            outputPath: "./voice.wav"
        )
    )
}

@Test func decodesListProfilesRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-3","op":"list_profiles"}"#)
    #expect(request == .listProfiles(id: "req-3"))
}

@Test func decodesRemoveProfileRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-4","op":"remove_profile","profile_name":"bright-guide"}"#)
    #expect(request == .removeProfile(id: "req-4", profileName: "bright-guide"))
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
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"queue_speech_live""#)
    }
}

@Test func rejectsUnknownOperation() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func rejectsMissingRequiredFields() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"queue_speech_live","text":"   ","profile_name":"default-femme"}"#)
    }
}

@Test func rejectsInvalidProfileName() throws {
    let tempRoot = makeTempDirectoryURL()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let store = ProfileStore(rootURL: tempRoot)

    #expect(throws: WorkerError.self) {
        try store.validateProfileName("Bad Name")
    }
}

// MARK: - Envelope Encoding

@Test func encodesWorkerEnvelopesWithExpectedKeys() throws {
    let queued = try jsonObject(
        WorkerQueuedEvent(
            id: "req-1",
            reason: .waitingForResidentModel,
            queuePosition: 2
        )
    )
    #expect(queued["event"] as? String == "queued")
    #expect(queued["reason"] as? String == "waiting_for_resident_model")
    #expect(queued["queue_position"] as? Int == 2)

    let started = try jsonObject(WorkerStartedEvent(id: "req-1", op: "queue_speech_live"))
    #expect(started["event"] as? String == "started")
    #expect(started["op"] as? String == "queue_speech_live")

    let progress = try jsonObject(WorkerProgressEvent(id: "req-1", stage: .bufferingAudio))
    #expect(progress["event"] as? String == "progress")
    #expect(progress["stage"] as? String == "buffering_audio")

    let prerollReady = try jsonObject(WorkerProgressEvent(id: "req-1", stage: .prerollReady))
    #expect(prerollReady["event"] as? String == "progress")
    #expect(prerollReady["stage"] as? String == "preroll_ready")

    let success = try jsonObject(
        WorkerSuccessResponse(
            id: "req-1",
            profileName: "default-femme",
            profilePath: "/tmp/default-femme",
            profiles: nil,
            activeRequest: ActiveWorkerRequestSummary(id: "req-active", op: "queue_speech_live", profileName: "default-femme"),
            queue: [QueuedWorkerRequestSummary(id: "req-queued", op: "list_profiles", profileName: nil, queuePosition: 1)],
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

    let failure = try jsonObject(
        WorkerFailureResponse(
            id: "req-1",
            code: .audioPlaybackTimeout,
            message: "Profile 'ghost' was not found in the SpeakSwiftly profile store."
        )
    )
    #expect(failure["ok"] as? Bool == false)
    #expect(failure["code"] as? String == "audio_playback_timeout")
}
