import Testing
import TextForSpeechCore

@Test func textForSpeechRuntimeReturnsStableSnapshotsForLaterJobs() {
    let initialProfile = TextNormalizationProfile(
        id: "default",
        name: "Default",
        replacements: [
            TextReplacementRule("foo", with: "bar")
        ]
    )
    let runtime = TextForSpeechRuntime(profile: initialProfile)

    let firstSnapshot = runtime.snapshot()
    runtime.use(
        TextNormalizationProfile(
            id: "default",
            name: "Updated",
            replacements: [
                TextReplacementRule("foo", with: "baz")
            ]
        )
    )
    let secondSnapshot = runtime.snapshot()

    #expect(firstSnapshot.name == "Default")
    #expect(firstSnapshot.replacements.first?.replacement == "bar")
    #expect(secondSnapshot.name == "Updated")
    #expect(secondSnapshot.replacements.first?.replacement == "baz")
}

@Test func textForSpeechProfileFiltersReplacementsByPhaseAndKind() {
    let profile = TextNormalizationProfile(
        replacements: [
            TextReplacementRule(
                "Thing",
                with: "Swift thing",
                id: "swift",
                in: .beforeNormalization,
                for: [.swift]
            ),
            TextReplacementRule(
                "Thing",
                with: "Any source thing",
                id: "source",
                in: .beforeNormalization,
                for: [.source],
                priority: 10
            ),
            TextReplacementRule(
                "Thing",
                with: "Final thing",
                id: "final",
                in: .afterNormalization
            )
        ]
    )

    let beforeNormalization = profile.replacements(for: .beforeNormalization, in: .swift)
    let afterNormalization = profile.replacements(for: .afterNormalization, in: .swift)

    #expect(beforeNormalization.map(\.id) == ["source", "swift"])
    #expect(afterNormalization.map(\.id) == ["final"])
}
