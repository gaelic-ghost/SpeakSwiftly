import Foundation
import SpeakSwiftlyNormalization

public extension SpeakSwiftly {
    /// Owns speech-safe text normalization, summarization, profiles, and persistence.
    actor Normalizer {
        enum Versioning {
            static let currentPersistedStateVersion = 1
        }

        let fileManager: FileManager
        let configuredPersistenceURL: URL

        var builtInStyle: TextProfileStyle
        var activeSummarizationProvider: SummarizationProvider
        var activeCustomProfileID: TextProfileID
        var storedCustomProfilesByID: [TextProfileID: TextProfile]

        /// Accesses built-in text-style operations for this normalizer.
        public nonisolated var style: Style { Style(normalizer: self) }

        /// Accesses stored custom-profile operations for this normalizer.
        public nonisolated var profiles: Profiles { Profiles(normalizer: self) }

        /// Accesses summarization-provider operations for this normalizer.
        public nonisolated var summarization: Summarization { Summarization(normalizer: self) }

        /// Accesses persistence operations for this normalizer.
        public nonisolated var persistence: Persistence { Persistence(normalizer: self) }

        /// Creates a normalizer with one state owner and one persistence location.
        public init(
            builtInStyle: TextProfileStyle = .balanced,
            persistenceURL: URL? = nil,
            state: TextNormalizationState? = nil,
        ) throws {
            let resolvedPersistenceURL = persistenceURL?.standardizedFileURL
                ?? ProfileStore.defaultTextProfilesURL(
                    stateRootOverride: ProfileStore.runtimeStateRootOverridePath(
                        in: ProcessInfo.processInfo.environment,
                    ),
                )

            fileManager = .default
            configuredPersistenceURL = resolvedPersistenceURL
            self.builtInStyle = builtInStyle
            activeSummarizationProvider = .foundationModels
            activeCustomProfileID = TextProfile.default.id
            storedCustomProfilesByID = [:]

            if let state {
                try Self.validate(state)
                self.builtInStyle = state.builtInStyle
                activeSummarizationProvider = state.summarizationProvider
                activeCustomProfileID = state.activeCustomProfileID
                storedCustomProfilesByID = state.profiles
            } else if fileManager.fileExists(atPath: resolvedPersistenceURL.path) {
                let loadedState = try Self.loadState(from: resolvedPersistenceURL)
                try Self.validate(loadedState)
                self.builtInStyle = loadedState.builtInStyle
                activeSummarizationProvider = loadedState.summarizationProvider
                activeCustomProfileID = loadedState.activeCustomProfileID
                storedCustomProfilesByID = loadedState.profiles
            }

            let repaired = Self.repairedProfileState(
                activeProfileID: activeCustomProfileID,
                profiles: storedCustomProfilesByID,
            )
            activeCustomProfileID = repaired.activeProfileID
            storedCustomProfilesByID = repaired.profiles

            if state == nil, !fileManager.fileExists(atPath: resolvedPersistenceURL.path) {
                try Self.writeState(
                    TextNormalizationState(
                        version: Self.Versioning.currentPersistedStateVersion,
                        builtInStyle: self.builtInStyle,
                        summarizationProvider: activeSummarizationProvider,
                        activeCustomProfileID: activeCustomProfileID,
                        profiles: storedCustomProfilesByID,
                    ),
                    to: resolvedPersistenceURL,
                    fileManager: fileManager,
                )
            }
        }
    }
}

public extension SpeakSwiftly.Normalizer {
    /// Built-in text-style operations on a normalizer.
    struct Style: Sendable { let normalizer: SpeakSwiftly.Normalizer }

    /// Stored custom-profile operations on a normalizer.
    struct Profiles: Sendable { let normalizer: SpeakSwiftly.Normalizer }

    /// Summarization-provider operations on a normalizer.
    struct Summarization: Sendable { let normalizer: SpeakSwiftly.Normalizer }

    /// Persistence operations on a normalizer.
    struct Persistence: Sendable { let normalizer: SpeakSwiftly.Normalizer }
}

public extension SpeakSwiftly.Runtime {
    /// Returns the text normalizer attached to this runtime.
    nonisolated var normalizer: SpeakSwiftly.Normalizer { normalizerRef }
}
