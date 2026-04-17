import Foundation
import NaturalLanguage

// MARK: - LiveSpeechTextChunk

struct LiveSpeechTextChunk: Equatable, Sendable {
    let index: Int
    let text: String
    let wordCount: Int
}

// MARK: - LiveSpeechChunkPlanner

enum LiveSpeechChunkPlanner {
    private static let firstChunkTargetWords = 16
    private static let laterChunkTargetWords = 28
    private static let minimumChunkWords = 8
    private static let maximumChunkWords = 40
    private static let clauseDelimiters: Set<Character> = [",", ";", ":", "—", "–"]

    static func chunks(for text: String) -> [LiveSpeechTextChunk] {
        let paragraphs = paragraphUnits(in: text)
        guard !paragraphs.isEmpty else { return [] }

        var chunkTexts = [String]()
        chunkTexts.reserveCapacity(paragraphs.count)

        for paragraph in paragraphs {
            appendParagraphChunks(
                for: paragraph,
                into: &chunkTexts,
            )
        }

        if chunkTexts.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            chunkTexts = [trimmed]
        }

        return chunkTexts.enumerated().map { index, chunkText in
            LiveSpeechTextChunk(
                index: index + 1,
                text: chunkText,
                wordCount: max(SpeakSwiftly.DeepTrace.words(in: chunkText).count, 1),
            )
        }
    }

    private static func appendParagraphChunks(
        for paragraph: String,
        into chunks: inout [String],
    ) {
        let spokenUnits = spokenUnits(in: paragraph)
        guard !spokenUnits.isEmpty else {
            chunks.append(paragraph)
            return
        }

        var currentSentences = [String]()
        var currentWordCount = 0

        func flushCurrentChunk() {
            guard !currentSentences.isEmpty else { return }
            chunks.append(currentSentences.joined(separator: " "))
            currentSentences.removeAll(keepingCapacity: true)
            currentWordCount = 0
        }

        for spokenUnit in spokenUnits {
            let spokenUnitWordCount = max(SpeakSwiftly.DeepTrace.words(in: spokenUnit).count, 1)
            let targetWordCount = chunks.isEmpty ? firstChunkTargetWords : laterChunkTargetWords

            if currentSentences.isEmpty {
                currentSentences = [spokenUnit]
                currentWordCount = spokenUnitWordCount
                continue
            }

            let proposedWordCount = currentWordCount + spokenUnitWordCount
            let fitsTarget = proposedWordCount <= targetWordCount
            let needsMinimumSupport = currentWordCount < minimumChunkWords && proposedWordCount <= maximumChunkWords

            if fitsTarget || needsMinimumSupport {
                currentSentences.append(spokenUnit)
                currentWordCount = proposedWordCount
                continue
            }

            flushCurrentChunk()
            currentSentences = [spokenUnit]
            currentWordCount = spokenUnitWordCount
        }

        flushCurrentChunk()
    }

    private static func spokenUnits(in text: String) -> [String] {
        sentenceUnits(in: text).flatMap(subsentenceUnits(in:))
    }

    private static func subsentenceUnits(in sentence: String) -> [String] {
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty else { return [] }

        let sentenceWordCount = SpeakSwiftly.DeepTrace.words(in: trimmedSentence).count
        guard sentenceWordCount > laterChunkTargetWords else { return [trimmedSentence] }

        let clauses = clauseUnits(in: trimmedSentence)
        let candidateUnits = clauses.count > 1 ? clauses : [trimmedSentence]
        return candidateUnits.flatMap(splitOversizedUnit(_:))
    }

    private static func splitOversizedUnit(_ unit: String) -> [String] {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUnit.isEmpty else { return [] }

        let words = SpeakSwiftly.DeepTrace.words(in: trimmedUnit)
        guard words.count > laterChunkTargetWords else { return [trimmedUnit] }

        let tokens = trimmedUnit.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return [trimmedUnit] }

        var chunkedUnits = [String]()
        var currentTokens = [Substring]()

        func flushCurrentTokens() {
            guard !currentTokens.isEmpty else { return }
            chunkedUnits.append(currentTokens.joined(separator: " "))
            currentTokens.removeAll(keepingCapacity: true)
        }

        for token in tokens {
            currentTokens.append(token)
            if currentTokens.count >= laterChunkTargetWords {
                flushCurrentTokens()
            }
        }

        flushCurrentTokens()
        return chunkedUnits
    }

    private static func paragraphUnits(in text: String) -> [String] {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    private static func clauseUnits(in text: String) -> [String] {
        var clauses = [String]()
        var currentClause = ""

        func flushCurrentClause() {
            let trimmedClause = currentClause.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedClause.isEmpty else { return }
            clauses.append(trimmedClause)
            currentClause.removeAll(keepingCapacity: true)
        }

        for character in text {
            currentClause.append(character)
            if clauseDelimiters.contains(character) {
                flushCurrentClause()
            }
        }

        flushCurrentClause()
        return clauses
    }
}
