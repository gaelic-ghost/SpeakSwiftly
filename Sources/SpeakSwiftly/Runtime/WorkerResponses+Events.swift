import Foundation

// MARK: - Response Events

public extension SpeakSwiftly {
    enum ResidentModelState: String, Codable, Sendable {
        case warming
        case ready
        case unloaded
        case failed
    }

    enum RequestEventName: String, Codable, Sendable {
        case queued
        case started
        case progress
    }

    enum ProgressStage: String, Codable, Sendable {
        case loadingProfile = "loading_profile"
        case generatingFileAudio = "generating_file_audio"
        case writingGeneratedFile = "writing_generated_file"
        case startingPlayback = "starting_playback"
        case bufferingAudio = "buffering_audio"
        case prerollReady = "preroll_ready"
        case playbackFinished = "playback_finished"
        case loadingProfileModel = "loading_profile_model"
        case generatingProfileAudio = "generating_profile_audio"
        case loadingCloneTranscriptionModel = "loading_clone_transcription_model"
        case transcribingCloneAudio = "transcribing_clone_audio"
        case writingProfileAssets = "writing_profile_assets"
        case exportingProfileAudio = "exporting_profile_audio"
        case removingProfile = "removing_profile"
    }

    enum QueuedReason: String, Codable, Sendable {
        case waitingForResidentModel = "waiting_for_resident_model"
        case waitingForResidentModels = "waiting_for_resident_models"
        case waitingForActiveRequest = "waiting_for_active_request"
        case waitingForPlaybackStability = "waiting_for_playback_stability"
        case waitingForMarvisGenerationLane = "waiting_for_marvis_generation_lane"
    }

    struct QueuedEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.queued
        public let reason: QueuedReason
        public let queuePosition: Int

        enum CodingKeys: String, CodingKey {
            case id
            case event
            case reason
            case queuePosition = "queue_position"
        }

        public init(id: String, reason: QueuedReason, queuePosition: Int) {
            self.id = id
            self.reason = reason
            self.queuePosition = queuePosition
        }
    }

    struct StartedEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.started
        public let kind: RequestKind

        enum CodingKeys: String, CodingKey {
            case id
            case event
            case kind = "op"
        }

        public init(id: String, kind: RequestKind) {
            self.id = id
            self.kind = kind
        }
    }

    struct ProgressEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.progress
        public let stage: ProgressStage

        public init(id: String, stage: ProgressStage) {
            self.id = id
            self.stage = stage
        }
    }
}

package extension SpeakSwiftly {
    struct WorkerStatusEvent: Encodable, Equatable {
        let event = "worker_status"
        let stage: RuntimeState
        let residentState: ResidentModelState
        let speechBackend: SpeechBackend

        enum CodingKeys: String, CodingKey {
            case event
            case stage
            case residentState = "resident_state"
            case speechBackend = "speech_backend"
        }

        init(stage: RuntimeState, residentState: ResidentModelState, speechBackend: SpeechBackend) {
            self.stage = stage
            self.residentState = residentState
            self.speechBackend = speechBackend
        }

        func runtimeUpdate(sequence: Int, date: Date) -> RuntimeUpdate {
            RuntimeUpdate(
                sequence: sequence,
                date: date,
                state: stage,
                event: .stateChanged(stage),
            )
        }
    }
}
