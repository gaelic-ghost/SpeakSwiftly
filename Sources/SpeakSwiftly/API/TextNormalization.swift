import Foundation
import TextForSpeech

public extension SpeakSwiftly {
    // MARK: Text Profile Transport

    struct TextProfileSummary: Codable, Sendable, Equatable, Identifiable {
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case replacementCount = "replacement_count"
        }

        public let id: String
        public let name: String
        public let replacementCount: Int

        init(_ summary: TextForSpeech.Runtime.Profiles.Summary) {
            id = summary.id
            name = summary.name
            replacementCount = summary.replacementCount
        }

        init(
            id: String,
            name: String,
            replacementCount: Int,
        ) {
            self.id = id
            self.name = name
            self.replacementCount = replacementCount
        }
    }

    struct TextProfileDetails: Codable, Sendable, Equatable, Identifiable {
        enum CodingKeys: String, CodingKey {
            case profileID = "profile_id"
            case summary
            case replacements
        }

        public let profileID: String
        public let summary: TextProfileSummary
        public let replacements: [TextForSpeech.Replacement]

        public var id: String { profileID }

        init(_ details: TextForSpeech.Runtime.Profiles.Details) {
            profileID = details.profileID
            summary = TextProfileSummary(details.summary)
            replacements = details.replacements
        }

        init(
            profileID: String,
            summary: TextProfileSummary,
            replacements: [TextForSpeech.Replacement],
        ) {
            self.profileID = profileID
            self.summary = summary
            self.replacements = replacements
        }
    }

    struct TextProfileStyleOption: Codable, Sendable, Equatable, Identifiable {
        public let style: TextForSpeech.BuiltInProfileStyle
        public let summary: String

        public var id: TextForSpeech.BuiltInProfileStyle { style }

        init(_ option: TextForSpeech.Runtime.Style.Option) {
            style = option.style
            summary = option.summary
        }

        init(
            style: TextForSpeech.BuiltInProfileStyle,
            summary: String,
        ) {
            self.style = style
            self.summary = summary
        }
    }

    // MARK: Normalizer Handle

    /// Wraps the shared TextForSpeech normalizer runtime used by SpeakSwiftly.
    actor Normalizer {
        let textRuntime: TextForSpeech.Runtime
        let configuredPersistenceURL: URL

        /// Accesses built-in text-style operations for this normalizer.
        public nonisolated var style: Style {
            Style(normalizer: self)
        }

        /// Accesses stored custom-profile operations for this normalizer.
        public nonisolated var profiles: Profiles {
            Profiles(normalizer: self)
        }

        /// Accesses persistence operations for this normalizer.
        public nonisolated var persistence: Persistence {
            Persistence(normalizer: self)
        }

        /// Creates a text normalizer that can be shared into a SpeakSwiftly runtime.
        public init(
            builtInStyle: TextForSpeech.BuiltInProfileStyle = .balanced,
            persistenceURL: URL? = nil,
            state: TextForSpeech.PersistedState? = nil,
        ) throws {
            let persistence: TextForSpeech.Runtime.PersistenceConfiguration
            let resolvedPersistenceURL: URL
            if let persistenceURL {
                let standardizedURL = persistenceURL.standardizedFileURL
                persistence = .file(standardizedURL)
                resolvedPersistenceURL = standardizedURL
            } else {
                let defaultURL = ProfileStore.defaultTextProfilesURL(
                    profileRootOverride: ProcessInfo.processInfo.environment[
                        ProfileStore.profileRootOverrideEnvironmentVariable,
                    ],
                )
                persistence = .file(defaultURL)
                resolvedPersistenceURL = defaultURL
            }

            let runtime = try TextForSpeech.Runtime(
                builtInStyle: builtInStyle,
                persistence: persistence,
            )
            if let state {
                try runtime.persistence.restore(state)
            }
            textRuntime = runtime
            configuredPersistenceURL = resolvedPersistenceURL
        }
    }
}

public extension SpeakSwiftly.Normalizer {
    /// Accesses built-in style operations on a ``SpeakSwiftly/Normalizer``.
    struct Style: Sendable {
        let normalizer: SpeakSwiftly.Normalizer
    }

    /// Accesses stored custom-profile operations on a ``SpeakSwiftly/Normalizer``.
    struct Profiles: Sendable {
        let normalizer: SpeakSwiftly.Normalizer
    }

    /// Accesses persistence operations on a ``SpeakSwiftly/Normalizer``.
    struct Persistence: Sendable {
        let normalizer: SpeakSwiftly.Normalizer
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the text normalizer attached to this runtime.
    nonisolated var normalizer: SpeakSwiftly.Normalizer {
        normalizerRef
    }
}
