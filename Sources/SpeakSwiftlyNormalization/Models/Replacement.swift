import Foundation

public extension SpeakSwiftlyNormalization {
    struct Replacement: Codable, Sendable, Equatable, Identifiable {
        public enum Match: Codable, Sendable, Equatable {
            case exactPhrase
            case wholeToken
            case token(TokenKind)
            case line(LineKind)
        }

        public enum Phase: String, Codable, Sendable {
            case beforeBuiltIns = "before_built_ins"
            case afterBuiltIns = "after_built_ins"
        }

        public enum TokenKind: String, Codable, Sendable, CaseIterable {
            case filePath = "file_path"
            case url
            case currencyAmount = "currency_amount"
            case measuredValue = "measured_value"
            case dottedIdentifier = "dotted_identifier"
            case snakeCaseIdentifier = "snake_case_identifier"
            case dashedIdentifier = "dashed_identifier"
            case camelCaseIdentifier = "camel_case_identifier"
            case functionCall = "function_call"
            case issueReference = "issue_reference"
            case fileLineReference = "file_line_reference"
            case cliFlag = "cli_flag"
            case repeatedLetterRun = "repeated_letter_run"
        }

        public enum LineKind: String, Codable, Sendable, CaseIterable {
            case codeLike = "code_like"
            case nonEmpty = "non_empty"
        }

        public enum Transform: Codable, Sendable, Equatable {
            public enum FunctionCallStyle: String, Codable, Sendable, Equatable {
                case compact
                case balanced
                case explicit
            }

            public enum IssueReferenceStyle: String, Codable, Sendable, Equatable {
                case compact
                case balanced
                case explicit
            }

            public enum FileReferenceStyle: String, Codable, Sendable, Equatable {
                case compact
                case balanced
                case explicit
            }

            public enum CLIFlagStyle: String, Codable, Sendable, Equatable {
                case compact
                case balanced
                case explicit
            }

            case literal(String)
            case spokenPath
            case spokenURL
            case spokenCurrencyAmount
            case spokenMeasuredValue
            case spokenIdentifier
            case spokenCode
            case spokenFunctionCall(FunctionCallStyle)
            case spokenIssueReference(IssueReferenceStyle)
            case spokenFileReference(FileReferenceStyle)
            case spokenCLIFlag(CLIFlagStyle)
            case spellOut
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case text
            case replacement
            case transform
            case match
            case phase
            case isCaseSensitive
            case textFormats
            case sourceFormats
            case priority
        }

        public let id: String
        public let text: String
        public let transform: Transform
        public let match: Match
        public let phase: Phase
        public let isCaseSensitive: Bool
        public let textFormats: Set<TextFormat>
        public let sourceFormats: Set<SourceFormat>
        public let priority: Int

        public var replacement: String? {
            guard case let .literal(replacement) = transform else { return nil }

            return replacement
        }

        public init(
            _ text: String,
            with replacement: String,
            id: String = UUID().uuidString,
            matching match: Match = .exactPhrase,
            during phase: Phase = .beforeBuiltIns,
            caseSensitive isCaseSensitive: Bool = false,
            forTextFormats textFormats: Set<TextFormat> = [],
            forSourceFormats sourceFormats: Set<SourceFormat> = [],
            priority: Int = 0,
        ) {
            self.id = id
            self.text = text
            transform = .literal(replacement)
            self.match = match
            self.phase = phase
            self.isCaseSensitive = isCaseSensitive
            self.textFormats = textFormats
            self.sourceFormats = sourceFormats
            self.priority = priority
        }

        public init(
            _ text: String,
            id: String = UUID().uuidString,
            matching match: Match,
            using transform: Transform,
            during phase: Phase = .beforeBuiltIns,
            caseSensitive isCaseSensitive: Bool = false,
            forTextFormats textFormats: Set<TextFormat> = [],
            forSourceFormats sourceFormats: Set<SourceFormat> = [],
            priority: Int = 0,
        ) {
            self.id = id
            self.text = text
            self.transform = transform
            self.match = match
            self.phase = phase
            self.isCaseSensitive = isCaseSensitive
            self.textFormats = textFormats
            self.sourceFormats = sourceFormats
            self.priority = priority
        }

        public init(
            id: String = UUID().uuidString,
            matching match: Match,
            using transform: Transform,
            during phase: Phase = .beforeBuiltIns,
            caseSensitive isCaseSensitive: Bool = false,
            forTextFormats textFormats: Set<TextFormat> = [],
            forSourceFormats sourceFormats: Set<SourceFormat> = [],
            priority: Int = 0,
        ) {
            self.init(
                "",
                id: id,
                matching: match,
                using: transform,
                during: phase,
                caseSensitive: isCaseSensitive,
                forTextFormats: textFormats,
                forSourceFormats: sourceFormats,
                priority: priority,
            )
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            text = try container.decode(String.self, forKey: .text)
            phase = try container.decode(Phase.self, forKey: .phase)
            isCaseSensitive = try container.decode(Bool.self, forKey: .isCaseSensitive)
            textFormats = try container.decode(Set<TextFormat>.self, forKey: .textFormats)
            sourceFormats = try container.decode(Set<SourceFormat>.self, forKey: .sourceFormats)
            priority = try container.decode(Int.self, forKey: .priority)

            if let wireMatch = try? container.decode(String.self, forKey: .match) {
                match = try Match(wireValue: wireMatch, codingPath: container.codingPath + [CodingKeys.match])
            } else {
                match = try container.decode(LegacyMatch.self, forKey: .match).value
            }

            if let literal = try container.decodeIfPresent(String.self, forKey: .replacement) {
                transform = .literal(literal)
            } else if let wireTransform = try? container.decode(String.self, forKey: .transform) {
                transform = try Transform(wireValue: wireTransform, codingPath: container.codingPath + [CodingKeys.transform])
            } else {
                transform = try container.decode(LegacyTransform.self, forKey: .transform).value
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encode(match.wireValue, forKey: .match)
            try container.encode(phase, forKey: .phase)
            try container.encode(isCaseSensitive, forKey: .isCaseSensitive)
            try container.encode(textFormats, forKey: .textFormats)
            try container.encode(sourceFormats, forKey: .sourceFormats)
            try container.encode(priority, forKey: .priority)

            if let replacement {
                try container.encode(replacement, forKey: .replacement)
            } else {
                try container.encode(transform.wireValue, forKey: .transform)
            }
        }

        public func applies(to format: TextFormat) -> Bool {
            guard !textFormats.isEmpty || !sourceFormats.isEmpty else { return true }

            return textFormats.contains(format)
        }

        public func applies(to format: SourceFormat) -> Bool {
            guard !textFormats.isEmpty || !sourceFormats.isEmpty else { return true }

            return sourceFormats.contains(.generic) || sourceFormats.contains(format)
        }
    }
}

private extension SpeakSwiftlyNormalization.Replacement.Match {
    var wireValue: String {
        switch self {
            case .exactPhrase: "exact_phrase"
            case .wholeToken: "whole_token"
            case let .token(kind): "token:\(kind.rawValue)"
            case let .line(kind): "line:\(kind.rawValue)"
        }
    }

    init(wireValue: String, codingPath: [any CodingKey]) throws {
        switch wireValue {
            case "exact_phrase": self = .exactPhrase
            case "whole_token": self = .wholeToken
            default:
                if wireValue.hasPrefix("token:"),
                   let kind = SpeakSwiftlyNormalization.Replacement.TokenKind(rawValue: String(wireValue.dropFirst("token:".count))) {
                    self = .token(kind)
                } else if wireValue.hasPrefix("line:"),
                          let kind = SpeakSwiftlyNormalization.Replacement.LineKind(rawValue: String(wireValue.dropFirst("line:".count))) {
                    self = .line(kind)
                } else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: codingPath,
                            debugDescription: "Replacement 'match' value '\(wireValue)' is not supported by SpeakSwiftly.",
                        ),
                    )
                }
        }
    }
}

private extension SpeakSwiftlyNormalization.Replacement.Transform {
    var wireValue: String {
        switch self {
            case .literal: preconditionFailure("Literal replacements encode through the 'replacement' field.")
            case .spokenPath: "spoken_path"
            case .spokenURL: "spoken_url"
            case .spokenCurrencyAmount: "spoken_currency_amount"
            case .spokenMeasuredValue: "spoken_measured_value"
            case .spokenIdentifier: "spoken_identifier"
            case .spokenCode: "spoken_code"
            case let .spokenFunctionCall(style): "spoken_function_call:\(style.rawValue)"
            case let .spokenIssueReference(style): "spoken_issue_reference:\(style.rawValue)"
            case let .spokenFileReference(style): "spoken_file_reference:\(style.rawValue)"
            case let .spokenCLIFlag(style): "spoken_cli_flag:\(style.rawValue)"
            case .spellOut: "spell_out"
        }
    }

    init(wireValue: String, codingPath: [any CodingKey]) throws {
        switch wireValue {
            case "spoken_path": self = .spokenPath
            case "spoken_url": self = .spokenURL
            case "spoken_currency_amount": self = .spokenCurrencyAmount
            case "spoken_measured_value": self = .spokenMeasuredValue
            case "spoken_identifier": self = .spokenIdentifier
            case "spoken_code": self = .spokenCode
            case "spell_out": self = .spellOut
            default:
                if wireValue.hasPrefix("spoken_function_call:"),
                   let style = FunctionCallStyle(rawValue: String(wireValue.dropFirst("spoken_function_call:".count))) {
                    self = .spokenFunctionCall(style)
                } else if wireValue.hasPrefix("spoken_issue_reference:"),
                          let style = IssueReferenceStyle(rawValue: String(wireValue.dropFirst("spoken_issue_reference:".count))) {
                    self = .spokenIssueReference(style)
                } else if wireValue.hasPrefix("spoken_file_reference:"),
                          let style = FileReferenceStyle(rawValue: String(wireValue.dropFirst("spoken_file_reference:".count))) {
                    self = .spokenFileReference(style)
                } else if wireValue.hasPrefix("spoken_cli_flag:"),
                          let style = CLIFlagStyle(rawValue: String(wireValue.dropFirst("spoken_cli_flag:".count))) {
                    self = .spokenCLIFlag(style)
                } else {
                    throw DecodingError.dataCorrupted(
                        .init(
                            codingPath: codingPath,
                            debugDescription: "Replacement 'transform' value '\(wireValue)' is not supported by SpeakSwiftly.",
                        ),
                    )
                }
        }
    }
}

private extension SpeakSwiftlyNormalization.Replacement {
    enum LegacyMatch: Codable {
        case exactPhrase
        case wholeToken
        case token(TokenKind)
        case line(LineKind)

        var value: Match {
            switch self {
                case .exactPhrase: .exactPhrase
                case .wholeToken: .wholeToken
                case let .token(kind): .token(kind)
                case let .line(kind): .line(kind)
            }
        }
    }

    enum LegacyTransform: Codable {
        case literal(String)
        case spokenPath
        case spokenURL
        case spokenCurrencyAmount
        case spokenMeasuredValue
        case spokenIdentifier
        case spokenCode
        case spokenFunctionCall(Transform.FunctionCallStyle)
        case spokenIssueReference(Transform.IssueReferenceStyle)
        case spokenFileReference(Transform.FileReferenceStyle)
        case spokenCLIFlag(Transform.CLIFlagStyle)
        case spellOut

        var value: Transform {
            switch self {
                case let .literal(value): .literal(value)
                case .spokenPath: .spokenPath
                case .spokenURL: .spokenURL
                case .spokenCurrencyAmount: .spokenCurrencyAmount
                case .spokenMeasuredValue: .spokenMeasuredValue
                case .spokenIdentifier: .spokenIdentifier
                case .spokenCode: .spokenCode
                case let .spokenFunctionCall(style): .spokenFunctionCall(style)
                case let .spokenIssueReference(style): .spokenIssueReference(style)
                case let .spokenFileReference(style): .spokenFileReference(style)
                case let .spokenCLIFlag(style): .spokenCLIFlag(style)
                case .spellOut: .spellOut
            }
        }
    }
}
