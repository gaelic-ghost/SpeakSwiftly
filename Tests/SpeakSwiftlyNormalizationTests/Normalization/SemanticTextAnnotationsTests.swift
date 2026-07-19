@testable import SpeakSwiftlyNormalization
import Testing

@Test func `semantic attributed string marks data detector and developer token runs`() {
    let runs = TextNormalizer.semanticTokenRuns(
        in: "Open https://example.com, email mail@example.com, and Sources/App.swift:42 with sampleRate.",
    )

    #expect(
        runs.contains {
            $0.text == "https://example.com" && $0.kind == .link
        },
    )
    #expect(
        runs.contains {
            $0.text == "mail@example.com" && $0.kind == .emailAddress
        },
    )
    #expect(
        runs.contains {
            $0.text == "Sources/App.swift:42" && $0.kind == .fileLineReference
        },
    )
    #expect(
        runs.contains {
            $0.text == "sampleRate" && $0.kind == .camelCaseIdentifier
        },
    )
}

@Test func `semantic runs preserve plain text gaps around detected tokens`() {
    let runs = TextNormalizer.semanticRuns(in: "Use --verbose with buildProject().")

    #expect(
        runs.contains {
            $0.text == "--verbose" && $0.kind == .cliFlag
        },
    )
    #expect(
        runs.contains {
            $0.text == "buildProject()" && $0.kind == .functionCall
        },
    )
    #expect(runs.contains { $0.text.contains("Use ") && $0.kind == nil })
}

@Test func `semantic link runs normalize links without rewriting email addresses`() {
    let normalized = TextNormalizer.normalizeSemanticLinkRuns(
        "Open www.example.com and mail@example.com.",
    )

    #expect(normalized.contains("example dot com"))
    #expect(!normalized.contains("www"))
    #expect(normalized.contains("mail@example.com"))
}

@Test func `semantic token helper routes path and file reference runs through profile rules`() {
    let normalized = TextNormalizer.normalizeSemanticTokenRuns(
        "Read /Users/galew/Workspace/SpeakSwiftlyNormalization/Sources/App.swift and WorkerRuntime.swift:42.",
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftlyNormalization",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftlyNormalization",
        ),
        profile: SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced),
        format: .text(.plain),
        kinds: [.filePath, .fileLineReference],
    )

    #expect(normalized.contains("current directory Sources App dot swift"))
    #expect(normalized.contains("Worker Runtime dot swift at line 42"))
}

@Test func `semantic token helper lets custom token rules override built in path speech`() {
    let profile = SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced).merged(
        with: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement(
                    id: "custom-path-token",
                    matching: .token(.filePath),
                    using: .literal("custom path"),
                    priority: 100,
                ),
            ],
        ),
    )

    let normalized = TextNormalizer.normalizeSemanticTokenRuns(
        "Read /tmp/App.swift.",
        profile: profile,
        format: .text(.plain),
        kinds: [.filePath],
    )

    #expect(normalized == "Read custom path.")
}

@Test func `semantic token helper routes style sensitive developer tokens`() {
    let normalized = TextNormalizer.normalizeSemanticTokenRuns(
        "Run foo() with --help for #123.",
        profile: SpeakSwiftlyNormalization.Profile.builtInBase(style: .explicit),
        format: .text(.plain),
        kinds: [.functionCall, .issueReference, .cliFlag],
    )

    #expect(normalized.contains("foo function call"))
    #expect(normalized.contains("long flag help"))
    #expect(normalized.contains("issue number 123"))
}

@Test func `semantic token helper lets custom style token rules override built ins`() {
    let profile = SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced).merged(
        with: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement(
                    id: "custom-cli-flag",
                    matching: .token(.cliFlag),
                    using: .literal("custom flag"),
                    priority: 100,
                ),
            ],
        ),
    )

    let normalized = TextNormalizer.normalizeSemanticTokenRuns(
        "Run --verbose.",
        profile: profile,
        format: .text(.plain),
        kinds: [.cliFlag],
    )

    #expect(normalized == "Run custom flag.")
}

@Test func `semantic token helper routes identifier token rules`() {
    let profile = SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced).merged(
        with: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement(
                    id: "custom-dotted-identifier",
                    matching: .token(.dottedIdentifier),
                    using: .literal("custom dotted"),
                    priority: 100,
                ),
            ],
        ),
    )

    let normalized = TextNormalizer.normalizeSemanticTokenRuns(
        "Read NSApplication.didFinishLaunchingNotification and snake_case_stuff.",
        profile: profile,
        format: .text(.plain),
        kinds: [.dottedIdentifier, .snakeCaseIdentifier],
    )

    #expect(normalized.contains("custom dotted"))
    #expect(normalized.contains("snake case stuff"))
}

@Test func `semantic aware replacement pass preserves rule priority ordering`() {
    let lowPriorityOverride = SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced).merged(
        with: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement(
                    "foo()",
                    with: "custom foo",
                    id: "low-priority-function-name",
                    priority: 0,
                ),
            ],
        ),
    )
    let highPriorityOverride = SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced).merged(
        with: SpeakSwiftlyNormalization.Profile(
            replacements: [
                SpeakSwiftlyNormalization.Replacement(
                    "foo()",
                    with: "custom foo",
                    id: "high-priority-function-name",
                    priority: 100,
                ),
            ],
        ),
    )

    let lowPriority = TextNormalizer.applySemanticAwareReplacementRules(
        "Run foo().",
        requestContext: nil,
        profile: lowPriorityOverride,
        format: .text(.plain),
        phase: .beforeBuiltIns,
        kinds: [.functionCall],
    )
    let highPriority = TextNormalizer.applySemanticAwareReplacementRules(
        "Run foo().",
        requestContext: nil,
        profile: highPriorityOverride,
        format: .text(.plain),
        phase: .beforeBuiltIns,
        kinds: [.functionCall],
    )

    #expect(lowPriority.contains("foo function"))
    #expect(!lowPriority.contains("custom foo"))
    #expect(highPriority.contains("custom foo"))
}
