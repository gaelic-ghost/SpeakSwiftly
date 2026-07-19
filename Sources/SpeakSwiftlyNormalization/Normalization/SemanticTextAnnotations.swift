import Foundation

extension TextNormalizer {
    enum SemanticTextKind: String, Codable, Equatable {
        case link
        case emailAddress
        case address
        case date
        case phoneNumber
        case filePath
        case fileLineReference
        case dottedIdentifier
        case snakeCaseIdentifier
        case dashedIdentifier
        case camelCaseIdentifier
        case functionCall
        case issueReference
        case cliFlag
    }

    struct SemanticTextRun: Equatable {
        let text: String
        let kind: SemanticTextKind?
    }

    private struct SemanticTokenTransform {
        let kind: SemanticTextKind
        let rule: SpeakSwiftlyNormalization.Replacement
    }

    static func semanticAttributedString(from text: String) -> AttributedString {
        var attributed = AttributedString(text)

        annotateDataDetectorTokens(in: &attributed, source: text)
        annotateDeveloperTokens(in: &attributed, source: text)

        return attributed
    }

    static func semanticRuns(in text: String) -> [SemanticTextRun] {
        let attributed = semanticAttributedString(from: text)
        return attributed.runs.map { run in
            SemanticTextRun(
                text: String(attributed[run.range].characters),
                kind: run[SemanticTextKindAttribute.self],
            )
        }
    }

    static func semanticTokenRuns(in text: String) -> [SemanticTextRun] {
        semanticRuns(in: text).filter { $0.kind != nil }
    }

    static func normalizeSemanticLinkRuns(_ text: String) -> String {
        semanticRuns(in: text)
            .map { run in
                run.kind == .link ? spokenURL(run.text) : run.text
            }
            .joined()
    }

    static func normalizeSemanticTokenRuns(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
        kinds: Set<SemanticTextKind>,
    ) -> String {
        guard !kinds.isEmpty else { return text }

        let transforms = semanticTokenTransforms(
            profile: profile,
            format: format,
            kinds: kinds,
        )
        guard !transforms.isEmpty else { return text }

        return semanticRuns(in: text)
            .map { run in
                guard let kind = run.kind,
                      let transform = transforms.first(where: { $0.kind == kind }) else {
                    return run.text
                }

                return resolvedReplacement(
                    for: run.text,
                    rule: transform.rule,
                    profile: profile,
                    requestContext: requestContext,
                    format: format,
                )
            }
            .joined()
    }

    static func applySemanticAwareReplacementRules(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
        phase: SpeakSwiftlyNormalization.Replacement.Phase,
        kinds: Set<SemanticTextKind>,
    ) -> String {
        guard !kinds.isEmpty else {
            return applyReplacementRules(
                text,
                profile: profile,
                format: format,
                phase: phase,
                requestContext: requestContext,
            )
        }

        return applicableReplacementRules(in: profile, format: format, phase: phase).reduce(text) { partial, rule in
            guard case let .token(tokenKind) = rule.match,
                  let kind = semanticKind(for: tokenKind),
                  kinds.contains(kind) else {
                return applyReplacementRule(
                    rule,
                    to: partial,
                    profile: profile,
                    requestContext: requestContext,
                    format: format,
                )
            }

            return applySemanticTokenRule(
                rule,
                kind: kind,
                to: partial,
                requestContext: requestContext,
                profile: profile,
                format: format,
            )
        }
    }

    private static func annotateDataDetectorTokens(
        in attributed: inout AttributedString,
        source text: String,
    ) {
        let detectorTypes = NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue

        guard let detector = try? NSDataDetector(types: detectorTypes) else { return }

        detector
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .forEach { match in
                guard let sourceRange = Range(match.range, in: text),
                      let kind = semanticKind(for: match) else {
                    return
                }

                applySemanticKind(kind, to: sourceRange, in: &attributed)
            }
    }

    private static func annotateDeveloperTokens(
        in attributed: inout AttributedString,
        source text: String,
    ) {
        var index = text.startIndex

        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }

            let tokenStart = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }

            let tokenRange = trimmedTokenRange(tokenStart..<index, in: text)
            let token = String(text[tokenRange])
            guard !token.isEmpty,
                  let kind = developerSemanticKind(for: token),
                  let attributedRange = Range<AttributedString.Index>(tokenRange, in: attributed),
                  !hasSemanticAnnotation(in: attributed, range: attributedRange) else {
                continue
            }

            attributed[attributedRange][SemanticTextKindAttribute.self] = kind
        }
    }

    private static func semanticKind(for match: NSTextCheckingResult) -> SemanticTextKind? {
        switch match.resultType {
            case .link:
                match.url?.scheme == "mailto" ? .emailAddress : .link
            case .address:
                .address
            case .date:
                .date
            case .phoneNumber:
                .phoneNumber
            default:
                nil
        }
    }

    private static func semanticTokenTransforms(
        profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
        kinds: Set<SemanticTextKind>,
    ) -> [SemanticTokenTransform] {
        applicableReplacementRules(in: profile, format: format, phase: .beforeBuiltIns).compactMap { rule in
            guard case let .token(tokenKind) = rule.match,
                  let kind = semanticKind(for: tokenKind),
                  kinds.contains(kind) else {
                return nil
            }

            return SemanticTokenTransform(kind: kind, rule: rule)
        }
    }

    private static func applicableReplacementRules(
        in profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
        phase: SpeakSwiftlyNormalization.Replacement.Phase,
    ) -> [SpeakSwiftlyNormalization.Replacement] {
        switch format {
            case let .text(textFormat):
                profile.replacements(for: phase, in: textFormat)
            case let .source(sourceFormat):
                profile.replacements(for: phase, in: sourceFormat)
        }
    }

    private static func applySemanticTokenRule(
        _ rule: SpeakSwiftlyNormalization.Replacement,
        kind: SemanticTextKind,
        to text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
    ) -> String {
        semanticRuns(in: text)
            .map { run in
                guard run.kind == kind else { return run.text }

                return resolvedReplacement(
                    for: run.text,
                    rule: rule,
                    profile: profile,
                    requestContext: requestContext,
                    format: format,
                )
            }
            .joined()
    }

    private static func semanticKind(
        for tokenKind: SpeakSwiftlyNormalization.Replacement.TokenKind,
    ) -> SemanticTextKind? {
        switch tokenKind {
            case .filePath:
                .filePath
            case .fileLineReference:
                .fileLineReference
            case .dottedIdentifier:
                .dottedIdentifier
            case .snakeCaseIdentifier:
                .snakeCaseIdentifier
            case .dashedIdentifier:
                .dashedIdentifier
            case .camelCaseIdentifier:
                .camelCaseIdentifier
            case .functionCall:
                .functionCall
            case .issueReference:
                .issueReference
            case .cliFlag:
                .cliFlag
            default:
                nil
        }
    }

    private static func developerSemanticKind(for token: String) -> SemanticTextKind? {
        if tokenMatches(.fileLineReference, token: token) { return .fileLineReference }
        if tokenMatches(.filePath, token: token) { return .filePath }
        if tokenMatches(.functionCall, token: token) { return .functionCall }
        if tokenMatches(.issueReference, token: token) { return .issueReference }
        if tokenMatches(.cliFlag, token: token) { return .cliFlag }
        if tokenMatches(.dottedIdentifier, token: token) { return .dottedIdentifier }
        if tokenMatches(.snakeCaseIdentifier, token: token) { return .snakeCaseIdentifier }
        if tokenMatches(.dashedIdentifier, token: token) { return .dashedIdentifier }
        if tokenMatches(.camelCaseIdentifier, token: token) { return .camelCaseIdentifier }

        return nil
    }

    private static func applySemanticKind(
        _ kind: SemanticTextKind,
        to sourceRange: Range<String.Index>,
        in attributed: inout AttributedString,
    ) {
        guard let attributedRange = Range<AttributedString.Index>(sourceRange, in: attributed) else {
            return
        }

        attributed[attributedRange][SemanticTextKindAttribute.self] = kind
    }

    private static func hasSemanticAnnotation(
        in attributed: AttributedString,
        range: Range<AttributedString.Index>,
    ) -> Bool {
        attributed[range].runs.contains { run in
            run[SemanticTextKindAttribute.self] != nil
        }
    }

    private static func trimmedTokenRange(
        _ range: Range<String.Index>,
        in text: String,
    ) -> Range<String.Index> {
        let punctuation = CharacterSet(charactersIn: "\"'()[]{}<>.,;:!?")
        var start = range.lowerBound
        var end = range.upperBound

        while start < end,
              !preservesLeadingRelativePathPrefix(in: text, at: start),
              text[start].unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            start = text.index(after: start)
        }

        while end > start {
            let beforeEnd = text.index(before: end)
            if text[beforeEnd] == ")" {
                let openIndex = text.index(before: beforeEnd)
                if openIndex >= start, text[openIndex] == "(" {
                    break
                }
            }
            guard text[beforeEnd].unicodeScalars.allSatisfy({ punctuation.contains($0) }) else {
                break
            }

            end = beforeEnd
        }

        return start..<end
    }
}

private struct SemanticTextKindAttribute: AttributedStringKey {
    typealias Value = TextNormalizer.SemanticTextKind

    static let name = "com.gaelic-ghost.SpeakSwiftlyNormalization.semanticTextKind"
}
