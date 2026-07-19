@testable import SpeakSwiftlyNormalization
import Testing

@Test func `swift markdown detects meaningful markdown structure`() {
    let markdown = """
    # Heading

    Read `sampleRate` and [docs](https://example.com).
    """

    #expect(TextNormalizer.markdownHasStructure(markdown))
    #expect(!TextNormalizer.markdownHasStructure("This is ordinary prose with no markdown structure."))
}

@Test func `swift soup detects meaningful html structure`() {
    #expect(TextNormalizer.htmlHasStructure("<section><p>Hello</p></section>"))
    #expect(!TextNormalizer.htmlHasStructure("This is ordinary prose with <angle words but no closing tag."))
}
