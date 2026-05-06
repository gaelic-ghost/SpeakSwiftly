import Foundation

public extension SpeakSwiftly {
    /// A meaningful event in runtime resident-model state.
    enum RuntimeEvent: Codable, Sendable, Equatable {
        case stateChanged(RuntimeState)
    }

    /// The current semantic state of runtime resident-model readiness.
    enum RuntimeState: String, Codable, Sendable, Equatable {
        case warmingResidentModel = "warming_resident_model"
        case residentModelReady = "resident_model_ready"
        case residentModelsUnloaded = "resident_models_unloaded"
        case residentModelFailed = "resident_model_failed"
    }

    /// A sequenced runtime-state publication.
    struct RuntimeUpdate: Codable, Sendable, Equatable {
        public let sequence: Int
        public let date: Date
        public let state: RuntimeState
        public let event: RuntimeEvent
    }

    /// A point-in-time read of runtime resident-model and storage state.
    struct RuntimeSnapshot: Codable, Sendable, Equatable {
        public let sequence: Int
        public let capturedAt: Date
        public let state: RuntimeState
        public let speechBackend: SpeechBackend
        public let residentState: ResidentModelState
        public let defaultVoiceProfile: String
        public let storage: RuntimeStorageSnapshot
    }
}
