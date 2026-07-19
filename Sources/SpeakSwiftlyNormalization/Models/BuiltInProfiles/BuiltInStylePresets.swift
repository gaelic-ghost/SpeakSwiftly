extension SpeakSwiftlyNormalization.Profile {
    /// The default shipped listening mode for general-purpose spoken output.
    static let balancedBuiltInStyle = SpeakSwiftlyNormalization.Profile(
        id: "base",
        name: "Balanced Built-In Style",
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "::",
                with: " ",
                id: "balanced-double-colon",
                priority: 50,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "balanced-function-call",
                matching: .token(.functionCall),
                using: .spokenFunctionCall(.balanced),
                priority: 40,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "balanced-issue-reference",
                matching: .token(.issueReference),
                using: .spokenIssueReference(.balanced),
                priority: 30,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "balanced-file-reference",
                matching: .token(.fileLineReference),
                using: .spokenFileReference(.balanced),
                priority: 20,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "balanced-cli-flag",
                matching: .token(.cliFlag),
                using: .spokenCLIFlag(.balanced),
                priority: 10,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "base-text-code-line",
                matching: .line(.codeLike),
                using: .spokenCode,
                forTextFormats: Set(SpeakSwiftlyNormalization.TextFormat.allCases),
                priority: -80,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "base-source-line",
                matching: .line(.nonEmpty),
                using: .spokenCode,
                forSourceFormats: [.generic],
                priority: -90,
            ),
        ],
    )

    /// A terser shipped listening mode for contexts where more visual detail
    /// can remain on screen instead of being narrated.
    static let compactBuiltInStyle = SpeakSwiftlyNormalization.Profile(
        id: "compact-built-in-style",
        name: "Compact Built-In Style",
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "::",
                with: " ",
                id: "compact-double-colon",
                priority: 50,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "compact-function-call",
                matching: .token(.functionCall),
                using: .spokenFunctionCall(.compact),
                priority: 40,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "compact-issue-reference",
                matching: .token(.issueReference),
                using: .spokenIssueReference(.compact),
                priority: 30,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "compact-file-reference",
                matching: .token(.fileLineReference),
                using: .spokenFileReference(.compact),
                priority: 20,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "compact-cli-flag",
                matching: .token(.cliFlag),
                using: .spokenCLIFlag(.compact),
                priority: 10,
            ),
        ],
    )

    /// A more narrated shipped listening mode for audio-first experiences that
    /// benefit from stronger spoken signposting.
    static let explicitBuiltInStyle = SpeakSwiftlyNormalization.Profile(
        id: "explicit-built-in-style",
        name: "Explicit Built-In Style",
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                id: "explicit-function-call",
                matching: .token(.functionCall),
                using: .spokenFunctionCall(.explicit),
                priority: 40,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "explicit-issue-reference",
                matching: .token(.issueReference),
                using: .spokenIssueReference(.explicit),
                priority: 30,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "explicit-file-reference",
                matching: .token(.fileLineReference),
                using: .spokenFileReference(.explicit),
                priority: 20,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "explicit-cli-flag",
                matching: .token(.cliFlag),
                using: .spokenCLIFlag(.explicit),
                priority: 10,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "base-text-code-line",
                matching: .line(.codeLike),
                using: .spokenCode,
                forTextFormats: Set(SpeakSwiftlyNormalization.TextFormat.allCases),
                priority: -80,
            ),
            SpeakSwiftlyNormalization.Replacement(
                id: "base-source-line",
                matching: .line(.nonEmpty),
                using: .spokenCode,
                forSourceFormats: [.generic],
                priority: -90,
            ),
        ],
    )
}
