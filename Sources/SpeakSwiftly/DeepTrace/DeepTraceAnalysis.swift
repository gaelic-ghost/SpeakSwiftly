import Foundation
import NaturalLanguage

// MARK: - Deep Trace Analysis

enum DeepTraceAnalysis {
    struct SectionCandidate {
        let title: String
        let kind: SpeakSwiftly.DeepTrace.SectionKind
        let text: String
    }

    struct MarkdownLinkMatch {
        let fullRange: Range<String.Index>
        let label: String
        let destination: String
    }

    static func features(
        originalText: String,
        normalizedText: String
    ) -> SpeakSwiftly.DeepTrace.Features {
        let tokens = candidateTokens(in: originalText)

        return SpeakSwiftly.DeepTrace.Features(
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

    static func sections(originalText: String) -> [SpeakSwiftly.DeepTrace.Section] {
        let sections = splitSections(in: originalText)
        let weightedCounts = sections.map { max($0.text.count, 1) }
        let totalWeightedCount = max(weightedCounts.reduce(0, +), 1)

        return sections.enumerated().map { index, section in
            SpeakSwiftly.DeepTrace.Section(
                index: index + 1,
                title: section.title,
                kind: section.kind,
                originalCharacterCount: section.text.count,
                normalizedCharacterCount: weightedCounts[index],
                normalizedCharacterShare: Double(weightedCounts[index]) / Double(totalWeightedCount)
            )
        }
    }

    static func sectionWindows(
        originalText: String,
        totalDurationMS: Int,
        totalChunkCount: Int
    ) -> [SpeakSwiftly.DeepTrace.SectionWindow] {
        let sections = sections(originalText: originalText)
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

            let window = SpeakSwiftly.DeepTrace.SectionWindow(
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

    static func words(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
    }

    // MARK: Sections

    static func splitSections(in text: String) -> [SectionCandidate] {
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
            SectionCandidate(
                title: "Full Request",
                kind: .fullRequest,
                text: trimmed
            )
        ]
    }

    static func splitMarkdownHeaderSections(in text: String) -> [SectionCandidate] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [SectionCandidate] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flushCurrentSection() {
            guard let currentTitle else { return }
            let sectionText = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sectionText.isEmpty else { return }
            sections.append(
                SectionCandidate(
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

    static func splitParagraphSections(in text: String) -> [SectionCandidate] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, paragraph in
                SectionCandidate(
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

    // MARK: Parsing

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

    static func markdownLinks(in text: String) -> [MarkdownLinkMatch] {
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
            let startsTildePath = character == "~"
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

    static func paragraphCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        return trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
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

    // MARK: Heuristics

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
              !token.contains("/")
        else {
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
}

private extension Character {
    var isAlphaNumeric: Bool { isLetter || isNumber }
}
