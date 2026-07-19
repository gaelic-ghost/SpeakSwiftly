@testable import SpeakSwiftlyNormalization
import Testing

// MARK: - End-to-End Normalization

private func occurrenceCount(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

@Test func `normalize preserves mixed input behavior`() async throws {
    let original = """
    Please read /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift, NSApplication.didFinishLaunchingNotification, camelCaseStuff, snake_case_stuff, f32, cosF32, and `profile?.sampleRate ?? 24000`.
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("gale wumbo Workspace Speak Swiftly"))
    #expect(normalized.contains("NSApplication dot did Finish Launching Notification"))
    #expect(normalized.contains("camel Case Stuff"))
    #expect(normalized.contains("snake case stuff"))
    #expect(normalized.contains("float thirty two"))
    #expect(normalized.contains("cosine float thirty two"))
    #expect(normalized.contains("profile optional chaining sample Rate nil coalescing 24000"))
}

@Test func `normalize adds request context preface before text output`() async throws {
    let original = "Read /tmp/Thing.swift and `profile?.sampleRate ?? 24000`."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            source: "codex",
            topic: "normalization",
            attributes: ["surface": "tests"],
        ),
    )

    #expect(normalized.hasPrefix("From codex, normalization.\n\n"))
    #expect(normalized.contains("tmp Thing dot swift"))
    #expect(normalized.contains("profile optional chaining sample Rate nil coalescing 24000"))
}

@Test func `normalize skips request context preface for path only context`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read /Users/galew/Workspace/SpeakSwiftlyNormalization/Sources/App.swift.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftlyNormalization",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftlyNormalization",
        ),
    )

    #expect(!normalized.hasPrefix("From "))
    #expect(normalized.contains("current directory Sources App dot swift"))
}

@Test func `normalize can preface topic only request context`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Build finished.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(reqPurpose: .speech, topic: "release"),
    )

    #expect(normalized.hasPrefix("About release.\n\n"))
    #expect(normalized.contains("Build finished."))
}

@Test func `normalize omits request context preface for audio file purpose by default`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Build finished.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .audioFile,
            source: "codex",
            topic: "retained-audio-file",
        ),
    )

    #expect(!normalized.hasPrefix("From "))
    #expect(!normalized.hasPrefix("About "))
    #expect(normalized == "Build finished.")
}

@Test func `normalize request preface policy can override purpose defaults`() async throws {
    let always = try await SpeakSwiftlyNormalization.Normalize.text(
        "Build finished.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .audioFile,
            source: "codex",
            topic: "forced",
            prefacePolicy: .always,
        ),
    )
    let never = try await SpeakSwiftlyNormalization.Normalize.text(
        "Build finished.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            source: "codex",
            topic: "muted",
            prefacePolicy: .never,
        ),
    )

    #expect(always.hasPrefix("From codex, forced.\n\n"))
    #expect(never == "Build finished.")
}

@Test func `normalize text can exercise summary path with test provider`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read https://example.com and stderr.",
        customProfile: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement("stderr", with: "standard error", id: "stderr-rule"),
            ],
        ),
        summarizationProvider: .test,
        summarize: true,
    )

    #expect(normalized.contains("example dot com"))
    #expect(normalized.contains("standard error"))
}

@Test func `normalize source can exercise summary path with test provider`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(
        "let sampleRate = 48_000",
        as: .swift,
        customProfile: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement("sampleRate", with: "sample rate override", id: "sample-rate-rule"),
            ],
        ),
        summarizationProvider: .test,
        summarize: true,
    )

    #expect(normalized.contains("sample rate override"))
    #expect(normalized.contains("48 000"))
}

@Test func `normalize source speaks detected links before source token rules`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(
        #"let docsURL = "https://example.com/docs""#,
        as: .swift,
    )

    #expect(normalized.contains("example dot com slash docs"))
    #expect(!normalized.contains("https"))
}

@Test func `normalize preserves markdown links code blocks and spiral words`() async throws {
    let original = """
    Read [the docs](https://example.com/docs) first.

    ```swift
    let sourcePath = "/tmp/Thing"
    ```

    Also say chrommmaticallly once.
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("the docs, link example dot com slash docs"))
    #expect(normalized.contains("Code sample."))
    #expect(normalized.contains("slash tmp slash Thing"))
    #expect(normalized.contains("c h r o m m m a t i c a l l l y"))
}

@Test func `normalize handles standalone urls before path passes`() async throws {
    let original = "Open https://example.com/docs/path_now before /tmp/Thing."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("example dot com slash docs slash path now"))
    #expect(normalized.contains("tmp Thing"))
}

@Test func `repeated underscores collapse to speech safe spacing`() async throws {
    let original = "Read snake___case and /tmp/path___now once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("snake case"))
    #expect(normalized.contains("tmp path now"))
    #expect(!normalized.contains("underscore"))
    #expect(!normalized.contains("___"))
}

@Test func `repeated dashes collapse to speech safe spacing`() async throws {
    let original = "Read kebab---case and /tmp/path---now once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("kebab case"))
    #expect(normalized.contains("tmp path now"))
    #expect(!normalized.contains("dash"))
    #expect(!normalized.contains("---"))
}

@Test func `normalize uses context aware file path shortening`() async throws {
    let original = "Please read /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftly",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
        ),
    )

    #expect(normalized.contains("current directory Sources Speak Swiftly"))
    #expect(!normalized.contains("gale wumbo slash Workspace slash Speak Swiftly"))
}

@Test func `normalize compacts repeated paths in the same directory`() async throws {
    let original = """
    Compare /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift and /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift.
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftly",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
        ),
    )

    let sharedPrefix = "current directory Sources Speak Swiftly"
    #expect(occurrenceCount(of: sharedPrefix, in: normalized) == 1)
    #expect(normalized.contains("Speech Text Normalizer dot swift"))
    #expect(normalized.contains("same directory, Worker Runtime dot swift"))
}

@Test func `normalize compacts repeated exact paths`() async throws {
    let original = """
    Read /tmp/Thing.swift, then read /tmp/Thing.swift again.
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("tmp Thing dot swift"))
    #expect(normalized.contains("same path"))
    #expect(occurrenceCount(of: "tmp Thing dot swift", in: normalized) == 1)
}

@Test func `normalize compacts repeated relative paths in the same directory`() async throws {
    let original = """
    Compare ./Sources/WorkerRuntime.swift and ./Sources/ProfileStore.swift.
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(original)

    #expect(normalized.contains("current directory Sources Worker Runtime dot swift"))
    #expect(normalized.contains("same directory, Profile Store dot swift"))
    #expect(!normalized.contains("dot slash Sources"))
}

@Test func `normalize applies custom replacements around built ins`() async throws {
    let profile = SpeakSwiftlyNormalization.Profile(
        id: "custom",
        name: "Custom",
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "chrommmaticallly",
                with: "chromatically",
                during: .beforeBuiltIns,
            ),
            SpeakSwiftlyNormalization.Replacement(
                "snake case stuff",
                with: "settings token",
                during: .afterBuiltIns,
                forTextFormats: [.plain],
            ),
        ],
    )

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Please say chrommmaticallly and snake_case_stuff once.",
        customProfile: profile,
    )

    #expect(normalized.contains("chromatically"))
    #expect(normalized.contains("settings token"))
    #expect(!normalized.contains("c h r o m"))
    #expect(!normalized.contains("snake case stuff"))
}

@Test func `whole token custom replacements preserve punctuation boundaries`() async throws {
    let profile = SpeakSwiftlyNormalization.Profile(
        id: "custom-whole-token",
        name: "Custom Whole Token",
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "TODO",
                with: "to do marker",
                matching: .wholeToken,
            ),
        ],
    )

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Keep (TODO), TODO, and TODO.",
        customProfile: profile,
    )

    #expect(normalized.contains("(to do marker),"))
    #expect(normalized.contains("to do marker,"))
    #expect(normalized.contains("to do marker."))
    #expect(!normalized.contains("TODO"))
}

@Test func `normalize text preserves line breaks paragraphs and suffix punctuation`() async throws {
    let profile = SpeakSwiftlyNormalization.Profile(
        id: "custom-structure",
        name: "Custom Structure",
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "TODO",
                with: "to do marker",
                matching: .wholeToken,
            ),
        ],
    )

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        """
        Keep TODO,
        and camelCaseStuff.

        Close with WorkerRuntime.swift.
        """,
        customProfile: profile,
    )

    #expect(
        normalized
            ==
            """
            Keep to do marker,
            and camel Case Stuff.

            Close with Worker Runtime dot swift.
            """,
    )
}

@Test func `normalize text preserves nine paragraph prose structure`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        """
        First paragraph, with a comma after the opening phrase. It mentions camelCaseStuff and closes cleanly.

        Second paragraph keeps speaking in ordinary prose. It mentions WorkerRuntime.swift, then ends with a period.

        Third paragraph asks for calm structure, not flattening. It keeps every sentence where it started.

        Fourth paragraph says TODO should stay where it belongs, if replaced. It also keeps commas, periods, and spacing intact.

        Fifth paragraph brings in snake_case_stuff and kebab-case-stuff. Both should normalize without collapsing the paragraph break after them.

        Sixth paragraph mentions /tmp/Thing.swift in the middle of a sentence. The path should become speech-safe while the prose shape stays put.

        Seventh paragraph includes NSApplication.didFinishLaunchingNotification. The dotted identifier should change, but not the paragraph boundary.

        Eighth paragraph adds one more ordinary sentence, with another comma, to make the structure test harder. Nothing should be fused into its neighbors.

        Ninth paragraph closes the sample. If the formatter is still flattening prose, this test should catch it.
        """,
    )

    let paragraphs = normalized
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    #expect(paragraphs.count == 9)
    #expect(occurrenceCount(of: "\n\n", in: normalized) == 8)
    #expect(normalized.contains("First paragraph, with a comma"))
    #expect(normalized.contains("camel Case Stuff"))
    #expect(normalized.contains("Worker Runtime dot swift, then ends with a period."))
    #expect(normalized.contains("snake case stuff"))
    #expect(normalized.contains("kebab case stuff"))
    #expect(normalized.contains("tmp Thing dot swift"))
    #expect(normalized.contains("NSApplication dot did Finish Launching Notification"))
    #expect(!normalized.contains("First paragraph, with a comma after the opening phrase. It mentions camel Case Stuff and closes cleanly. Second paragraph"))
    #expect(!normalized.contains("neighbors. Ninth paragraph"))
}

@Test func `detect text format finds markdown`() {
    let markdown = """
    # Header

    Read `code` and [docs](https://example.com).
    """

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: markdown) == .markdown)
}

@Test func `detect text format finds list html cli and log inputs`() {
    let list = """
    - First
    - Second
    """
    let html = "<div><p>Hello</p></div>"
    let cli = "$ swift test"
    let log = "2026-04-05 18:00:00 ERROR Worker failed"

    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: list) == .list)
    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: html) == .html)
    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: cli) == .cli)
    #expect(SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: log) == .log)
}

@Test func `detected markdown normalizes header content`() async throws {
    let text = """
    # Header

    - First
    - Second
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        text,
    )

    #expect(normalized.contains("Header"))
}

@Test func `normalize text speaks markdown priority list labels`() async throws {
    let original = """
    - [P1] Fix the crash
    - [P2] Add tests
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
    )

    #expect(normalized.contains("Priority Level One. Fix the crash"))
    #expect(normalized.contains("Priority Level Two. Add tests"))
    #expect(!normalized.contains("[P1]"))
}

@Test func `normalize text speaks plain priority list labels`() async throws {
    let original = """
    [P4] Triage the next report
    [P5] Prepare the follow up
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
    )

    #expect(normalized.contains("Priority Level Four. Triage the next report"))
    #expect(normalized.contains("Priority Level Five. Prepare the follow up"))
    #expect(!normalized.contains("[P4]"))
}

@Test func `normalize text speaks fenced code generically`() async throws {
    let original = """
    ```swift
    let sampleRate = profile?.sampleRate ?? 24000
    ```
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
    )

    #expect(normalized.contains("Code sample."))
    #expect(normalized.contains("optional chaining"))
    #expect(normalized.contains("nil coalescing"))
}

@Test func `normalize text handles mixed fenced code without source context`() async throws {
    let original = """
    ```swift
    let sampleRate = profile?.sampleRate ?? 24000
    ```

    ```python
    value = config.get("sample_rate")
    ```
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
    )

    #expect(normalized.components(separatedBy: "Code sample.").count == 3)
    #expect(normalized.contains("optional chaining"))
    #expect(normalized.contains("nil coalescing"))
    #expect(normalized.contains("sample rate"))
}

@Test func `inline code file paths use path speech instead of generic code speech`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read `/Users/galew/Workspace/SpeakSwiftly/WorkerRuntime.swift` now.",
    )

    #expect(normalized.contains("gale wumbo Workspace Speak Swiftly Worker Runtime dot swift"))
    #expect(!normalized.contains("gale wumbo slash Workspace"))
}

@Test func `inline code file paths keep context aware shortening`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift` now.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftly",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
        ),
    )

    #expect(normalized.contains("current directory Sources Speak Swiftly Worker Runtime dot swift"))
    #expect(!normalized.contains("current directory slash"))
}

@Test func `inline code file references keep context aware shortening`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/WorkerRuntime.swift:12` now.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftly",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
        ),
    )

    #expect(normalized.contains("current directory Sources Speak Swiftly Worker Runtime dot swift at line 12"))
    #expect(!normalized.contains("gale wumbo Workspace Speak Swiftly"))
}

@Test func `inline code relative file references use directory aware path speech`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read `../Sources/WorkerRuntime.swift:12` now.",
    )

    #expect(normalized.contains("parent directory Sources Worker Runtime dot swift at line 12"))
    #expect(!normalized.contains("dot dot slash Sources"))
}

@Test func `inline slash operators stay in code speech lane`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        "Read `a/b` once.",
    )

    #expect(normalized.contains("a slash b"))
    #expect(!normalized.contains("same path"))
}

@Test func `normalize source provides explicit whole source lane`() async throws {
    let source = """
    struct WorkerRuntime {
        let sampleRate: Int
    }
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(source, as: .swift)

    #expect(!normalized.contains("open brace"))
    #expect(normalized.contains("sample Rate"))
}

@Test func `normalize source preserves line and paragraph breaks`() async throws {
    let source = """
    struct WorkerRuntime {
        let sampleRate: Int

        let fallbackValue: Int
    }
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(source, as: .swift)

    #expect(normalized.split(separator: "\n", omittingEmptySubsequences: false).count == 5)
    #expect(normalized.contains("\n\n"))
    #expect(normalized.contains("sample Rate"))
    #expect(normalized.contains("fallback Value"))
}

@Test func `normalize source adds request context preface`() async throws {
    let source = """
    struct WorkerRuntime {
        let sampleRate: Int
    }
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(
        source,
        as: .swift,
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            source: "codex",
            topic: "normalization",
        ),
    )

    #expect(normalized.hasPrefix("From codex, normalization.\n\n"))
    #expect(!normalized.contains("open brace"))
    #expect(normalized.contains("sample Rate"))
}

@Test func `compact style keeps whole source more visual and less spoken`() async throws {
    let source = """
    struct WorkerRuntime {
        let sampleRate: Int
    }
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(
        source,
        as: .swift,
        style: .compact,
    )

    #expect(!normalized.contains("open brace"))
    #expect(normalized.contains("sample Rate"))
}

@Test func `malformed source delimiters stay audible`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.source(
        "let x = ([)]",
        as: .swift,
    )

    #expect(normalized.contains("open parenthesis"))
    #expect(normalized.contains("open bracket"))
    #expect(normalized.contains("close parenthesis"))
    #expect(normalized.contains("close bracket"))
}

@Test func `styles differentiate function calls issue references flags and file refs`() async throws {
    let original = "Run foo() with --help and see #123 in WorkerRuntime.swift:42:7."

    let compact = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        style: .compact,
    )
    let balanced = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        style: .balanced,
    )
    let explicit = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        style: .explicit,
    )

    #expect(compact.contains("foo"))
    #expect(!compact.contains("function call"))
    #expect(compact.contains("help"))
    #expect(!compact.contains("double tack help"))
    #expect(compact.contains("123"))
    #expect(!compact.contains("issue 123"))

    #expect(balanced.contains("foo function"))
    #expect(balanced.contains("double tack help"))
    #expect(balanced.contains("issue 123"))
    #expect(balanced.contains("Worker Runtime dot swift line 42 column 7"))

    #expect(explicit.contains("foo function call"))
    #expect(explicit.contains("long flag help"))
    #expect(explicit.contains("issue number 123"))
    #expect(explicit.contains("file Worker Runtime dot swift line 42 column 7"))
}

@Test func `double colon stays silent except in explicit style`() async throws {
    let original = "let value = Thing::value"

    let compact = try await SpeakSwiftlyNormalization.Normalize.source(
        original,
        as: .swift,
        style: .compact,
    )
    let balanced = try await SpeakSwiftlyNormalization.Normalize.source(
        original,
        as: .swift,
        style: .balanced,
    )
    let explicit = try await SpeakSwiftlyNormalization.Normalize.source(
        original,
        as: .swift,
        style: .explicit,
    )

    #expect(compact.contains("Thing value"))
    #expect(!compact.contains("::"))
    #expect(!compact.contains("double colon"))

    #expect(balanced.contains("Thing value"))
    #expect(!balanced.contains("::"))
    #expect(!balanced.contains("double colon"))

    #expect(explicit.contains("Thing double colon value"))
}

@Test func `styles use at line for line only file references`() async throws {
    let original = "See MarvisTTSModel.swift:208."

    let balanced = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        style: .balanced,
    )
    let explicit = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        style: .explicit,
    )

    #expect(balanced.contains("Marvis TTS Model dot swift at line 208"))
    #expect(explicit.contains("file Marvis TTS Model dot swift at line 208"))
}

@Test func `balanced style speaks short and long cli flag prefixes as tack words`() async throws {
    let original = "Run codex --version and git branch -d."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(
        original,
        style: .balanced,
    )

    #expect(normalized.contains("codex double tack version"))
    #expect(normalized.contains("git branch tack d"))
    #expect(!normalized.contains("dash"))
}
