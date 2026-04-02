import Foundation

// MARK: - Speech Text Normalization

struct SpeechTextForensicFeatures: Sendable, Equatable {
    let originalCharacterCount: Int
    let normalizedCharacterCount: Int
    let normalizedCharacterDelta: Int
    let originalParagraphCount: Int
    let normalizedParagraphCount: Int
    let markdownHeaderCount: Int
    let fencedCodeBlockCount: Int
    let inlineCodeSpanCount: Int
    let markdownLinkCount: Int
    let filePathCount: Int
    let dottedIdentifierCount: Int
    let camelCaseTokenCount: Int
    let snakeCaseTokenCount: Int
    let objcSymbolCount: Int
    let repeatedLetterRunCount: Int
    let punctuationHeavyLineCount: Int
    let looksCodeHeavy: Bool
}

enum SpeechTextForensicSectionKind: String, Sendable, Equatable {
    case markdownHeader = "markdown_header"
    case paragraph
    case fullRequest = "full_request"
}

struct SpeechTextForensicSection: Sendable, Equatable {
    let index: Int
    let title: String
    let kind: SpeechTextForensicSectionKind
    let originalCharacterCount: Int
    let normalizedCharacterCount: Int
    let normalizedCharacterShare: Double
}

struct SpeechTextForensicSectionWindow: Sendable, Equatable {
    let section: SpeechTextForensicSection
    let estimatedStartMS: Int
    let estimatedEndMS: Int
    let estimatedDurationMS: Int
    let estimatedStartChunk: Int
    let estimatedEndChunk: Int
}

enum SpeechTextNormalizer {
    static func normalize(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        if containsCorrectableText(normalized) {
            normalized = normalizeFencedCodeBlocks(normalized)
            normalized = normalizeInlineCode(normalized)
            normalized = normalizeMarkdownLinks(normalized)
            normalized = normalizeFilePaths(normalized)
            normalized = normalizeIdentifierTokens(normalized)

            if looksCodeHeavy(normalized) {
                normalized = spokenCode(normalized)
            }

            normalized = collapseWhitespace(normalized)
        }

        let finalized = collapseWhitespace(normalized)
        return finalized.isEmpty ? text : finalized
    }

    static func forensicFeatures(originalText: String, normalizedText: String) -> SpeechTextForensicFeatures {
        SpeechTextForensicFeatures(
            originalCharacterCount: originalText.count,
            normalizedCharacterCount: normalizedText.count,
            normalizedCharacterDelta: normalizedText.count - originalText.count,
            originalParagraphCount: paragraphCount(in: originalText),
            normalizedParagraphCount: paragraphCount(in: normalizedText),
            markdownHeaderCount: regexMatchCount(in: originalText, pattern: #"(?m)^\s{0,3}#{1,6}\s+\S.*$"#),
            fencedCodeBlockCount: regexMatchCount(in: originalText, pattern: #"```"#) / 2,
            inlineCodeSpanCount: regexMatchCount(in: originalText, pattern: #"`[^`\n]+`"#),
            markdownLinkCount: regexMatchCount(in: originalText, pattern: #"\[[^\]]+\]\([^)]+\)"#),
            filePathCount: regexMatchCount(in: originalText, pattern: #"(?<!\w)(?:~|/)[^\s`),;]+"#),
            dottedIdentifierCount: regexMatchCount(in: originalText, pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b"#),
            camelCaseTokenCount: regexMatchCount(in: originalText, pattern: #"\b[a-z]+(?:[A-Z][a-z0-9]+)+\b"#),
            snakeCaseTokenCount: regexMatchCount(in: originalText, pattern: #"\b[a-z0-9]+(?:_[a-z0-9]+)+\b"#),
            objcSymbolCount: regexMatchCount(in: originalText, pattern: #"\b[A-Z]{2,}[A-Za-z0-9]*(?::[A-Za-z0-9]+)+\b|\bNS[A-Z][A-Za-z0-9]+\b"#),
            repeatedLetterRunCount: regexMatchCount(in: originalText, pattern: #"(?i)\b\w*([a-z])\1{2,}\w*\b"#),
            punctuationHeavyLineCount: punctuationHeavyLineCount(in: originalText),
            looksCodeHeavy: looksCodeHeavy(originalText)
        )
    }

    static func forensicSections(originalText: String) -> [SpeechTextForensicSection] {
        let sections = splitForensicSections(in: originalText)
        let weightedCounts = sections.map { max(normalize($0.text).count, 1) }
        let totalWeightedCount = max(weightedCounts.reduce(0, +), 1)

        let finalizedSections = sections.enumerated().map { index, section in
            SpeechTextForensicSection(
                index: index + 1,
                title: section.title,
                kind: section.kind,
                originalCharacterCount: section.text.count,
                normalizedCharacterCount: weightedCounts[index],
                normalizedCharacterShare: Double(weightedCounts[index]) / Double(totalWeightedCount)
            )
        }
        return finalizedSections
    }

    static func forensicSectionWindows(
        originalText: String,
        totalDurationMS: Int,
        totalChunkCount: Int
    ) -> [SpeechTextForensicSectionWindow] {
        let sections = forensicSections(originalText: originalText)
        guard !sections.isEmpty else { return [] }

        var elapsedMS = 0
        var elapsedChunks = 0
        let windows = sections.enumerated().map { index, section in
            let isLastSection = index == sections.count - 1
            let remainingDurationMS = max(totalDurationMS - elapsedMS, 0)
            let remainingChunkCount = max(totalChunkCount - elapsedChunks, 0)
            let durationMS = isLastSection
                ? remainingDurationMS
                : min(
                    remainingDurationMS,
                    max(Int((Double(totalDurationMS) * section.normalizedCharacterShare).rounded()), 0)
                )
            let chunkCount = isLastSection
                ? remainingChunkCount
                : min(
                    remainingChunkCount,
                    max(Int((Double(totalChunkCount) * section.normalizedCharacterShare).rounded()), 0)
                )

            let window = SpeechTextForensicSectionWindow(
                section: section,
                estimatedStartMS: elapsedMS,
                estimatedEndMS: elapsedMS + durationMS,
                estimatedDurationMS: durationMS,
                estimatedStartChunk: elapsedChunks,
                estimatedEndChunk: elapsedChunks + chunkCount
            )
            elapsedMS += durationMS
            elapsedChunks += chunkCount
            return window
        }

        return windows
    }

    private static func containsCorrectableText(_ text: String) -> Bool {
        let markers = ["```", "`", "[", "](", "->", "=>", "::", "?.", "??"]
        if markers.contains(where: text.contains) {
            return true
        }

        return looksCodeHeavy(text)
    }

    private static func normalizeFencedCodeBlocks(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?s)```(?:[\w.+-]+)?\n?(.*?)```"#
        ) { match, source in
            let body = source.substring(with: match.range(at: 1))
            let spoken = spokenCode(body)
            return spoken.isEmpty ? " Code sample. " : " Code sample. \(spoken). End code sample. "
        }
    }

    private static func normalizeInlineCode(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?s)`([^`]+)`"#
        ) { match, source in
            let body = source.substring(with: match.range(at: 1))
            let spoken = spokenCode(body)
            return spoken.isEmpty ? " code " : " \(spoken) "
        }
    }

    private static func normalizeMarkdownLinks(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"\[([^\]]+)\]\(([^)]+)\)"#
        ) { match, source in
            let label = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let link = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { return " \(link) " }
            return " \(label), link \(link) "
        }
    }

    private static func normalizeFilePaths(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?<!\w)(~|/)[^\s`),;]+"#
        ) { match, source in
            let path = source.substring(with: match.range(at: 0))
            return " \(spokenPath(path)) "
        }
    }

    private static func normalizeIdentifierTokens(_ text: String) -> String {
        let dottedNormalized = replacingMatches(
            in: text,
            pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b"#
        ) { match, source in
            let token = source.substring(with: match.range(at: 0))
            return " \(spokenIdentifier(token)) "
        }

        let snakeNormalized = replacingMatches(
            in: dottedNormalized,
            pattern: #"\b[a-z0-9]+(?:_[a-z0-9]+)+\b"#
        ) { match, source in
            let token = source.substring(with: match.range(at: 0))
            return " \(spokenIdentifier(token)) "
        }

        return replacingMatches(
            in: snakeNormalized,
            pattern: #"\b[a-z]+(?:[A-Z][a-z0-9]+)+\b"#
        ) { match, source in
            let token = source.substring(with: match.range(at: 0))
            return " \(spokenIdentifier(token)) "
        }
    }

    private static func looksCodeHeavy(_ text: String) -> Bool {
        let obviousMarkers = [
            "```", "`", "->", "=>", "::", "&&", "||", "==", "!=", "{", "}", "</", "/>",
            "func ", "let ", "var ", "const ", "class ", "struct ", "enum ", "return "
        ]
        if obviousMarkers.contains(where: text.contains) {
            return true
        }

        let codeCharacters = text.filter { "{}[]()<>/\\=_*#|~:;".contains($0) }.count
        let letterCharacters = text.filter(\.isLetter).count
        guard letterCharacters > 0 else { return codeCharacters > 0 }
        return Double(codeCharacters) / Double(letterCharacters) >= 0.12
    }

    private static func paragraphCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let normalizedBreaks = trimmed.replacingOccurrences(
            of: #"\n\s*\n"#,
            with: "\n\n",
            options: .regularExpression
        )
        return normalizedBreaks.components(separatedBy: "\n\n").count
    }

    private static func punctuationHeavyLineCount(in text: String) -> Int {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reduce(into: 0) { count, rawLine in
                let line = String(rawLine)
                let punctuation = line.filter { "{}[]()<>/\\=_*#|~:;.`-".contains($0) }.count
                let letters = line.filter(\.isLetter).count
                let containsStructuredCodeMarker =
                    line.contains("@property")
                    || line.contains("[")
                    || line.contains("]")
                    || line.contains("://")
                    || line.contains("/")
                    || line.contains("::")
                    || line.contains("->")
                    || line.contains("?.")
                    || line.contains("??")

                if punctuation >= 6 && (punctuation * 2 >= max(letters, 4) || containsStructuredCodeMarker) {
                    count += 1
                }
            }
    }

    private static func regexMatchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.numberOfMatches(in: text, range: range)
    }

    private static func spokenCode(_ text: String) -> String {
        let replacements: [(String, String)] = [
            ("\n", ". "),
            ("->", " returns "),
            ("=>", " maps to "),
            ("===", " strictly equals "),
            ("!==", " not strictly equals "),
            ("==", " equals equals "),
            ("!=", " not equals "),
            ("&&", " and "),
            ("||", " or "),
            ("::", " double colon "),
            ("?.", " optional chaining "),
            ("??", " nil coalescing "),
            ("...", " ellipsis "),
            ("_", " underscore "),
            ("#", " hash "),
            ("*", " star "),
            ("{", " open brace "),
            ("}", " close brace "),
            ("[", " open bracket "),
            ("]", " close bracket "),
            ("(", " open parenthesis "),
            (")", " close parenthesis "),
            ("<", " less than "),
            (">", " greater than "),
            ("/", " slash "),
            ("\\", " backslash "),
            (":", " colon "),
            (";", " semicolon "),
            ("=", " equals "),
        ]

        var spoken = text
        for (source, replacement) in replacements {
            spoken = spoken.replacingOccurrences(of: source, with: replacement)
        }

        spoken = replacingMatches(
            in: spoken,
            pattern: #"([a-z0-9])([A-Z])"#
        ) { match, source in
            let lhs = source.substring(with: match.range(at: 1))
            let rhs = source.substring(with: match.range(at: 2))
            return "\(lhs) \(rhs)"
        }

        return collapseWhitespace(spoken)
    }

    private static func spokenPath(_ text: String) -> String {
        var spoken = text
        if spoken.hasPrefix("~") {
            spoken = spoken.replacingOccurrences(of: "~", with: "home", options: [], range: spoken.startIndex..<spoken.index(after: spoken.startIndex))
        }

        spoken = spoken
            .replacingOccurrences(of: "/", with: " slash ")
            .replacingOccurrences(of: "\\", with: " backslash ")
            .replacingOccurrences(of: ".", with: " dot ")
            .replacingOccurrences(of: "_", with: " underscore ")
            .replacingOccurrences(of: "-", with: " dash ")

        return collapseWhitespace(spoken)
    }

    private static func spokenIdentifier(_ text: String) -> String {
        var spoken = text
            .replacingOccurrences(of: ".", with: " dot ")
            .replacingOccurrences(of: "_", with: " underscore ")
            .replacingOccurrences(of: "-", with: " dash ")

        spoken = replacingMatches(
            in: spoken,
            pattern: #"([a-z0-9])([A-Z])"#
        ) { match, source in
            let lhs = source.substring(with: match.range(at: 1))
            let rhs = source.substring(with: match.range(at: 2))
            return "\(lhs) \(rhs)"
        }

        return collapseWhitespace(spoken)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let collapsedSpaces = text.replacingOccurrences(
            of: #"[ ]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        let collapsedLines = collapsedSpaces.replacingOccurrences(
            of: #"\n{2,}"#,
            with: ". ",
            options: .regularExpression
        )
        return collapsedLines
            .replacingOccurrences(
                of: #"\s+([,.;:?!])"#,
                with: "$1",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: (_ match: NSTextCheckingResult, _ source: NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastLocation = 0

        for match in matches {
            let matchRange = match.range
            let prefixRange = NSRange(location: lastLocation, length: matchRange.location - lastLocation)
            result += source.substring(with: prefixRange)
            result += transform(match, source)
            lastLocation = matchRange.location + matchRange.length
        }

        let suffixRange = NSRange(location: lastLocation, length: source.length - lastLocation)
        result += source.substring(with: suffixRange)
        return result
    }

    private struct ForensicSectionCandidate {
        let title: String
        let kind: SpeechTextForensicSectionKind
        let text: String
    }

    private static func splitForensicSections(in text: String) -> [ForensicSectionCandidate] {
        let headerSections = splitMarkdownHeaderSections(in: text)
        if !headerSections.isEmpty {
            return headerSections
        }

        let paragraphSections = splitParagraphSections(in: text)
        if !paragraphSections.isEmpty {
            return paragraphSections
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [
            ForensicSectionCandidate(
                title: "Full Request",
                kind: .fullRequest,
                text: trimmed
            )
        ]
    }

    private static func splitMarkdownHeaderSections(in text: String) -> [ForensicSectionCandidate] {
        let lines = text.components(separatedBy: .newlines)
        var sections = [ForensicSectionCandidate]()
        var currentTitle: String?
        var currentLines = [String]()

        func flushCurrentSection() {
            guard let currentTitle else { return }
            let sectionText = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sectionText.isEmpty else { return }
            sections.append(
                ForensicSectionCandidate(
                    title: currentTitle,
                    kind: .markdownHeader,
                    text: sectionText
                )
            )
        }

        for line in lines {
            if let headerTitle = markdownHeaderTitle(in: line) {
                flushCurrentSection()
                currentTitle = headerTitle
                currentLines = [line]
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }

        flushCurrentSection()
        return sections
    }

    private static func splitParagraphSections(in text: String) -> [ForensicSectionCandidate] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        return normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, paragraph in
                ForensicSectionCandidate(
                    title: "Paragraph \(index + 1)",
                    kind: .paragraph,
                    text: paragraph
                )
            }
    }

    private static func markdownHeaderTitle(in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s{0,3}#{1,6}\s+(.+?)\s*$"#) else {
            return nil
        }

        let source = line as NSString
        let range = NSRange(location: 0, length: source.length)
        guard let match = regex.firstMatch(in: line, range: range) else {
            return nil
        }

        let title = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
