import Foundation
import NaturalLanguage
import RegexBuilder

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
    let urlCount: Int
    let filePathCount: Int
    let dottedIdentifierCount: Int
    let camelCaseTokenCount: Int
    let snakeCaseTokenCount: Int
    let objcSymbolCount: Int
    let repeatedLetterRunCount: Int
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
    typealias NormalizationPass = (String) -> String

    private static var codeMarkerRegex: Regex<Substring> {
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

    private static var normalizationPasses: [NormalizationPass] {
        [
            normalizeFencedCodeBlocks,
            normalizeInlineCodeSpans,
            normalizeMarkdownLinks,
            normalizeURLs,
            normalizeFilePaths,
            normalizeDottedIdentifiers,
            normalizeSnakeCaseIdentifiers,
            normalizeCamelCaseIdentifiers,
            normalizeCodeHeavyLines,
            normalizeSpiralProneWords,
            collapseWhitespace,
        ]
    }

    // MARK: Public API

    static func normalize(_ text: String) -> String {
        let normalized = normalizationPasses.reduce(canonicalize(text)) { partial, pass in
            pass(partial)
        }
        let finalized = collapseWhitespace(normalized)
        return finalized.isEmpty ? text : finalized
    }

    static func forensicFeatures(originalText: String, normalizedText: String) -> SpeechTextForensicFeatures {
        let tokens = candidateTokens(in: originalText)

        return SpeechTextForensicFeatures(
            originalCharacterCount: originalText.count,
            normalizedCharacterCount: normalizedText.count,
            normalizedCharacterDelta: normalizedText.count - originalText.count,
            originalParagraphCount: paragraphCount(in: originalText),
            normalizedParagraphCount: paragraphCount(in: normalizedText),
            markdownHeaderCount: originalText.split(separator: "\n", omittingEmptySubsequences: false)
                .count(where: { markdownHeaderTitle(in: String($0)) != nil }),
            fencedCodeBlockCount: fencedCodeBlockBodies(in: originalText).count,
            inlineCodeSpanCount: inlineCodeBodies(in: originalText).count,
            markdownLinkCount: markdownLinks(in: originalText).count,
            urlCount: tokens.count(where: isLikelyURL),
            filePathCount: filePathFragments(in: originalText).count,
            dottedIdentifierCount: tokens.count(where: isLikelyDottedIdentifier),
            camelCaseTokenCount: tokens.count(where: isLikelyCamelCaseIdentifier),
            snakeCaseTokenCount: tokens.count(where: isLikelySnakeCaseIdentifier),
            objcSymbolCount: tokens.count(where: isLikelyObjectiveCSymbol),
            repeatedLetterRunCount: tokens.count(where: containsRepeatedLetterRun)
        )
    }

    static func forensicSections(originalText: String) -> [SpeechTextForensicSection] {
        let sections = splitForensicSections(in: originalText)
        let weightedCounts = sections.map { max(normalize($0.text).count, 1) }
        let totalWeightedCount = max(weightedCounts.reduce(0, +), 1)

        return sections.enumerated().map { index, section in
            SpeechTextForensicSection(
                index: index + 1,
                title: section.title,
                kind: section.kind,
                originalCharacterCount: section.text.count,
                normalizedCharacterCount: weightedCounts[index],
                normalizedCharacterShare: Double(weightedCounts[index]) / Double(totalWeightedCount)
            )
        }
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

        return sections.enumerated().map { index, section in
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
    }
}

// MARK: - Normalization Passes

extension SpeechTextNormalizer {
    static func normalizeFencedCodeBlocks(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return text }

        var output: [String] = []
        var bufferedCode: [String] = []
        var insideFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if insideFence {
                    output.append(spokenCodeBlock(bufferedCode.joined(separator: "\n")))
                    bufferedCode.removeAll(keepingCapacity: true)
                }
                insideFence.toggle()
                continue
            }

            if insideFence {
                bufferedCode.append(line)
            } else {
                output.append(line)
            }
        }

        if insideFence, !bufferedCode.isEmpty {
            output.append(spokenCodeBlock(bufferedCode.joined(separator: "\n")))
        }

        return output.joined(separator: "\n")
    }

    static func normalizeInlineCodeSpans(_ text: String) -> String {
        let bodies = inlineCodeBodies(in: text)
        guard !bodies.isEmpty else { return text }

        var result = ""
        var index = text.startIndex
        var bodyIterator = bodies.makeIterator()
        var nextBody = bodyIterator.next()

        while index < text.endIndex {
            guard text[index] == "`", let expectedBody = nextBody else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let contentStart = text.index(after: index)
            guard let closing = text[contentStart...].firstIndex(of: "`") else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let body = String(text[contentStart..<closing])
            if body == expectedBody {
                result += spokenInlineCode(body)
                index = text.index(after: closing)
                nextBody = bodyIterator.next()
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }

        return result
    }

    static func normalizeMarkdownLinks(_ text: String) -> String {
        let links = markdownLinks(in: text)
        guard !links.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex

        for link in links {
            result += text[cursor..<link.fullRange.lowerBound]
            let label = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = link.destination.trimmingCharacters(in: .whitespacesAndNewlines)

            if label.isEmpty {
                result += " \(destination) "
            } else {
                result += " \(label), link \(destination) "
            }

            cursor = link.fullRange.upperBound
        }

        result += text[cursor...]
        return result
    }

    static func normalizeURLs(_ text: String) -> String {
        transformTokens(in: text) { token in
            guard isLikelyURL(token) else { return nil }
            return spokenURL(token)
        }
    }

    static func normalizeFilePaths(_ text: String) -> String {
        transformTokens(in: text) { token in
            guard isLikelyFilePath(token) else { return nil }
            return spokenPath(token)
        }
    }

    static func normalizeDottedIdentifiers(_ text: String) -> String {
        transformTokens(in: text) { token in
            guard isLikelyDottedIdentifier(token) else { return nil }
            return spokenIdentifier(token)
        }
    }

    static func normalizeSnakeCaseIdentifiers(_ text: String) -> String {
        transformTokens(in: text) { token in
            guard isLikelySnakeCaseIdentifier(token) else { return nil }
            return spokenIdentifier(token)
        }
    }

    static func normalizeCamelCaseIdentifiers(_ text: String) -> String {
        transformTokens(in: text) { token in
            guard isLikelyCamelCaseIdentifier(token) else { return nil }
            return spokenIdentifier(token)
        }
    }

    static func normalizeCodeHeavyLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { line in
            isLikelyCodeLine(line) ? spokenCode(line) : line
        }.joined(separator: "\n")
    }

    static func normalizeSpiralProneWords(_ text: String) -> String {
        let tokens = naturalLanguageTokenRanges(in: text)
        guard !tokens.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex

        for range in tokens {
            result += text[cursor..<range.lowerBound]
            let token = String(text[range])
            result += containsRepeatedLetterRun(token) ? spelledOut(token) : token
            cursor = range.upperBound
        }

        result += text[cursor...]
        return result
    }
}

// MARK: - Speech Conversion

extension SpeechTextNormalizer {
    static func spokenCode(_ text: String) -> String {
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

        let spoken = replacements.reduce(text) { partial, replacement in
            partial.replacingOccurrences(of: replacement.0, with: replacement.1)
        }

        return collapseWhitespace(insertWordBreaks(in: spoken))
    }

    static func spokenPath(_ text: String) -> String {
        var segments: [String] = []
        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            segments.append(spokenSegment(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            switch character {
            case "~":
                flushBuffer()
                segments.append("home")
            case "/":
                flushBuffer()
                if !segments.isEmpty {
                    segments.append("slash")
                }
            case "\\":
                flushBuffer()
                segments.append("backslash")
            case ".":
                flushBuffer()
                segments.append("dot")
            case "_":
                flushBuffer()
                segments.append("underscore")
            case "-":
                flushBuffer()
                segments.append("dash")
            default:
                buffer.append(character)
            }
        }

        flushBuffer()
        return collapseWhitespace(segments.joined(separator: " "))
    }

    static func spokenURL(_ text: String) -> String {
        guard let schemeSeparator = text.range(of: "://") else {
            return spokenPath(text)
        }

        let scheme = text[..<schemeSeparator.lowerBound].lowercased()
        var remainder = String(text[schemeSeparator.upperBound...])

        if ["http", "https"].contains(scheme) {
            if remainder.hasPrefix("www.") {
                remainder.removeFirst(4)
            }

            return spokenPath(remainder)
        }

        return collapseWhitespace("\(spokenSegment(String(scheme))) colon slash slash \(spokenPath(remainder))")
    }

    static func spokenIdentifier(_ text: String) -> String {
        var parts: [String] = []
        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            parts.append(spokenSegment(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            switch character {
            case ".":
                flushBuffer()
                parts.append("dot")
            case "_":
                flushBuffer()
                parts.append("underscore")
            case "-":
                flushBuffer()
                parts.append("dash")
            default:
                buffer.append(character)
            }
        }

        flushBuffer()
        return collapseWhitespace(parts.joined(separator: " "))
    }
}

// MARK: - Formatting

extension SpeechTextNormalizer {
    static func canonicalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
    }

    static func collapseWhitespace(_ text: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }

        var rebuilt = ""
        var blankLineCount = 0

        for line in lines {
            if line.isEmpty {
                blankLineCount += 1
                continue
            }

            if blankLineCount > 0, !rebuilt.isEmpty {
                rebuilt += ". "
            } else if !rebuilt.isEmpty, !rebuilt.hasSuffix(" ") {
                rebuilt += " "
            }

            rebuilt += line
            blankLineCount = 0
        }

        return rebuilt
            .replacingOccurrences(
                of: #"\s+([,.;:?!])"#,
                with: "$1",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Section Splitting

extension SpeechTextNormalizer {
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
        var sections: [ForensicSectionCandidate] = []
        var currentTitle: String?
        var currentLines: [String] = []

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
            if let title = markdownHeaderTitle(in: line) {
                flushCurrentSection()
                currentTitle = title
                currentLines = [line]
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }

        flushCurrentSection()
        return sections
    }

    private static func splitParagraphSections(in text: String) -> [ForensicSectionCandidate] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return trimmed
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

    static func markdownHeaderTitle(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "#" else { return nil }

        let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}

// MARK: - Parsing Utilities

extension SpeechTextNormalizer {
    private struct MarkdownLinkMatch {
        let fullRange: Range<String.Index>
        let label: String
        let destination: String
    }

    static func fencedCodeBlockBodies(in text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var bodies: [String] = []
        var buffer: [String] = []
        var insideFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if insideFence {
                    bodies.append(buffer.joined(separator: "\n"))
                    buffer.removeAll(keepingCapacity: true)
                }
                insideFence.toggle()
                continue
            }

            if insideFence {
                buffer.append(line)
            }
        }

        if insideFence, !buffer.isEmpty {
            bodies.append(buffer.joined(separator: "\n"))
        }

        return bodies
    }

    static func inlineCodeBodies(in text: String) -> [String] {
        var bodies: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "`" else {
                index = text.index(after: index)
                continue
            }

            let contentStart = text.index(after: index)
            guard let closing = text[contentStart...].firstIndex(of: "`") else {
                break
            }

            bodies.append(String(text[contentStart..<closing]))
            index = text.index(after: closing)
        }

        return bodies
    }

    private static func markdownLinks(in text: String) -> [MarkdownLinkMatch] {
        var matches: [MarkdownLinkMatch] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let labelStart = text[cursor...].firstIndex(of: "[") else { break }
            guard let labelEnd = text[labelStart...].firstRange(of: "](")?.lowerBound else {
                cursor = text.index(after: labelStart)
                continue
            }

            let destinationStart = text.index(labelEnd, offsetBy: 2)
            guard let destinationEnd = text[destinationStart...].firstIndex(of: ")") else {
                cursor = text.index(after: labelStart)
                continue
            }

            let fullRange = labelStart..<text.index(after: destinationEnd)
            matches.append(
                MarkdownLinkMatch(
                    fullRange: fullRange,
                    label: String(text[text.index(after: labelStart)..<labelEnd]),
                    destination: String(text[destinationStart..<destinationEnd])
                )
            )
            cursor = fullRange.upperBound
        }

        return matches
    }

    static func candidateTokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(trimmedCandidateToken)
            .filter { !$0.isEmpty }
    }

    static func filePathFragments(in text: String) -> [String] {
        var fragments: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let startsTildePath =
                character == "~"
                && text.index(after: index) < text.endIndex
                && text[text.index(after: index)] == "/"

            guard character == "/" || startsTildePath else {
                index = text.index(after: index)
                continue
            }

            let start = index
            var end = index

            while end < text.endIndex {
                let current = text[end]
                if current.isWhitespace || "`),;\"[]{}".contains(current) {
                    break
                }
                end = text.index(after: end)
            }

            let fragment = String(text[start..<end])
            if isLikelyFilePath(fragment) {
                fragments.append(fragment)
            }

            index = end
        }

        return fragments
    }

    static func naturalLanguageTokenRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
    }

    static func naturalLanguageWords(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer
            .tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]) }
    }
}

// MARK: - Small Helpers

extension SpeechTextNormalizer {
    static func paragraphCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        return trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

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

    static func transformedToken(_ rawToken: String, transform: (String) -> String?) -> String {
        let punctuation = CharacterSet(charactersIn: "\"'()[]{}<>.,;:!?")
        var start = rawToken.startIndex
        var end = rawToken.endIndex

        while start < end,
              rawToken[start].unicodeScalars.allSatisfy({ punctuation.contains($0) })
        {
            start = rawToken.index(after: start)
        }

        while end > start {
            let beforeEnd = rawToken.index(before: end)
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
              token[start].unicodeScalars.allSatisfy({ punctuation.contains($0) })
        {
            start = token.index(after: start)
        }

        while end > start {
            let beforeEnd = token.index(before: end)
            guard token[beforeEnd].unicodeScalars.allSatisfy({ punctuation.contains($0) }) else {
                break
            }
            end = beforeEnd
        }

        return String(token[start..<end])
    }

    static func isLikelyFilePath(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        guard !token.contains("://") else { return false }
        guard !token.contains("@") else { return false }

        return token.hasPrefix("/")
            || token.hasPrefix("~/")
            || (token.contains("/") && !token.contains(" "))
    }

    static func isLikelyURL(_ token: String) -> Bool {
        guard let schemeSeparator = token.range(of: "://") else { return false }
        let scheme = token[..<schemeSeparator.lowerBound]
        guard !scheme.isEmpty else { return false }
        return scheme.allSatisfy { $0.isLetter }
    }

    static func isLikelyDottedIdentifier(_ token: String) -> Bool {
        guard token.contains(".") else { return false }
        guard !isLikelyFilePath(token) else { return false }
        guard !token.contains("://") else { return false }

        let parts = token.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy(isIdentifierLike)
    }

    static func isLikelySnakeCaseIdentifier(_ token: String) -> Bool {
        guard token.contains("_") else { return false }
        let parts = token.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isAlphaNumeric) }
    }

    static func isLikelyCamelCaseIdentifier(_ token: String) -> Bool {
        guard !token.contains("."),
              !token.contains("_"),
              !token.contains("-"),
              !token.contains("/") else {
            return false
        }

        return hasLowerToUpperTransition(token)
    }

    static func isLikelyObjectiveCSymbol(_ token: String) -> Bool {
        if token.hasPrefix("NS"), token.dropFirst(2).first?.isUppercase == true {
            return true
        }

        guard token.contains(":") else { return false }
        return token.split(separator: ":").allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isAlphaNumeric)
        }
    }

    static func isIdentifierLike(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isAlphaNumeric || $0 == "_" }
    }

    static func hasLowerToUpperTransition(_ text: String) -> Bool {
        var previous: Character?

        for character in text {
            defer { previous = character }
            guard let previous else { continue }
            if previous.isLowercase, character.isUppercase {
                return true
            }
        }

        return false
    }

    static func containsRepeatedLetterRun(_ text: String) -> Bool {
        var previous: Character?
        var runLength = 1

        for character in text.lowercased() {
            guard character.isLetter else {
                previous = nil
                runLength = 1
                continue
            }

            if previous == character {
                runLength += 1
                if runLength >= 3 {
                    return true
                }
            } else {
                previous = character
                runLength = 1
            }
        }

        return false
    }

    static func spelledOut(_ text: String) -> String {
        text.map { String($0) }.joined(separator: " ")
    }

    static func spokenCodeBlock(_ body: String) -> String {
        let spoken = spokenCode(body)
        return spoken.isEmpty ? "Code sample." : "Code sample. \(spoken). End code sample."
    }

    static func spokenInlineCode(_ body: String) -> String {
        let spoken = spokenCode(body)
        return spoken.isEmpty ? " code " : " \(spoken) "
    }

    static func spokenSegment(_ text: String) -> String {
        let broken = insertWordBreaks(in: text)
        let words = naturalLanguageWords(in: broken)
        if words.isEmpty {
            return broken
        }
        return words.joined(separator: " ")
    }

    static func insertWordBreaks(in text: String) -> String {
        guard !text.isEmpty else { return text }

        var output = ""
        var previous: Character?

        for character in text {
            defer { previous = character }

            guard let previous else {
                output.append(character)
                continue
            }

            let needsBreak =
                (previous.isLowercase && character.isUppercase)
                || (previous.isLetter && character.isNumber)
                || (previous.isNumber && character.isLetter)

            if needsBreak, output.last != " " {
                output.append(" ")
            }

            output.append(character)
        }

        return output
    }

    static func isLikelyCodeLine(_ line: String) -> Bool {
        let punctuation = line.filter { "{}[]()<>/\\=_*#|~:;.`-".contains($0) }.count
        let letters = line.filter(\.isLetter).count
        let hasStructuredMarker =
            line.firstMatch(of: codeMarkerRegex) != nil
            || line.contains("[")
            || line.contains("]")
            || line.contains("@property")

        return punctuation >= 6 && (punctuation * 2 >= max(letters, 4) || hasStructuredMarker)
    }
}

private extension Character {
    var isAlphaNumeric: Bool { isLetter || isNumber }
}
