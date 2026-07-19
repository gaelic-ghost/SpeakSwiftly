@testable import SpeakSwiftlyNormalization
import Testing

// MARK: - Parsing Utilities

@Test func `natural language words returns word tokens without punctuation`() {
    let words = TextNormalizer.naturalLanguageWords(in: "Hello, Gale. Ship v0.18.9!")

    #expect(words.contains("Hello"))
    #expect(words.contains("Gale"))
    #expect(words.contains("Ship"))
    #expect(!words.contains(","))
    #expect(!words.contains("!"))
}
