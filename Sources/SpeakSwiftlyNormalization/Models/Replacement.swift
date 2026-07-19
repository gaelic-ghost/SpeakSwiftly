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
            text = ""
            self.transform = transform
            self.match = match
            self.phase = phase
            self.isCaseSensitive = isCaseSensitive
            self.textFormats = textFormats
            self.sourceFormats = sourceFormats
            self.priority = priority
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
