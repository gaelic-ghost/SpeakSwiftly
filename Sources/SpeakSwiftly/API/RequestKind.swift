import Foundation

public extension SpeakSwiftly {
    /// Identifies the kind of work represented by a request.
    struct RequestKind: RawRepresentable, Codable, Sendable, Equatable, Hashable {
        public static let generateSpeech = Self(rawValue: "generate_speech")
        public static let generateAudioFile = Self(rawValue: "generate_audio_file")
        public static let generateBatch = Self(rawValue: "generate_batch")
        public static let getArtifact = Self(rawValue: "get_generated_file")
        public static let listArtifacts = Self(rawValue: "list_generated_files")
        public static let getGenerationJob = Self(rawValue: "get_generation_job")
        public static let listGenerationJobs = Self(rawValue: "list_generation_jobs")
        public static let expireGenerationJob = Self(rawValue: "expire_generation_job")
        public static let createVoiceProfileFromDescription = Self(rawValue: "create_voice_profile_from_description")
        public static let createVoiceProfileFromAudio = Self(rawValue: "create_voice_profile_from_audio")
        public static let createSystemVoiceProfileFromDescription = Self(rawValue: "create_system_voice_profile_from_description")
        public static let listVoiceProfiles = Self(rawValue: "list_voice_profiles")
        public static let updateVoiceProfileName = Self(rawValue: "update_voice_profile_name")
        public static let rerollVoiceProfile = Self(rawValue: "reroll_voice_profile")
        public static let deleteVoiceProfile = Self(rawValue: "delete_voice_profile")
        public static let getActiveTextProfile = Self(rawValue: "get_active_text_profile")
        public static let getTextProfile = Self(rawValue: "get_text_profile")
        public static let listTextProfiles = Self(rawValue: "list_text_profiles")
        public static let getEffectiveTextProfile = Self(rawValue: "get_effective_text_profile")
        public static let getTextProfilePersistence = Self(rawValue: "get_text_profile_persistence")
        public static let getActiveTextProfileStyle = Self(rawValue: "get_active_text_profile_style")
        public static let listTextProfileStyles = Self(rawValue: "list_text_profile_styles")
        public static let setActiveTextProfileStyle = Self(rawValue: "set_active_text_profile_style")
        public static let createTextProfile = Self(rawValue: "create_text_profile")
        public static let updateTextProfileName = Self(rawValue: "update_text_profile_name")
        public static let setActiveTextProfile = Self(rawValue: "set_active_text_profile")
        public static let deleteTextProfile = Self(rawValue: "delete_text_profile")
        public static let factoryResetTextProfiles = Self(rawValue: "factory_reset_text_profiles")
        public static let resetTextProfile = Self(rawValue: "reset_text_profile")
        public static let loadTextProfiles = Self(rawValue: "load_text_profiles")
        public static let saveTextProfiles = Self(rawValue: "save_text_profiles")
        public static let createTextReplacement = Self(rawValue: "create_text_replacement")
        public static let replaceTextReplacement = Self(rawValue: "replace_text_replacement")
        public static let deleteTextReplacement = Self(rawValue: "delete_text_replacement")
        public static let listGenerationQueue = Self(rawValue: "list_generation_queue")
        public static let listPlaybackQueue = Self(rawValue: "list_playback_queue")
        public static let clearGenerationQueue = Self(rawValue: "clear_generation_queue")
        public static let clearPlaybackQueue = Self(rawValue: "clear_playback_queue")
        public static let cancelGeneration = Self(rawValue: "cancel_generation")
        public static let cancelPlayback = Self(rawValue: "cancel_playback")
        public static let getStatus = Self(rawValue: "get_status")
        public static let getRuntimeOverview = Self(rawValue: "get_runtime_overview")
        public static let getDefaultVoiceProfile = Self(rawValue: "get_default_voice_profile")
        public static let setDefaultVoiceProfile = Self(rawValue: "set_default_voice_profile")
        public static let getPlaybackState = Self(rawValue: "get_playback_state")
        public static let playbackPause = Self(rawValue: "playback_pause")
        public static let playbackResume = Self(rawValue: "playback_resume")
        public static let setSpeechBackend = Self(rawValue: "set_speech_backend")
        public static let reloadModels = Self(rawValue: "reload_models")
        public static let unloadModels = Self(rawValue: "unload_models")
        public static let clearQueue = Self(rawValue: "clear_queue")
        public static let cancelRequest = Self(rawValue: "cancel_request")

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}
