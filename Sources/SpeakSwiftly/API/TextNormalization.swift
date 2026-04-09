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
        ) throws {
            let runtime = try TextForSpeech.Runtime(persistenceURL: persistenceURL)
            if !profiles.isEmpty || activeProfile != .default {
                try Self.seed(
                    runtime: runtime,
                    activeProfile: activeProfile,
                    profiles: profiles
                )
            }
            textRuntime = runtime
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

private extension SpeakSwiftly.Normalizer {
    static func seed(
        runtime: TextForSpeech.Runtime,
        activeProfile: TextForSpeech.Profile,
        profiles: [String: TextForSpeech.Profile]
    ) throws {
        var storedProfiles = profiles
        storedProfiles[activeProfile.id] = activeProfile

        try runtime.persistence.restore(
            TextForSpeech.PersistedState(
                version: runtime.persistence.state.version,
                activeCustomProfileID: activeProfile.id,
                profiles: storedProfiles
            )
        )
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    nonisolated var normalizer: SpeakSwiftly.Normalizer {
        normalizerRef
    }
}
