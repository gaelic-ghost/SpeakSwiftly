import Foundation
import NaturalLanguage

struct LiveSpeechTextChunk: Equatable {
    let index: Int
    let text: String
    let wordCount: Int
}

enum LiveSpeechChunkPlanner {
    enum Strategy: Equatable {
        case sentenceGroups
        case paragraphPairs(maxSentencesPerChunk: Int = 8)
    }

    private static let firstChunkSentenceCount = 3
    private static let laterChunkSentenceCount = 2
    private static let paragraphsPerChunk = 2

    static func chunks(
        for text: String,
        strategy: Strategy = .sentenceGroups,
    ) -> [LiveSpeechTextChunk] {
        let chunkTexts = switch strategy {
            case .sentenceGroups:
                sentenceGroupedChunkTexts(for: text)
            case let .paragraphPairs(maxSentencesPerChunk):
                paragraphPairChunkTexts(for: text, maxSentencesPerChunk: maxSentencesPerChunk)
        }

        return chunkTexts.enumerated().map { index, chunkText in
            LiveSpeechTextChunk(
                index: index + 1,
                text: chunkText,
                wordCount: max(SpeakSwiftly.DeepTrace.words(in: chunkText).count, 1),
            )
        }
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

    private static func paragraphPairChunkTexts(
        for text: String,
        maxSentencesPerChunk: Int,
    ) -> [String] {
        let paragraphs = paragraphUnits(in: text)
        guard !paragraphs.isEmpty else {
            return sentenceGroupedChunkTexts(for: text)
        }

        var chunkTexts = [String]()
        var index = 0

        while index < paragraphs.count {
            let endIndex = min(index + paragraphsPerChunk, paragraphs.count)
            let combinedParagraphs = paragraphs[index..<endIndex].joined(separator: "\n\n")
            let sentenceCount = sentenceUnits(in: combinedParagraphs).count

            if sentenceCount > maxSentencesPerChunk {
                chunkTexts.append(contentsOf: sentenceChunks(from: sentenceUnits(in: combinedParagraphs)))
            } else {
                chunkTexts.append(combinedParagraphs)
            }

            index = endIndex
        }

        return chunkTexts
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
