import SpeakSwiftly

struct ReplacementPayload: Decodable {
    private enum MatchPayload: Decodable {
        case value(SpeakSwiftly.TextReplacement.Match)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            switch try container.decode(String.self) {
                case "exact_phrase": self = .value(.exactPhrase)
                case "whole_token": self = .value(.wholeToken)
                default:
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Replacement 'match' must be 'exact_phrase' or 'whole_token'.",
                    )
            }
        }

        var value: SpeakSwiftly.TextReplacement.Match {
            switch self { case let .value(value): value }
        }
    }

    private enum TransformPayload: Decodable {
        case value(SpeakSwiftly.TextReplacement.Transform)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            switch try container.decode(String.self) {
                case "spoken_path": self = .value(.spokenPath)
                case "spoken_url": self = .value(.spokenURL)
                case "spoken_identifier": self = .value(.spokenIdentifier)
                case "spoken_code": self = .value(.spokenCode)
                case "spell_out": self = .value(.spellOut)
                default:
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Replacement 'transform' is not a supported worker transform.",
                    )
            }
        }

        var value: SpeakSwiftly.TextReplacement.Transform {
            switch self { case let .value(value): value }
        }
    }

    let id: String
    let text: String
    let replacement: String?
    let phase: SpeakSwiftly.TextReplacement.Phase
    let isCaseSensitive: Bool
    let textFormats: Set<SpeakSwiftly.TextFormat>
    let sourceFormats: Set<SpeakSwiftly.SourceFormat>
    let priority: Int

    private let transform: TransformPayload?
    private let match: MatchPayload

    func resolved() throws -> SpeakSwiftly.TextReplacement {
        if let replacement {
            return SpeakSwiftly.TextReplacement(
                text,
                with: replacement,
                id: id,
                matching: match.value,
                during: phase,
                caseSensitive: isCaseSensitive,
                forTextFormats: textFormats,
                forSourceFormats: sourceFormats,
                priority: priority,
            )
        }
        guard let transform else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Replacement payload must provide 'replacement' or 'transform'.",
                ),
            )
        }

        return SpeakSwiftly.TextReplacement(
            id: id,
            matching: match.value,
            using: transform.value,
            during: phase,
            caseSensitive: isCaseSensitive,
            forTextFormats: textFormats,
            forSourceFormats: sourceFormats,
            priority: priority,
        )
    }
}
