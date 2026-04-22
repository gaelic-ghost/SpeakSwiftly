import Foundation
import NaturalLanguage

struct LiveSpeechTextChunk: Equatable {
    let index: Int
    let text: String
    let wordCount: Int
}

enum LiveSpeechChunkPlanner {
    private static let firstChunkSentenceCount = 3
    private static let laterChunkSentenceCount = 2

    static func chunks(for text: String) -> [LiveSpeechTextChunk] {
        let sentences = sentenceUnits(in: text)
        let chunkTexts: [String]

        if sentences.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }

            chunkTexts = [trimmed]
        } else {
            chunkTexts = sentenceChunks(from: sentences)
        }

        return chunkTexts.enumerated().map { index, chunkText in
            LiveSpeechTextChunk(
                index: index + 1,
                text: chunkText,
                wordCount: max(SpeakSwiftly.DeepTrace.words(in: chunkText).count, 1),
            )
        }
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
