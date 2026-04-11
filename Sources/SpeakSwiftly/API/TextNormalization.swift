import Foundation
import TextForSpeech

// MARK: - Text Normalization API

public extension SpeakSwiftly {
    // MARK: Normalizer Handle

    actor Normalizer {
        let textRuntime: TextForSpeech.Runtime
        let configuredPersistenceURL: URL

        public init(
            builtInStyle: TextForSpeech.BuiltInProfileStyle = .balanced,
            activeProfile: TextForSpeech.Profile = .default,
            profiles: [String: TextForSpeech.Profile] = [:],
            persistenceURL: URL? = nil
        ) throws {
            let persistence: TextForSpeech.Runtime.PersistenceConfiguration
            let resolvedPersistenceURL: URL
            if let persistenceURL {
                let standardizedURL = persistenceURL.standardizedFileURL
                persistence = .file(standardizedURL)
                resolvedPersistenceURL = standardizedURL
            } else {
                let defaultURL = ProfileStore.defaultTextProfilesURL()
                persistence = .file(defaultURL)
                resolvedPersistenceURL = defaultURL
            }

            let runtime = try TextForSpeech.Runtime(
                builtInStyle: builtInStyle,
                persistence: persistence
            )
            if builtInStyle != .balanced || !profiles.isEmpty || activeProfile != .default {
                try Self.seed(
                    runtime: runtime,
                    builtInStyle: builtInStyle,
                    activeProfile: activeProfile,
                    profiles: profiles
                )
            }
            textRuntime = runtime
            configuredPersistenceURL = resolvedPersistenceURL
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
        builtInStyle: TextForSpeech.BuiltInProfileStyle,
        activeProfile: TextForSpeech.Profile,
        profiles: [String: TextForSpeech.Profile]
    ) throws {
        var storedProfiles = profiles
        storedProfiles[activeProfile.id] = activeProfile

        try runtime.persistence.restore(
            TextForSpeech.PersistedState(
                version: runtime.persistence.state.version,
                builtInStyle: builtInStyle,
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
