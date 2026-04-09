import Foundation
import TextForSpeech

// MARK: - Text Normalization API

public extension SpeakSwiftly {
    // MARK: Normalizer Handle

    actor Normalizer {
        let textRuntime: TextForSpeech.Runtime

        public init(
            activeProfile: TextForSpeech.Profile = .default,
            profiles: [String: TextForSpeech.Profile] = [:],
            persistenceURL: URL? = nil
        ) {
            textRuntime = TextForSpeech.Runtime(
                customProfile: activeProfile,
                profiles: profiles,
                persistenceURL: persistenceURL
            )
        }

        public nonisolated var profiles: Profiles {
            Profiles(normalizer: self)
        }

        public nonisolated var persistence: Persistence {
            Persistence(normalizer: self)
        }
    }
}

public extension SpeakSwiftly.Normalizer {
    struct Profiles: Sendable {
        let normalizer: SpeakSwiftly.Normalizer
    }

    struct Persistence: Sendable {
        let normalizer: SpeakSwiftly.Normalizer
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    nonisolated var normalizer: SpeakSwiftly.Normalizer {
        normalizerRef
    }
}
