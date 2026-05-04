import Foundation

// MARK: - Response Runtime Overview

public extension SpeakSwiftly {
    struct QueueSnapshot: Codable, Sendable, Equatable {
        public let queueType: QueueType
        public let activeRequests: [ActiveRequest]
        public let queue: [QueuedRequest]

        enum CodingKeys: String, CodingKey {
            case queueType = "queue_type"
            case activeRequests = "active_requests"
            case queue
        }

        public init(
            queueType: QueueType,
            activeRequests: [ActiveRequest] = [],
            queue: [QueuedRequest],
        ) {
            self.queueType = queueType
            self.activeRequests = activeRequests
            self.queue = queue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            queueType = try container.decode(QueueType.self, forKey: .queueType)
            activeRequests = try container.decodeIfPresent([ActiveRequest].self, forKey: .activeRequests) ?? []
            queue = try container.decode([QueuedRequest].self, forKey: .queue)
        }
    }

    struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
        public let state: PlaybackState
        public let activeRequest: ActiveRequest?
        /// These fields remain part of the runtime overview as playback telemetry for operators.
        /// Runtime scheduling no longer depends directly on this richer surface.
        public let isStableForConcurrentGeneration: Bool
        public let isRebuffering: Bool
        public let stableBufferedAudioMS: Int?
        public let stableBufferTargetMS: Int?

        enum CodingKeys: String, CodingKey {
            case state
            case activeRequest = "active_request"
            case isStableForConcurrentGeneration = "is_stable_for_concurrent_generation"
            case isRebuffering = "is_rebuffering"
            case stableBufferedAudioMS = "stable_buffered_audio_ms"
            case stableBufferTargetMS = "stable_buffer_target_ms"
        }

        public init(
            state: PlaybackState,
            activeRequest: ActiveRequest?,
            isStableForConcurrentGeneration: Bool = false,
            isRebuffering: Bool = false,
            stableBufferedAudioMS: Int? = nil,
            stableBufferTargetMS: Int? = nil,
        ) {
            self.state = state
            self.activeRequest = activeRequest
            self.isStableForConcurrentGeneration = isStableForConcurrentGeneration
            self.isRebuffering = isRebuffering
            self.stableBufferedAudioMS = stableBufferedAudioMS
            self.stableBufferTargetMS = stableBufferTargetMS
        }
    }

    struct RuntimeOverview: Encodable, Sendable, Equatable {
        public let status: StatusEvent?
        public let speechBackend: SpeechBackend
        public let storage: RuntimeStorageSnapshot
        public let generationQueue: QueueSnapshot
        public let playbackQueue: QueueSnapshot
        public let playbackState: PlaybackStateSnapshot
        public let defaultVoiceProfile: String

        enum CodingKeys: String, CodingKey {
            case status
            case speechBackend = "speech_backend"
            case storage
            case generationQueue = "generation_queue"
            case playbackQueue = "playback_queue"
            case playbackState = "playback_state"
            case defaultVoiceProfile = "default_voice_profile"
        }

        public init(
            status: StatusEvent?,
            speechBackend: SpeechBackend,
            storage: RuntimeStorageSnapshot,
            generationQueue: QueueSnapshot,
            playbackQueue: QueueSnapshot,
            playbackState: PlaybackStateSnapshot,
            defaultVoiceProfile: String,
        ) {
            self.status = status
            self.speechBackend = speechBackend
            self.storage = storage
            self.generationQueue = generationQueue
            self.playbackQueue = playbackQueue
            self.playbackState = playbackState
            self.defaultVoiceProfile = defaultVoiceProfile
        }
    }

    struct RuntimeStorageSnapshot: Codable, Sendable, Equatable {
        public let stateRootPath: String
        public let profileStoreRootPath: String
        public let configurationPath: String
        public let textProfilesPath: String
        public let generatedFilesRootPath: String
        public let generationJobsRootPath: String

        enum CodingKeys: String, CodingKey {
            case stateRootPath = "state_root_path"
            case profileStoreRootPath = "profile_store_root_path"
            case configurationPath = "configuration_path"
            case textProfilesPath = "text_profiles_path"
            case generatedFilesRootPath = "generated_files_root_path"
            case generationJobsRootPath = "generation_jobs_root_path"
        }

        public init(
            stateRootPath: String,
            profileStoreRootPath: String,
            configurationPath: String,
            textProfilesPath: String,
            generatedFilesRootPath: String,
            generationJobsRootPath: String,
        ) {
            self.stateRootPath = stateRootPath
            self.profileStoreRootPath = profileStoreRootPath
            self.configurationPath = configurationPath
            self.textProfilesPath = textProfilesPath
            self.generatedFilesRootPath = generatedFilesRootPath
            self.generationJobsRootPath = generationJobsRootPath
        }
    }

    struct ActiveRequest: Codable, Sendable, Equatable {
        public let id: String
        public let kind: RequestKind
        public let voiceProfile: String?
        public let requestContext: SpeakSwiftly.RequestContext?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case voiceProfile = "voice_profile"
            case requestContext = "request_context"
        }

        public init(id: String, kind: RequestKind, voiceProfile: String?, requestContext: SpeakSwiftly.RequestContext?) {
            self.id = id
            self.kind = kind
            self.voiceProfile = voiceProfile
            self.requestContext = requestContext
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decode(RequestKind.self, forKey: .op)
            voiceProfile = try container.decodeIfPresent(String.self, forKey: .voiceProfile)
            requestContext = try container.decodeIfPresent(SpeakSwiftly.RequestContext.self, forKey: .requestContext)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(kind, forKey: .op)
            try container.encodeIfPresent(voiceProfile, forKey: .voiceProfile)
            try container.encodeIfPresent(requestContext, forKey: .requestContext)
        }
    }

    struct QueuedRequest: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case id
            case op
            case voiceProfile = "voice_profile"
            case requestContext = "request_context"
            case queuePosition = "queue_position"
        }

        public let id: String
        public let kind: RequestKind
        public let voiceProfile: String?
        public let requestContext: SpeakSwiftly.RequestContext?
        public let queuePosition: Int

        public init(
            id: String,
            kind: RequestKind,
            voiceProfile: String?,
            requestContext: SpeakSwiftly.RequestContext?,
            queuePosition: Int,
        ) {
            self.id = id
            self.kind = kind
            self.voiceProfile = voiceProfile
            self.requestContext = requestContext
            self.queuePosition = queuePosition
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decode(RequestKind.self, forKey: .op)
            voiceProfile = try container.decodeIfPresent(String.self, forKey: .voiceProfile)
            requestContext = try container.decodeIfPresent(SpeakSwiftly.RequestContext.self, forKey: .requestContext)
            queuePosition = try container.decode(Int.self, forKey: .queuePosition)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(kind, forKey: .op)
            try container.encodeIfPresent(voiceProfile, forKey: .voiceProfile)
            try container.encodeIfPresent(requestContext, forKey: .requestContext)
            try container.encode(queuePosition, forKey: .queuePosition)
        }
    }
}
