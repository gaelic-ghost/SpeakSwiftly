import Foundation

extension TextNormalizer {
    // MARK: Source Line Normalization

    static func normalizeStructuredSourceLines(
        _ text: String,
        format: SpeakSwiftlyNormalization.SourceFormat,
    ) -> String {
        applySingleBaseRule(
            id: "base-source-line",
            to: text,
            format: .source(format),
        )
    }

    // MARK: Token-Level Passes

    static func normalizeURLs(_ text: String) -> String {
        normalizeSemanticLinkRuns(text)
    }

    static func normalizeFilePaths(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile _: SpeakSwiftlyNormalization.Profile = .default,
        format _: NormalizationFormat = .text(.plain),
    ) -> String {
        applySingleBaseRule(
            id: "base-file-path",
            to: text,
            format: .text(.plain),
            requestContext: requestContext,
        )
    }

    // MARK: Code-Like Line Passes

    static func normalizeCodeHeavyLines(
        _ text: String,
        format: NormalizationFormat,
    ) -> String {
        let ruleID = switch format {
            case .text:
                "base-text-code-line"
            case .source:
                "base-source-line"
        }

        return applySingleBaseRule(
            id: ruleID,
            to: text,
            format: format,
        )
    }

    // MARK: Natural Language Passes

    static func normalizeSpiralProneWords(_ text: String) -> String {
        applySingleBaseRule(
            id: "base-repeated-letter-run",
            to: text,
            format: .text(.plain),
        )
    }

    // MARK: Base Rule Helpers

    private static func applySingleBaseRule(
        id: String,
        to text: String,
        format: NormalizationFormat,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
    ) -> String {
        guard let rule = SpeakSwiftlyNormalization.Profile.base.replacement(id: id) else { return text }

        return applyReplacementRules(
            text,
            profile: SpeakSwiftlyNormalization.Profile(
                id: "base-\(id)",
                name: "Base \(id)",
                replacements: [rule],
            ),
            format: format,
            phase: .beforeBuiltIns,
            requestContext: requestContext,
        )
    }
}
