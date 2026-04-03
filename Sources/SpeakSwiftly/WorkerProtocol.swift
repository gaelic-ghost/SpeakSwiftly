import Foundation

// MARK: - Request Envelope

struct RawWorkerRequest: Decodable, Sendable {
    let id: String?
    let op: String?
    let text: String?
    let profileName: String?
    let voiceDescription: String?
    let outputPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case text
        case profileName = "profile_name"
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
    }
}

enum WorkerRequest: Sendable, Equatable {
    case speakLive(id: String, text: String, profileName: String)
    case speakLiveBackground(id: String, text: String, profileName: String)
    case createProfile(id: String, profileName: String, text: String, voiceDescription: String, outputPath: String?)
    case listProfiles(id: String)
    case removeProfile(id: String, profileName: String)

    var id: String {
        switch self {
        case .speakLive(let id, _, _),
             .speakLiveBackground(let id, _, _),
             .createProfile(let id, _, _, _, _),
             .listProfiles(let id),
             .removeProfile(let id, _):
            id
        }
    }

    var opName: String {
        switch self {
        case .speakLive:
            "speak_live"
        case .speakLiveBackground:
            "speak_live_background"
        case .createProfile:
            "create_profile"
        case .listProfiles:
            "list_profiles"
        case .removeProfile:
            "remove_profile"
        }
    }

    var isPlayback: Bool {
        switch self {
        case .speakLive, .speakLiveBackground:
            return true
        default:
            return false
        }
    }

    var acknowledgesEnqueueImmediately: Bool {
        if case .speakLiveBackground = self {
            return true
        }
        return false
    }

    var profileName: String? {
        switch self {
        case .speakLive(_, _, let profileName),
             .speakLiveBackground(_, _, let profileName),
             .createProfile(_, let profileName, _, _, _),
             .removeProfile(_, let profileName):
            profileName
        case .listProfiles:
            nil
        }
    }

    static func decode(from line: String, decoder: JSONDecoder = JSONDecoder()) throws -> WorkerRequest {
        let data = Data(line.utf8)
        let raw: RawWorkerRequest

        do {
            raw = try decoder.decode(RawWorkerRequest.self, from: data)
        } catch {
            throw WorkerError(code: .invalidJSON, message: "The request line is not valid JSON. Each request must be a single JSON object on one line.")
        }

        guard let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw WorkerError(code: .invalidRequest, message: "The request is missing a non-empty 'id' field.")
        }

        guard let op = raw.op?.trimmingCharacters(in: .whitespacesAndNewlines), !op.isEmpty else {
            throw WorkerError(code: .invalidRequest, message: "Request '\(id)' is missing a non-empty 'op' field.")
        }

        switch op {
        case "speak_live":
            let text = try requireNonEmpty(raw.text, field: "text", id: id)
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            return .speakLive(id: id, text: text, profileName: profileName)

        case "speak_live_background":
            let text = try requireNonEmpty(raw.text, field: "text", id: id)
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            return .speakLiveBackground(id: id, text: text, profileName: profileName)

        case "create_profile":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            let text = try requireNonEmpty(raw.text, field: "text", id: id)
            let voiceDescription = try requireNonEmpty(raw.voiceDescription, field: "voice_description", id: id)
            let outputPath = raw.outputPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .createProfile(id: id, profileName: profileName, text: text, voiceDescription: voiceDescription, outputPath: outputPath)

        case "list_profiles":
            return .listProfiles(id: id)

        case "remove_profile":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            return .removeProfile(id: id, profileName: profileName)

        default:
            throw WorkerError(code: .unknownOperation, message: "Request '\(id)' uses unsupported operation '\(op)'.")
        }
    }

    private static func requireNonEmpty(_ value: String?, field: String, id: String) throws -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw WorkerError(code: .invalidRequest, message: "Request '\(id)' is missing a non-empty '\(field)' field.")
        }
        return trimmed
    }
}

// MARK: - Response Envelope

enum WorkerStatusStage: String, Codable, Sendable {
    case warmingResidentModel = "warming_resident_model"
    case residentModelReady = "resident_model_ready"
    case residentModelFailed = "resident_model_failed"
}

enum WorkerRequestEventName: String, Codable, Sendable {
    case queued
    case started
    case progress
}

enum WorkerProgressStage: String, Codable, Sendable {
    case loadingProfile = "loading_profile"
    case startingPlayback = "starting_playback"
    case bufferingAudio = "buffering_audio"
    case prerollReady = "preroll_ready"
    case playbackFinished = "playback_finished"
    case loadingProfileModel = "loading_profile_model"
    case generatingProfileAudio = "generating_profile_audio"
    case writingProfileAssets = "writing_profile_assets"
    case exportingProfileAudio = "exporting_profile_audio"
    case removingProfile = "removing_profile"
}

enum WorkerQueuedReason: String, Codable, Sendable {
    case waitingForResidentModel = "waiting_for_resident_model"
    case waitingForActiveRequest = "waiting_for_active_request"
}

struct WorkerStatusEvent: Encodable, Sendable {
    let event = "worker_status"
    let stage: WorkerStatusStage
}

struct WorkerQueuedEvent: Encodable, Sendable {
    let id: String
    let event = WorkerRequestEventName.queued
    let reason: WorkerQueuedReason
    let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case reason
        case queuePosition = "queue_position"
    }
}

struct WorkerStartedEvent: Encodable, Sendable {
    let id: String
    let event = WorkerRequestEventName.started
    let op: String
}

struct WorkerProgressEvent: Encodable, Sendable {
    let id: String
    let event = WorkerRequestEventName.progress
    let stage: WorkerProgressStage
}

struct WorkerSuccessResponse: Encodable, Sendable {
    let id: String
    let ok = true
    let profileName: String?
    let profilePath: String?
    let profiles: [ProfileSummary]?

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case profiles
    }
}

struct WorkerFailureResponse: Encodable, Sendable {
    let id: String
    let ok = false
    let code: WorkerErrorCode
    let message: String
}

// MARK: - Errors

enum WorkerErrorCode: String, Codable, Sendable {
    case invalidJSON = "invalid_json"
    case invalidRequest = "invalid_request"
    case unknownOperation = "unknown_operation"
    case profileNotFound = "profile_not_found"
    case profileAlreadyExists = "profile_already_exists"
    case invalidProfileName = "invalid_profile_name"
    case modelLoading = "model_loading"
    case modelGenerationFailed = "model_generation_failed"
    case requestCancelled = "request_cancelled"
    case workerShuttingDown = "worker_shutting_down"
    case audioPlaybackTimeout = "audio_playback_timeout"
    case audioPlaybackFailed = "audio_playback_failed"
    case filesystemError = "filesystem_error"
    case internalError = "internal_error"
}

struct WorkerError: Error, Sendable {
    let code: WorkerErrorCode
    let message: String
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
