import Foundation
import NaturalLanguage

extension TextNormalizer {
    // MARK: Natural Language Tokens

    static func naturalLanguageWords(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
    }
}
