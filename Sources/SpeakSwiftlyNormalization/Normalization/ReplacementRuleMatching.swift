import Foundation

extension TextNormalizer {
    static func tokenMatches(_ expected: String, token: String, caseSensitive: Bool) -> Bool {
        caseSensitive
            ? token == expected
            : token.compare(expected, options: [.caseInsensitive]) == .orderedSame
    }

    static func tokenMatches(
        _ tokenKind: SpeakSwiftlyNormalization.Replacement.TokenKind,
        token: String,
    ) -> Bool {
        switch tokenKind {
            case .filePath:
                isLikelyFilePath(token)
            case .url:
                isLikelyURL(token)
            case .currencyAmount:
                isLikelyCurrencyAmount(token)
            case .measuredValue:
                isLikelyMeasuredValue(token)
            case .dottedIdentifier:
                isLikelyDottedIdentifier(token)
            case .snakeCaseIdentifier:
                isLikelySnakeCaseIdentifier(token)
            case .dashedIdentifier:
                isLikelyDashedIdentifier(token)
            case .camelCaseIdentifier:
                isLikelyCamelCaseIdentifier(token)
            case .functionCall:
                isLikelyFunctionCall(token)
            case .issueReference:
                isLikelyIssueReference(token)
            case .fileLineReference:
                isLikelyFileLineReference(token)
            case .cliFlag:
                isLikelyCLIFlag(token)
            case .repeatedLetterRun:
                containsRepeatedLetterRun(trimmedCandidateToken(token))
        }
    }

    static func lineMatches(
        _ lineKind: SpeakSwiftlyNormalization.Replacement.LineKind,
        line: String,
    ) -> Bool {
        switch lineKind {
            case .codeLike:
                isLikelyCodeLine(line)
            case .nonEmpty:
                !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
