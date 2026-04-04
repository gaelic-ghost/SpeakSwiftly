import Testing
import TextForSpeechCore

@Test func textNormalizationRuntimeReturnsStableSnapshotsForLaterJobs() {
    let initialProfile = TextNormalizationProfile(
        id: "default",
        displayName: "Default",
        replacementRules: [
            TextReplacementRule(match: "foo", replacement: "bar")
        ]
    )
    let runtime = TextNormalizationRuntime(currentProfile: initialProfile)

    let firstSnapshot = runtime.snapshot()
    runtime.replaceCurrentProfile(
        with: TextNormalizationProfile(
            id: "default",
            displayName: "Updated",
            replacementRules: [
                TextReplacementRule(match: "foo", replacement: "baz")
            ]
        )
    )
    let secondSnapshot = runtime.snapshot()

    #expect(firstSnapshot.displayName == "Default")
    #expect(firstSnapshot.replacementRules.first?.replacement == "bar")
    #expect(secondSnapshot.displayName == "Updated")
    #expect(secondSnapshot.replacementRules.first?.replacement == "baz")
}

@Test func textNormalizationProfileFiltersRulesByPhaseAndInputKind() {
    let profile = TextNormalizationProfile(
        replacementRules: [
            TextReplacementRule(
                id: "swift",
                match: "Thing",
                replacement: "Swift thing",
                phase: .beforeBuiltIns,
                inputKinds: [.swiftSource]
            ),
            TextReplacementRule(
                id: "source",
                match: "Thing",
                replacement: "Any source thing",
                phase: .beforeBuiltIns,
                inputKinds: [.sourceCode],
                priority: 10
            ),
            TextReplacementRule(
                id: "final",
                match: "Thing",
                replacement: "Final thing",
                phase: .afterBuiltIns
            )
        ]
    )

    let beforeBuiltIns = profile.replacementRules(for: .beforeBuiltIns, inputKind: .swiftSource)
    let afterBuiltIns = profile.replacementRules(for: .afterBuiltIns, inputKind: .swiftSource)

    #expect(beforeBuiltIns.map(\.id) == ["source", "swift"])
    #expect(afterBuiltIns.map(\.id) == ["final"])
}
