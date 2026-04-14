import Foundation

// MARK: - SpeakSwiftly.DeepTrace

public extension SpeakSwiftly {
    enum DeepTrace {}
}

public extension SpeakSwiftly.DeepTrace {
    struct Features: Sendable, Equatable {
        public let originalCharacterCount: Int
        public let normalizedCharacterCount: Int
        public let normalizedCharacterDelta: Int
        public let originalParagraphCount: Int
        public let normalizedParagraphCount: Int
        public let markdownHeaderCount: Int
        public let fencedCodeBlockCount: Int
        public let inlineCodeSpanCount: Int
        public let markdownLinkCount: Int
        public let urlCount: Int
        public let filePathCount: Int
        public let dottedIdentifierCount: Int
        public let camelCaseTokenCount: Int
        public let snakeCaseTokenCount: Int
        public let objcSymbolCount: Int
        public let repeatedLetterRunCount: Int
    }

    enum SectionKind: String, Sendable, Equatable {
        case markdownHeader = "markdown_header"
        case paragraph
        case fullRequest = "full_request"
    }

    struct Section: Sendable, Equatable {
        public let index: Int
        public let title: String
        public let kind: SectionKind
        public let originalCharacterCount: Int
        public let normalizedCharacterCount: Int
        public let normalizedCharacterShare: Double
    }

    struct SectionWindow: Sendable, Equatable {
        public let section: Section
        public let estimatedStartMS: Int
        public let estimatedEndMS: Int
        public let estimatedDurationMS: Int
        public let estimatedStartChunk: Int
        public let estimatedEndChunk: Int
    }

    static func features(
        originalText: String,
        normalizedText: String,
    ) -> Features {
        DeepTraceAnalysis.features(
            originalText: originalText,
            normalizedText: normalizedText,
        )
    }

    static func sections(originalText: String) -> [Section] {
        DeepTraceAnalysis.sections(originalText: originalText)
    }

    static func sectionWindows(
        originalText: String,
        totalDurationMS: Int,
        totalChunkCount: Int,
    ) -> [SectionWindow] {
        DeepTraceAnalysis.sectionWindows(
            originalText: originalText,
            totalDurationMS: totalDurationMS,
            totalChunkCount: totalChunkCount,
        )
    }

    static func words(in text: String) -> [String] {
        DeepTraceAnalysis.words(in: text)
    }
}
