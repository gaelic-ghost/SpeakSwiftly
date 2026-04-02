import Foundation
import Testing
@testable import SpeakSwiftly

struct SpeechTextNormalizerTests {
    @Test func fencedCodeBlocksBecomeSpokenCodeSamples() {
        let text = """
        Before
        ```swift
        let fooBar = thing?.value ?? 24000
        ```
        After
        """

        let normalized = SpeechTextNormalizer.normalizeFencedCodeBlocks(text)

        #expect(normalized.contains("Code sample."))
        #expect(normalized.contains("let foo Bar equals thing optional chaining value nil coalescing 24000"))
        #expect(normalized.contains("End code sample."))
    }

    @Test func inlineCodeSpansBecomeSpeakable() {
        let text = "Read `profile?.sampleRate ?? 24000` once."

        let normalized = SpeechTextNormalizer.normalizeInlineCodeSpans(text)

        #expect(!normalized.contains("`"))
        #expect(normalized.contains("profile optional chaining sample Rate nil coalescing 24000"))
    }

    @Test func markdownLinksPreserveLabelAndDestination() {
        let text = "Open [the docs](https://example.com/docs) now."

        let normalized = SpeechTextNormalizer.normalizeMarkdownLinks(text)

        #expect(normalized.contains("the docs, link https://example.com/docs"))
    }

    @Test func filePathsBecomeSpokenPaths() {
        let text = "Path: /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift."

        let normalized = SpeechTextNormalizer.normalizeFilePaths(text)

        #expect(normalized.contains("Users slash galew slash Workspace slash Speak Swiftly"))
        #expect(normalized.contains("Speech Text Normalizer dot swift"))
    }

    @Test func dottedIdentifiersBecomeSpokenIdentifiers() {
        let text = "Read NSApplication.didFinishLaunchingNotification once."

        let normalized = SpeechTextNormalizer.normalizeDottedIdentifiers(text)

        #expect(normalized.contains("NSApplication dot did Finish Launching Notification"))
    }

    @Test func snakeCaseIdentifiersBecomeSpokenIdentifiers() {
        let text = "Read snake_case_stuff once."

        let normalized = SpeechTextNormalizer.normalizeSnakeCaseIdentifiers(text)

        #expect(normalized.contains("snake underscore case underscore stuff"))
    }

    @Test func camelCaseIdentifiersBecomeSpokenIdentifiers() {
        let text = "Read camelCaseStuff once."

        let normalized = SpeechTextNormalizer.normalizeCamelCaseIdentifiers(text)

        #expect(normalized.contains("camel Case Stuff"))
    }

    @Test func codeHeavyLinesBecomeSpokenCode() {
        let text = #"let fallback = weirdWords.first(where: { $0.hasPrefix("q") }) ?? "nothing""#

        let normalized = SpeechTextNormalizer.normalizeCodeHeavyLines(text)

        #expect(normalized.contains("open brace"))
        #expect(normalized.contains("nil coalescing"))
    }

    @Test func spiralProneWordsAreSpelledOut() {
        let text = "Also say chrommmaticallly and qqqwweerrtyy once."

        let normalized = SpeechTextNormalizer.normalizeSpiralProneWords(text)

        #expect(normalized.contains("c h r o m m m a t i c a l l l y"))
        #expect(normalized.contains("q q q w w e e r r t y y"))
    }

    @Test func normalizeRunsSingleFunctionalPipelineAcrossMixedInput() {
        let original = """
        Please read /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift, NSApplication.didFinishLaunchingNotification, camelCaseStuff, snake_case_stuff, and `profile?.sampleRate ?? 24000`.
        """

        let normalized = SpeechTextNormalizer.normalize(original)

        #expect(normalized.contains("Users slash galew slash Workspace slash Speak Swiftly"))
        #expect(normalized.contains("NSApplication dot did Finish Launching Notification"))
        #expect(normalized.contains("camel Case Stuff"))
        #expect(normalized.contains("snake underscore case underscore stuff"))
        #expect(normalized.contains("profile optional chaining sample Rate nil coalescing 24000"))
    }

    @Test func normalizeHandlesMarkdownLinksCodeBlocksAndSpiralWordsTogether() {
        let original = """
        Read [the docs](https://example.com/docs) first.

        ```swift
        let sourcePath = "/tmp/Thing"
        ```

        Also say chrommmaticallly once.
        """

        let normalized = SpeechTextNormalizer.normalize(original)

        #expect(normalized.contains("the docs, link https://example.com/docs"))
        #expect(normalized.contains("Code sample."))
        #expect(normalized.contains("slash tmp slash Thing"))
        #expect(normalized.contains("c h r o m m m a t i c a l l l y"))
    }
}
