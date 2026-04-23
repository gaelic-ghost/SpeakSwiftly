import Foundation
import NaturalLanguage

struct LiveSpeechTextChunk: Equatable {
    enum Segmentation: String, Equatable {
        case sentenceGroup = "sentence_group"
        case paragraphGroup = "paragraph_group"
        case lineBreak = "line_break"
        case punctuationBoundary = "punctuation_boundary"
        case forcedBreak = "forced_break"
    }

    let index: Int
    let text: String
    let wordCount: Int
    let segmentation: Segmentation
}

enum LiveSpeechChunkPlanner {
    enum Strategy: Equatable {
        case sentenceGroups
        case smartParagraphGroups(targetParagraphCount: Int = 3, softCharacterLimit: Int = 1400)
    }

    private static let firstChunkSentenceCount = 3
    private static let laterChunkSentenceCount = 2
    private static let minimumSmartBoundaryCharacterCount = 120

    static func chunks(
        for text: String,
        strategy: Strategy = .sentenceGroups,
    ) -> [LiveSpeechTextChunk] {
        let chunkTexts = switch strategy {
            case .sentenceGroups:
                sentenceGroupedChunkTexts(for: text)
            case let .smartParagraphGroups(targetParagraphCount, softCharacterLimit):
                smartParagraphChunkTexts(
                    for: text,
                    targetParagraphCount: targetParagraphCount,
                    softCharacterLimit: softCharacterLimit,
                )
        }

        return chunkTexts.enumerated().map { index, chunkText in
            LiveSpeechTextChunk(
                index: index + 1,
                text: chunkText,
                wordCount: max(SpeakSwiftly.DeepTrace.words(in: chunkText).count, 1),
                segmentation: segmentation(for: chunkText, strategy: strategy),
            )
        }
    }

    static func paragraphCount(in text: String) -> Int {
        paragraphUnits(in: text).count
    }

    static func sentenceCount(in text: String) -> Int {
        sentenceUnits(in: text).count
    }

    private static func sentenceGroupedChunkTexts(for text: String) -> [String] {
        let sentences = sentenceUnits(in: text)
        let chunkTexts: [String]

        if sentences.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }

            chunkTexts = [trimmed]
        } else {
            chunkTexts = sentenceChunks(from: sentences)
        }

        return chunkTexts
    }

    private static func smartParagraphChunkTexts(
        for text: String,
        targetParagraphCount: Int,
        softCharacterLimit: Int,
    ) -> [String] {
        let paragraphs = paragraphUnits(in: text)
        guard !paragraphs.isEmpty else {
            return smartBoundaryChunkTexts(for: text, softCharacterLimit: softCharacterLimit)
        }

        var chunkTexts = [String]()
        var index = 0

        while index < paragraphs.count {
            let preferredEndIndex = min(index + targetParagraphCount, paragraphs.count)
            let preferredChunk = paragraphs[index..<preferredEndIndex].joined(separator: "\n\n")

            if preferredChunk.count <= softCharacterLimit {
                chunkTexts.append(preferredChunk)
                index = preferredEndIndex
                continue
            }

            var acceptedEndIndex: Int?
            var candidateEndIndex = preferredEndIndex
            while candidateEndIndex > index + 1 {
                let candidate = paragraphs[index..<candidateEndIndex].joined(separator: "\n\n")
                if candidate.count <= softCharacterLimit {
                    acceptedEndIndex = candidateEndIndex
                    break
                }
                candidateEndIndex -= 1
            }

            if let acceptedEndIndex {
                chunkTexts.append(paragraphs[index..<acceptedEndIndex].joined(separator: "\n\n"))
                index = acceptedEndIndex
            } else {
                chunkTexts.append(contentsOf: smartBoundaryChunkTexts(for: paragraphs[index], softCharacterLimit: softCharacterLimit))
                index += 1
            }
        }

        return chunkTexts
    }

    private static func segmentation(
        for chunkText: String,
        strategy: Strategy,
    ) -> LiveSpeechTextChunk.Segmentation {
        switch strategy {
            case .sentenceGroups:
                .sentenceGroup
            case .smartParagraphGroups:
                if chunkText.contains("\n\n") {
                    .paragraphGroup
                } else if chunkText.contains("\n") {
                    .lineBreak
                } else if endsAtClosingPunctuation(chunkText) {
                    .punctuationBoundary
                } else {
                    .forcedBreak
                }
        }
    }

    private static func smartBoundaryChunkTexts(
        for text: String,
        softCharacterLimit: Int,
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > softCharacterLimit else { return [trimmed] }
        guard let boundaryIndex = bestBoundaryIndex(in: trimmed, softCharacterLimit: softCharacterLimit) else {
            let forcedIndex = trimmed.index(trimmed.startIndex, offsetBy: softCharacterLimit)
            let left = trimmed[..<forcedIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = trimmed[forcedIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            return [left, right].filter { !$0.isEmpty }
        }

        let left = trimmed[..<boundaryIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let right = trimmed[boundaryIndex...].trimmingCharacters(in: .whitespacesAndNewlines)

        return smartBoundaryChunkTexts(for: String(left), softCharacterLimit: softCharacterLimit)
            + smartBoundaryChunkTexts(for: String(right), softCharacterLimit: softCharacterLimit)
    }

    private static func bestBoundaryIndex(
        in text: String,
        softCharacterLimit: Int,
    ) -> String.Index? {
        let safeLimit = min(softCharacterLimit, text.count)
        guard safeLimit < text.count else { return nil }

        let minimumOffset = min(max(softCharacterLimit / 3, minimumSmartBoundaryCharacterCount), safeLimit)
        let minimumIndex = text.index(text.startIndex, offsetBy: minimumOffset)
        let searchLimit = text.index(text.startIndex, offsetBy: safeLimit)

        if let boundaryIndex = lastDelimiterBoundary(
            delimiter: "\n\n",
            in: text,
            minimumIndex: minimumIndex,
            searchLimit: searchLimit,
        ) {
            return boundaryIndex
        }

        if let boundaryIndex = lastDelimiterBoundary(
            delimiter: "\n",
            in: text,
            minimumIndex: minimumIndex,
            searchLimit: searchLimit,
        ) {
            return boundaryIndex
        }

        if let boundaryIndex = lastSentenceBoundary(
            in: text,
            minimumIndex: minimumIndex,
            searchLimit: searchLimit,
        ) {
            return boundaryIndex
        }

        if let boundaryIndex = lastClosingPunctuationBoundary(
            in: text,
            minimumIndex: minimumIndex,
            searchLimit: searchLimit,
        ) {
            return boundaryIndex
        }

        return lastWhitespaceBoundary(
            in: text,
            minimumIndex: minimumIndex,
            searchLimit: searchLimit,
        )
    }

    private static func lastDelimiterBoundary(
        delimiter: String,
        in text: String,
        minimumIndex: String.Index,
        searchLimit: String.Index,
    ) -> String.Index? {
        guard let range = text[minimumIndex..<searchLimit].range(of: delimiter, options: .backwards) else {
            return nil
        }

        return range.upperBound
    }

    private static func lastSentenceBoundary(
        in text: String,
        minimumIndex: String.Index,
        searchLimit: String.Index,
    ) -> String.Index? {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        let ranges = tokenizer.tokens(for: text.startIndex..<searchLimit)
        return ranges.last(where: { $0.upperBound > minimumIndex && $0.upperBound < text.endIndex })?.upperBound
    }

    private static func lastClosingPunctuationBoundary(
        in text: String,
        minimumIndex: String.Index,
        searchLimit: String.Index,
    ) -> String.Index? {
        let candidates = ".!?;:"
        var index = searchLimit

        while index > minimumIndex {
            let previousIndex = text.index(before: index)
            if candidates.contains(text[previousIndex]) {
                return index
            }
            index = previousIndex
        }

        return nil
    }

    private static func lastWhitespaceBoundary(
        in text: String,
        minimumIndex: String.Index,
        searchLimit: String.Index,
    ) -> String.Index? {
        var index = searchLimit

        while index > minimumIndex {
            let previousIndex = text.index(before: index)
            if text[previousIndex].isWhitespace {
                return index
            }
            index = previousIndex
        }

        return nil
    }

    private static func endsAtClosingPunctuation(_ text: String) -> Bool {
        guard let lastNonWhitespace = text.last(where: { !$0.isWhitespace }) else { return false }

        return ".!?;:)]}\"'".contains(lastNonWhitespace)
    }

    private static func sentenceChunks(from sentences: [String]) -> [String] {
        var chunks = [String]()
        var index = 0

        while index < sentences.count {
            let chunkSentenceCount = chunks.isEmpty ? firstChunkSentenceCount : laterChunkSentenceCount
            let endIndex = min(index + chunkSentenceCount, sentences.count)
            chunks.append(sentences[index..<endIndex].joined(separator: " "))
            index = endIndex
        }

        return chunks
    }

    private static func paragraphUnits(in text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var paragraphs = [String]()
        var currentParagraphLines = [String]()

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !currentParagraphLines.isEmpty {
                    paragraphs.append(currentParagraphLines.joined(separator: "\n"))
                    currentParagraphLines.removeAll(keepingCapacity: true)
                }
            } else {
                currentParagraphLines.append(line)
            }
        }

        if !currentParagraphLines.isEmpty {
            paragraphs.append(currentParagraphLines.joined(separator: "\n"))
        }

        if paragraphs.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        return paragraphs
    }

    private static func sentenceUnits(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        return sentences
    }
}
