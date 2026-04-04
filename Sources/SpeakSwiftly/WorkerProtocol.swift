import Foundation

// MARK: - Request Envelope

struct RawWorkerRequest: Decodable, Sendable {
    let id: String?
    let op: String?
    let text: String?
    let profileName: String?
    let requestID: String?
    let voiceDescription: String?
    let outputPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case text
        case profileName = "profile_name"
        case requestID = "request_id"
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
    }
}

public enum WorkerRequest: Sendable, Equatable {
    case queueSpeech(id: String, text: String, profileName: String, jobType: SpeechJobType)
    case createProfile(id: String, profileName: String, text: String, voiceDescription: String, outputPath: String?)
    case listProfiles(id: String)
    case removeProfile(id: String, profileName: String)
    case listQueue(id: String, queueType: WorkerQueueType)
    case playback(id: String, action: PlaybackAction)
    case clearQueue(id: String)
    case cancelRequest(id: String, requestID: String)

    public var id: String {
        switch self {
        case .queueSpeech(let id, _, _, _),
             .createProfile(let id, _, _, _, _),
             .listProfiles(let id),
             .removeProfile(let id, _),
             .listQueue(let id, _),
             .playback(let id, _),
             .clearQueue(let id),
             .cancelRequest(let id, _):
            id
        }
    }

    public var opName: String {
        switch self {
        case .queueSpeech(_, _, _, .live):
            "queue_speech_live"
        case .createProfile:
            "create_profile"
        case .listProfiles:
            "list_profiles"
        case .removeProfile:
            "remove_profile"
        case .listQueue(_, .generation):
            "list_queue_generation"
        case .listQueue(_, .playback):
            "list_queue_playback"
        case .playback(_, .pause):
            "playback_pause"
        case .playback(_, .resume):
            "playback_resume"
        case .playback(_, .state):
            "playback_state"
        case .clearQueue:
            "clear_queue"
        case .cancelRequest:
            "cancel_request"
        }
    }

    public var isSpeechRequest: Bool {
        switch self {
        case .queueSpeech:
            return true
        default:
            return false
        }
    }

    public var acknowledgesEnqueueImmediately: Bool {
        if case .queueSpeech = self {
            return true
        }
        return false
    }

    public var isImmediateControlOperation: Bool {
        switch self {
        case .listQueue, .playback, .clearQueue, .cancelRequest:
            return true
        default:
            return false
        }
    }

    public var profileName: String? {
        switch self {
        case .queueSpeech(_, _, let profileName, _),
             .createProfile(_, let profileName, _, _, _),
             .removeProfile(_, let profileName):
            profileName
        case .listProfiles, .listQueue, .playback, .clearQueue, .cancelRequest:
            nil
        }
    }

    public static func decode(from line: String, decoder: JSONDecoder = JSONDecoder()) throws -> WorkerRequest {
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
        case "queue_speech_live":
            let text = try requireNonEmpty(raw.text, field: "text", id: id)
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            return .queueSpeech(id: id, text: text, profileName: profileName, jobType: .live)

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

        case "list_queue_generation":
            return .listQueue(id: id, queueType: .generation)

        case "list_queue_playback":
            return .listQueue(id: id, queueType: .playback)

        case "playback_pause":
            return .playback(id: id, action: .pause)

        case "playback_resume":
            return .playback(id: id, action: .resume)

        case "playback_state":
            return .playback(id: id, action: .state)

        case "clear_queue":
            return .clearQueue(id: id)

        case "cancel_request":
            let requestID = try requireNonEmpty(raw.requestID, field: "request_id", id: id)
            return .cancelRequest(id: id, requestID: requestID)

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

public enum WorkerStatusStage: String, Codable, Sendable {
    case warmingResidentModel = "warming_resident_model"
    case residentModelReady = "resident_model_ready"
    case residentModelFailed = "resident_model_failed"
}

public enum WorkerRequestEventName: String, Codable, Sendable {
    case queued
    case started
    case progress
}

public enum WorkerProgressStage: String, Codable, Sendable {
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

public enum WorkerQueuedReason: String, Codable, Sendable {
    case waitingForResidentModel = "waiting_for_resident_model"
    case waitingForActiveRequest = "waiting_for_active_request"
}

public struct WorkerStatusEvent: Encodable, Sendable, Equatable {
    public let event = "worker_status"
    public let stage: WorkerStatusStage

    public init(stage: WorkerStatusStage) {
        self.stage = stage
    }
}

public struct WorkerQueuedEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = WorkerRequestEventName.queued
    public let reason: WorkerQueuedReason
    public let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case reason
        case queuePosition = "queue_position"
    }

    public init(id: String, reason: WorkerQueuedReason, queuePosition: Int) {
        self.id = id
        self.reason = reason
        self.queuePosition = queuePosition
    }
}

public struct WorkerStartedEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = WorkerRequestEventName.started
    public let op: String

    public init(id: String, op: String) {
        self.id = id
        self.op = op
    }
}

public struct WorkerProgressEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = WorkerRequestEventName.progress
    public let stage: WorkerProgressStage

    public init(id: String, stage: WorkerProgressStage) {
        self.id = id
        self.stage = stage
    }
}

public struct WorkerSuccessResponse: Encodable, Sendable, Equatable {
    public let id: String
    public let ok = true
    public let profileName: String?
    public let profilePath: String?
    public let profiles: [ProfileSummary]?
    public let activeRequest: ActiveWorkerRequestSummary?
    public let queue: [QueuedWorkerRequestSummary]?
    public let playbackState: PlaybackStateSummary?
    public let clearedCount: Int?
    public let cancelledRequestID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case profiles
        case activeRequest = "active_request"
        case queue
        case playbackState = "playback_state"
        case clearedCount = "cleared_count"
        case cancelledRequestID = "cancelled_request_id"
    }

    public init(
        id: String,
        profileName: String? = nil,
        profilePath: String? = nil,
        profiles: [ProfileSummary]? = nil,
        activeRequest: ActiveWorkerRequestSummary? = nil,
        queue: [QueuedWorkerRequestSummary]? = nil,
        playbackState: PlaybackStateSummary? = nil,
        clearedCount: Int? = nil,
        cancelledRequestID: String? = nil
    ) {
        self.id = id
        self.profileName = profileName
        self.profilePath = profilePath
        self.profiles = profiles
        self.activeRequest = activeRequest
        self.queue = queue
        self.playbackState = playbackState
        self.clearedCount = clearedCount
        self.cancelledRequestID = cancelledRequestID
    }
}

public struct PlaybackStateSummary: Codable, Sendable, Equatable {
    public let state: PlaybackState
    public let activeRequest: ActiveWorkerRequestSummary?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }

    public init(state: PlaybackState, activeRequest: ActiveWorkerRequestSummary?) {
        self.state = state
        self.activeRequest = activeRequest
    }
}

public struct ActiveWorkerRequestSummary: Codable, Sendable, Equatable {
    public let id: String
    public let op: String
    public let profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
    }

    public init(id: String, op: String, profileName: String?) {
        self.id = id
        self.op = op
        self.profileName = profileName
    }
}

public struct QueuedWorkerRequestSummary: Codable, Sendable, Equatable {
    public let id: String
    public let op: String
    public let profileName: String?
    public let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
        case queuePosition = "queue_position"
    }

    public init(id: String, op: String, profileName: String?, queuePosition: Int) {
        self.id = id
        self.op = op
        self.profileName = profileName
        self.queuePosition = queuePosition
    }
}

public struct WorkerFailureResponse: Encodable, Sendable, Equatable {
    public let id: String
    public let ok = false
    public let code: WorkerErrorCode
    public let message: String

    public init(id: String, code: WorkerErrorCode, message: String) {
        self.id = id
        self.code = code
        self.message = message
    }
}

// MARK: - Errors

public enum WorkerErrorCode: String, Codable, Sendable {
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
    case requestNotFound = "request_not_found"
    case filesystemError = "filesystem_error"
    case internalError = "internal_error"
}

public struct WorkerError: Error, Sendable, Equatable {
    public let code: WorkerErrorCode
    public let message: String

    public init(code: WorkerErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
