import Foundation
import NaturalLanguage
import RegexBuilder

enum TextNormalizer {
    // MARK: Pass Types

    typealias NormalizationPass = (String) -> String
    typealias ContextualNormalizationPass =
        (
            String,
            SpeakSwiftlyNormalization.RequestContext?,
            SpeakSwiftlyNormalization.Profile,
            NormalizationFormat,
        ) -> String

    // MARK: Pass Pipelines

    static let semanticRunTokenKinds: Set<SemanticTextKind> = [
        .filePath,
        .fileLineReference,
        .functionCall,
        .issueReference,
        .cliFlag,
        .dottedIdentifier,
        .snakeCaseIdentifier,
        .dashedIdentifier,
        .camelCaseIdentifier,
    ]

    // MARK: Detection Markers

    static var codeMarkerRegex: Regex<Substring> {
        Regex {
            ChoiceOf {
                "```"
                "`"
                "->"
                "=>"
                "::"
                "?."
                "??"
                "&&"
                "||"
                "=="
                "!="
                "{"
                "}"
                "</"
                "/>"
                "func "
                "let "
                "var "
                "const "
                "class "
                "struct "
                "enum "
                "return "
            }
        }
    }

    static var normalizationPasses: [ContextualNormalizationPass] {
        [
            { text, requestContext, profile, _ in
                normalizeFencedCodeBlocks(
                    text,
                    requestContext: requestContext,
                    profile: profile,
                )
            },
            { text, _, _, _ in normalizeMarkdownTablesForSpeech(text) },
            { text, requestContext, profile, _ in
                normalizeInlineCodeSpans(
                    text,
                    requestContext: requestContext,
                    profile: profile,
                )
            },
            { text, _, _, _ in normalizeMarkdownLinks(text) },
            { text, _, _, _ in normalizePriorityListItems(text) },
            { text, _, _, _ in normalizeSemanticLinkRuns(text) },
            { text, requestContext, _, _ in
                compactRepeatedFilePathPrefixes(text, requestContext: requestContext)
            },
            { text, _, _, _ in normalizeSpacedMeasuredValues(text) },
            { text, requestContext, profile, format in
                applySemanticAwareReplacementRules(
                    text,
                    requestContext: requestContext,
                    profile: profile,
                    format: format,
                    phase: .beforeBuiltIns,
                    kinds: semanticRunTokenKinds,
                )
            },
            { text, _, _, _ in normalizeWhitespacePreservingLineBreaks(text) },
        ]
    }

    static var sourceNormalizationPasses: [ContextualNormalizationPass] {
        [
            { text, _, _, _ in normalizeSemanticLinkRuns(text) },
            { text, _, _, _ in normalizeSpacedMeasuredValues(text) },
            { text, requestContext, profile, format in
                applySemanticAwareReplacementRules(
                    text,
                    requestContext: requestContext,
                    profile: profile,
                    format: format,
                    phase: .beforeBuiltIns,
                    kinds: semanticRunTokenKinds,
                )
            },
            { text, _, _, _ in normalizeWhitespacePreservingLineBreaks(text) },
        ]
    }

    // MARK: Public Entry Points

    static func normalizeText(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .default,
        format: SpeakSwiftlyNormalization.TextFormat? = nil,
    ) -> String {
        let resolvedFormat = format ?? detectTextFormat(in: text)
        return normalize(
            canonicalize(text),
            requestContext: requestContext,
            profile: profile,
            format: .text(resolvedFormat),
            passes: normalizationPasses,
        )
    }

    static func normalizeSource(
        _ source: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .default,
        format: SpeakSwiftlyNormalization.SourceFormat,
    ) -> String {
        normalize(
            canonicalize(source),
            requestContext: requestContext,
            profile: profile,
            format: .source(format),
            passes: sourceNormalizationPasses,
        )
    }

    // MARK: Pipeline Driver

    private static func normalize(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        profile: SpeakSwiftlyNormalization.Profile,
        format: NormalizationFormat,
        passes: [ContextualNormalizationPass],
    ) -> String {
        let normalized = passes.reduce(text) { partial, pass in
            pass(partial, requestContext, profile, format)
        }
        let finalized = normalizeWhitespacePreservingLineBreaks(
            applyReplacementRules(
                normalized,
                profile: profile,
                format: format,
                phase: .afterBuiltIns,
                requestContext: requestContext,
            ),
        )
        return finalized.isEmpty ? text : finalized
    }
}
