import Foundation

// MARK: - Voice Vibe

public extension SpeakSwiftly {
    /// The broad vocal presentation used when creating a voice profile.
    enum Vibe: String, Codable, Sendable, Equatable, CaseIterable {
        case masc
        case femme

        private static let legacyFemmeAlias = String(
            decoding: [97, 110, 100, 114, 111, 103, 121, 110, 111, 117, 115],
            as: UTF8.self,
        )

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
                case Self.masc.rawValue:
                    self = .masc
                case Self.femme.rawValue, Self.legacyFemmeAlias:
                    self = .femme
                default:
                    let supportedValues = Self.allCases.map { $0.rawValue }.joined(separator: ", ")
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Unsupported vibe '\(rawValue)'. Expected one of: \(supportedValues).",
                    )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}
