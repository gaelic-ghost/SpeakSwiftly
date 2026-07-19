import Foundation

public extension SpeakSwiftlyNormalization {
    struct TextProfileSummary: Codable, Sendable, Equatable, Identifiable {
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case replacementCount = "replacement_count"
        }

        public let id: String
        public let name: String
        public let replacementCount: Int

        public init(profile: Profile) {
            id = profile.id
            name = profile.name
            replacementCount = profile.replacements.count
        }

        public init(id: String, name: String, replacementCount: Int) {
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
        public let replacements: [Replacement]

        public var id: String { profileID }

        public init(profile: Profile) {
            profileID = profile.id
            summary = TextProfileSummary(profile: profile)
            replacements = profile.replacements
        }

        public init(
            profileID: String,
            summary: TextProfileSummary,
            replacements: [Replacement],
        ) {
            self.profileID = profileID
            self.summary = summary
            self.replacements = replacements
        }
    }

    struct TextProfileStyleOption: Codable, Sendable, Equatable, Identifiable {
        public let style: BuiltInProfileStyle
        public let summary: String

        public var id: BuiltInProfileStyle { style }

        public init(style: BuiltInProfileStyle, summary: String) {
            self.style = style
            self.summary = summary
        }
    }

    struct SummarizationProviderOption: Codable, Sendable, Equatable, Identifiable {
        public let provider: SummarizationProvider
        public let summary: String

        public var id: SummarizationProvider.ID { provider.id }

        public init(provider: SummarizationProvider, summary: String) {
            self.provider = provider
            self.summary = summary
        }
    }
}
