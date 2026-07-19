public extension SpeakSwiftlyNormalization {
    struct PersistedState: Codable, Sendable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case version
            case builtInStyle
            case summarizationProvider
            case summaryProvider
            case activeCustomProfileID
            case profiles
        }

        public let version: Int
        public let builtInStyle: SpeakSwiftlyNormalization.BuiltInProfileStyle
        public let summarizationProvider: SpeakSwiftlyNormalization.SummarizationProvider
        public let activeCustomProfileID: String
        public let profiles: [String: Profile]

        public init(
            version: Int = 1,
            builtInStyle: SpeakSwiftlyNormalization.BuiltInProfileStyle = .balanced,
            summarizationProvider: SpeakSwiftlyNormalization.SummarizationProvider = .foundationModels,
            activeCustomProfileID: String,
            profiles: [String: Profile],
        ) {
            self.version = version
            self.builtInStyle = builtInStyle
            self.summarizationProvider = summarizationProvider
            self.activeCustomProfileID = activeCustomProfileID
            self.profiles = profiles
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            builtInStyle = try container.decodeIfPresent(
                SpeakSwiftlyNormalization.BuiltInProfileStyle.self,
                forKey: .builtInStyle,
            ) ?? .balanced
            if let decodedProvider = try container.decodeIfPresent(
                SpeakSwiftlyNormalization.SummarizationProvider.self,
                forKey: .summarizationProvider,
            ) {
                summarizationProvider = decodedProvider
            } else if let legacyProvider = try container.decodeIfPresent(
                SpeakSwiftlyNormalization.SummarizationProvider.self,
                forKey: .summaryProvider,
            ) {
                summarizationProvider = legacyProvider
            } else {
                summarizationProvider = .foundationModels
            }
            activeCustomProfileID = try container.decode(String.self, forKey: .activeCustomProfileID)
            profiles = try container.decode([String: Profile].self, forKey: .profiles)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(builtInStyle, forKey: .builtInStyle)
            try container.encode(summarizationProvider, forKey: .summarizationProvider)
            try container.encode(activeCustomProfileID, forKey: .activeCustomProfileID)
            try container.encode(profiles, forKey: .profiles)
        }
    }
}
