import Foundation
import Testing
@testable import SpeakSwiftlyCore

// MARK: - Request Decoding

@Test func decodesSpeakLiveRequest() throws {
    let request = try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live","text":"Hello","profile_name":"default-femme"}"#)

    #expect(request == .speakLive(id: "req-1", text: "Hello", profileName: "default-femme"))
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

@Test func rejectsMalformedJSON() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live""#)
    }
}

@Test func rejectsUnknownOperation() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"dance"}"#)
    }
}

@Test func rejectsMissingRequiredFields() throws {
    #expect(throws: WorkerError.self) {
        try WorkerRequest.decode(from: #"{"id":"req-1","op":"speak_live","text":"   ","profile_name":"default-femme"}"#)
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

    let started = try jsonObject(WorkerStartedEvent(id: "req-1", op: "speak_live"))
    #expect(started["event"] as? String == "started")
    #expect(started["op"] as? String == "speak_live")

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
            profiles: nil
        )
    )
    #expect(success["ok"] as? Bool == true)
    #expect(success["profile_name"] as? String == "default-femme")
    #expect(success["profile_path"] as? String == "/tmp/default-femme")

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
