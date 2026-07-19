import Foundation

extension TextNormalizer {
    static func paragraphCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        return trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    static func applyReplacementRules(
        _ text: String,
        profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
        phase: SpeakSwiftlyNormalization.Replacement.Phase,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
    ) -> String {
        let replacements: [SpeakSwiftlyNormalization.Replacement] = switch format {
            case let .text(textFormat):
                profile.replacements(for: phase, in: textFormat)
            case let .source(sourceFormat):
                profile.replacements(for: phase, in: sourceFormat)
        }

        return replacements.reduce(text) { partial, rule in
            applyReplacementRule(
                rule,
                to: partial,
                profile: profile,
                requestContext: requestContext,
                format: format,
            )
        }
    }

    // MARK: Line and Token Transforms

    static func transformTokens(in text: String, transform: (String) -> String?) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }

            let rawToken = String(text[start..<index])
            result += transformedToken(rawToken, transform: transform)
        }

        return result
    }

    static func transformTokensStatefully<State>(
        in text: String,
        state: inout State,
        transform: (String, inout State) -> String?,
    ) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }

            let rawToken = String(text[start..<index])
            result += transformedToken(rawToken) { token in
                transform(token, &state)
            }
        }

        return result
    }

    static func transformLines(in text: String, transform: (String) -> String?) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let rawLine = String(line)
                return transform(rawLine) ?? rawLine
            }
            .joined(separator: "\n")
    }

    static func transformedToken(_ rawToken: String, transform: (String) -> String?) -> String {
        let punctuation = CharacterSet(charactersIn: "\"'()[]{}<>.,;:!?")
        var start = rawToken.startIndex
        var end = rawToken.endIndex

        while start < end,
              !preservesLeadingRelativePathPrefix(in: rawToken, at: start),
              rawToken[start].unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            start = rawToken.index(after: start)
        }

        while end > start {
            let beforeEnd = rawToken.index(before: end)
            if rawToken[beforeEnd] == ")" {
                let openIndex = rawToken.index(before: beforeEnd)
                if openIndex >= start, rawToken[openIndex] == "(" {
                    break
                }
            }
            guard rawToken[beforeEnd].unicodeScalars.allSatisfy({ punctuation.contains($0) }) else {
                break
            }

            end = beforeEnd
        }

        let prefix = rawToken[..<start]
        let core = String(rawToken[start..<end])
        let suffix = rawToken[end...]

        guard !core.isEmpty, let replacement = transform(core) else {
            return rawToken
        }

        return "\(prefix)\(replacement)\(suffix)"
    }

    static func trimmedCandidateToken(_ token: String) -> String {
        let punctuation = CharacterSet(charactersIn: "\"'()[]{}<>.,;:!?")
        var start = token.startIndex
        var end = token.endIndex

        while start < end,
              !preservesLeadingRelativePathPrefix(in: token, at: start),
              token[start].unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            start = token.index(after: start)
        }

        while end > start {
            let beforeEnd = token.index(before: end)
            if token[beforeEnd] == ")" {
                let openIndex = token.index(before: beforeEnd)
                if openIndex >= start, token[openIndex] == "(" {
                    break
                }
            }
            guard token[beforeEnd].unicodeScalars.allSatisfy({ punctuation.contains($0) }) else {
                break
            }

            end = beforeEnd
        }

        return String(token[start..<end])
    }

    static func preservesLeadingRelativePathPrefix(
        in token: String,
        at index: String.Index,
    ) -> Bool {
        guard token[index] == "." else { return false }

        let nextIndex = token.index(after: index)
        guard nextIndex < token.endIndex else { return false }

        if token[nextIndex] == "/" {
            return true
        }

        let secondIndex = token.index(after: nextIndex)
        return token[nextIndex] == "."
            && secondIndex < token.endIndex
            && token[secondIndex] == "/"
    }

    // MARK: Rule Application

    static func applyReplacementRule(
        _ rule: SpeakSwiftlyNormalization.Replacement,
        to text: String,
        profile: SpeakSwiftlyNormalization.Profile,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        format: NormalizationFormat,
    ) -> String {
        switch rule.match {
            case .exactPhrase:
                guard !rule.text.isEmpty else { return text }

                return text.replacingOccurrences(
                    of: rule.text,
                    with: resolvedReplacement(
                        for: rule.text,
                        rule: rule,
                        profile: profile,
                        requestContext: requestContext,
                        format: format,
                    ),
                    options: rule.isCaseSensitive ? [] : [.caseInsensitive],
                )

            case .wholeToken:
                guard !rule.text.isEmpty else { return text }

                return transformTokens(in: text) { token in
                    tokenMatches(rule.text, token: token, caseSensitive: rule.isCaseSensitive)
                        ? resolvedReplacement(
                            for: token,
                            rule: rule,
                            profile: profile,
                            requestContext: requestContext,
                            format: format,
                        )
                        : nil
                }

            case let .token(tokenKind):
                return transformTokens(in: text) { token in
                    tokenMatches(tokenKind, token: token)
                        ? resolvedReplacement(
                            for: token,
                            rule: rule,
                            profile: profile,
                            requestContext: requestContext,
                            format: format,
                        )
                        : nil
                }

            case let .line(lineKind):
                let lineInput = lineInputForLineRule(
                    rule,
                    lineKind: lineKind,
                    text: text,
                )

                return transformLines(in: lineInput) { line in
                    lineMatches(lineKind, line: line)
                        ? resolvedReplacement(
                            for: preparedLineForLineRule(
                                rule,
                                lineKind: lineKind,
                                line: line,
                            ),
                            rule: rule,
                            profile: profile,
                            requestContext: requestContext,
                            format: format,
                        )
                        : nil
                }
        }
    }

    private static func isSpokenCodeLineRule(_ rule: SpeakSwiftlyNormalization.Replacement) -> Bool {
        guard case .line = rule.match else { return false }
        guard case .spokenCode = rule.transform else { return false }

        return true
    }

    private static func lineInputForLineRule(
        _ rule: SpeakSwiftlyNormalization.Replacement,
        lineKind: SpeakSwiftlyNormalization.Replacement.LineKind,
        text: String,
    ) -> String {
        guard isSpokenCodeLineRule(rule), lineKind == .nonEmpty else { return text }

        return omittingMatchedSpeechDelimiters(in: text)
    }

    private static func preparedLineForLineRule(
        _ rule: SpeakSwiftlyNormalization.Replacement,
        lineKind: SpeakSwiftlyNormalization.Replacement.LineKind,
        line: String,
    ) -> String {
        line
    }

    static func resolvedReplacement(
        for text: String,
        rule: SpeakSwiftlyNormalization.Replacement,
        profile: SpeakSwiftlyNormalization.Profile,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        format: NormalizationFormat,
    ) -> String {
        switch rule.transform {
            case let .literal(replacement):
                replacement

            case .spokenPath:
                spokenPath(text, requestContext: requestContext)

            case .spokenURL:
                spokenURL(text)

            case .spokenCurrencyAmount:
                spokenCurrencyAmount(text)

            case .spokenMeasuredValue:
                spokenMeasuredValue(text)

            case .spokenIdentifier:
                spokenIdentifier(text)

            case .spokenCode:
                switch format {
                    case let .source(sourceFormat):
                        if isPreprocessedSourceLineForSpokenCode(rule) {
                            spokenCode(
                                text,
                                suppressingMatchedDelimiters: false,
                                doubleColonPolicy: doubleColonSpeechPolicy(for: profile),
                            )
                        } else {
                            spokenSource(text, format: sourceFormat, profile: profile)
                        }
                    case .text:
                        spokenCode(
                            text,
                            doubleColonPolicy: doubleColonSpeechPolicy(for: profile),
                        )
                }

            case let .spokenFunctionCall(style):
                spokenFunctionCall(text, style: style)

            case let .spokenIssueReference(style):
                spokenIssueReference(text, style: style)

            case let .spokenFileReference(style):
                spokenFileReference(text, style: style, requestContext: requestContext)

            case let .spokenCLIFlag(style):
                spokenCLIFlag(text, style: style)

            case .spellOut:
                spelledOut(trimmedCandidateToken(text))
        }
    }

    private static func isPreprocessedSourceLineForSpokenCode(
        _ rule: SpeakSwiftlyNormalization.Replacement,
    ) -> Bool {
        guard case .line(.nonEmpty) = rule.match else { return false }
        guard case .spokenCode = rule.transform else { return false }

        return true
    }
}
