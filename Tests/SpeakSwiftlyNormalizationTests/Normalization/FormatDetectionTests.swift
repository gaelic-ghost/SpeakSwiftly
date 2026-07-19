@testable import SpeakSwiftlyNormalization
import Testing

// MARK: - Format Detection

@Test func `detect text format keeps prose with source language words plain`() {
    let prose = """
    We should let the import settle before we use the new name. The struct of the notes matters less than the user-facing sentence.
    """

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: prose) == .plain)
}

@Test func `detect text format does not treat incomplete tags as html`() {
    let prose = "The rendered output starts with <section class=\"hero\"> but the sample is only describing the opening tag."

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: prose) == .plain)
}

@Test func `detect text format requires more than one markdown list item`() {
    let prose = "- one note in prose should not become a list by itself"

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: prose) == .plain)
}

@Test func `detect text format ignores unmatched markdown punctuation`() {
    let prose = "This mentions [docs] and `code without forming real markdown."

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: prose) == .plain)
}

@Test func `detect text format distinguishes block quote prose from angle prompt commands`() {
    let quote = "> This quoted sentence should stay ordinary prose."
    let command = "> swift test"

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: quote) == .plain)
    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: command) == .cli)
}

@Test func `detect text format avoids log detection for lowercase prose severity words`() {
    let prose = "The release notes mention error handling, warn readers about migration, and info panels in docs."

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: prose) == .plain)
}
