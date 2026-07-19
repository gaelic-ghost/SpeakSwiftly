import Foundation
@testable import SpeakSwiftly
import Testing

@Test func `normalizer bootstraps and persists the default profile`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }

    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
    let style = await normalizer.style.getActive()
    let active = await normalizer.profiles.getActive()

    #expect(style == .balanced)
    #expect(active.id == "default")
    #expect(active.summary.replacementCount == 0)
    #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
}

@Test func `normalizer lists every style and summarization provider`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)

    let styles = await normalizer.style.list()
    let providers = await normalizer.summarization.list()

    #expect(styles.map(\.style) == [.balanced, .compact, .explicit])
    #expect(styles.allSatisfy { !$0.summary.isEmpty })
    #expect(providers.map(\.provider) == [.codexExec, .openAIResponses, .foundationModels, .test])
    #expect(providers.allSatisfy { !$0.summary.isEmpty })
}

@Test func `normalizer applies active and selected profiles to text and source`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
    let logs = try await normalizer.profiles.create(name: "Logs")
    _ = try await normalizer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement("stderr", with: "standard error", id: "stderr-rule"),
        toProfile: logs.id,
    )

    let preview = try await normalizer.speechText("stderr", textProfileID: logs.id)
    let stillDefault = await normalizer.profiles.getActive()
    try await normalizer.profiles.setActive(id: logs.id)
    let active = try await normalizer.speechText("https://example.com and stderr")

    _ = try await normalizer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement("sampleRate", with: "sample rate override", id: "sample-rate-rule"),
    )
    let source = try await normalizer.speechSource("let sampleRate = 48_000", as: .swift)

    #expect(preview == "standard error")
    #expect(stillDefault.id == "default")
    #expect(active.contains("example dot com"))
    #expect(active.contains("standard error"))
    #expect(source.contains("sample rate override"))
    #expect(source.contains("48 000"))
}

@Test func `normalizer uses its selected summarization provider only when requested`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
    try await normalizer.summarization.set(.test)
    _ = try await normalizer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement("stderr", with: "standard error", id: "stderr-rule"),
    )

    let ordinary = try await normalizer.speechText("stderr", summarize: false)
    let summarized = try await normalizer.speechText("stderr", summarize: true)

    #expect(ordinary == "standard error")
    #expect(summarized == "standard error")
}

@Test func `normalizer profile lifecycle keeps stable ids and replacement state`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)

    let first = try await normalizer.profiles.create(name: "Logs")
    let second = try await normalizer.profiles.create(name: "Logs")
    let renamed = try await normalizer.profiles.rename(profile: first.id, to: "Operations")
    let added = try await normalizer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement("panic", with: "runtime panic", id: "panic-rule"),
        toProfile: first.id,
    )
    let patched = try await normalizer.profiles.patchReplacement(
        SpeakSwiftly.TextReplacement("panic", with: "fatal runtime panic", id: "panic-rule"),
        inProfile: first.id,
    )
    let removed = try await normalizer.profiles.removeReplacement(
        id: "panic-rule",
        fromProfile: first.id,
    )

    #expect(first.id == "logs")
    #expect(second.id == "logs-2")
    #expect(renamed.summary.name == "Operations")
    #expect(added.summary.replacementCount == 1)
    #expect(patched.replacements.first?.replacement == "fatal runtime panic")
    #expect(removed.replacements.isEmpty)

    try await normalizer.profiles.setActive(id: first.id)
    try await normalizer.profiles.delete(id: first.id)
    #expect(await normalizer.profiles.getActive().id == "default")

    try await normalizer.profiles.factoryReset()
    #expect(await normalizer.profiles.list().map(\.id) == ["default"])
}

@Test func `normalizer persists style provider active profile and rules`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let writer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
    let logs = try await writer.profiles.create(name: "Logs")
    _ = try await writer.profiles.addReplacement(
        SpeakSwiftly.TextReplacement("stderr", with: "standard error", id: "stderr-rule"),
        toProfile: logs.id,
    )
    try await writer.profiles.setActive(id: logs.id)
    try await writer.style.setActive(to: .compact)
    try await writer.summarization.set(.openAIResponses)

    let reader = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
    let active = await reader.profiles.getActive()
    let style = await reader.style.getActive()
    let provider = await reader.summarization.get()

    #expect(active.id == logs.id)
    #expect(active.replacements.first?.replacement == "standard error")
    #expect(style == .compact)
    #expect(provider == .openAIResponses)
}

@Test func `normalization state reads legacy provider key and writes only canonical key`() throws {
    let legacyJSON = """
    {
      "activeCustomProfileID": "default",
      "builtInStyle": "balanced",
      "summaryProvider": "openAIResponses",
      "profiles": { "default": { "id": "default", "name": "Default", "replacements": [] } },
      "version": 1
    }
    """
    let state = try JSONDecoder().decode(SpeakSwiftly.TextNormalizationState.self, from: Data(legacyJSON.utf8))
    let encoded = try JSONEncoder().encode(state)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    #expect(state.summarizationProvider == .openAIResponses)
    #expect(object["summarizationProvider"] as? String == "openAIResponses")
    #expect(object["summaryProvider"] == nil)
}

@Test func `normalizer repairs a missing active profile and missing default profile`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let state = SpeakSwiftly.TextNormalizationState(
        activeCustomProfileID: "missing",
        profiles: ["logs": SpeakSwiftly.TextProfile(id: "logs", name: "Logs")],
    )
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL, state: state)

    let active = await normalizer.profiles.getActive()
    let listed = await normalizer.profiles.list().map(\.id)
    #expect(active.id == "default")
    #expect(listed == ["default", "logs"])
}

@Test func `normalizer rejects unsupported state versions`() async throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    let normalizer = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
    let unsupported = SpeakSwiftly.TextNormalizationState(
        version: 99,
        activeCustomProfileID: "default",
        profiles: ["default": .default],
    )

    do {
        try await normalizer.persistence.restore(unsupported)
        Issue.record("Expected an unsupported persisted-state version error.")
    } catch let error as SpeakSwiftly.TextNormalizationPersistenceError {
        #expect(error == .unsupportedPersistedStateVersion(99))
    }
}

@Test func `normalizer reports concrete persistence failures`() throws {
    let fixture = makeNormalizationFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: true)

    do {
        _ = try SpeakSwiftly.Normalizer(persistenceURL: fixture.fileURL)
        Issue.record("Expected a directory-backed state path to fail decoding.")
    } catch let error as SpeakSwiftly.TextNormalizationPersistenceError {
        guard case let .couldNotRead(url, details) = error else {
            Issue.record("Expected a read failure, received \(error).")
            return
        }

        #expect(url == fixture.fileURL.standardizedFileURL)
        #expect(!details.isEmpty)
    }
}

@Test func `text profile transport models preserve worker coding keys`() throws {
    let details = SpeakSwiftly.TextProfileDetails(
        profileID: "logs",
        summary: SpeakSwiftly.TextProfileSummary(id: "logs", name: "Logs", replacementCount: 1),
        replacements: [SpeakSwiftly.TextReplacement("stderr", with: "standard error", id: "rule")],
    )
    let data = try JSONEncoder().encode(details)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let summary = try #require(object["summary"] as? [String: Any])

    #expect(object["profile_id"] as? String == "logs")
    #expect(summary["replacement_count"] as? Int == 1)
    #expect(try JSONDecoder().decode(SpeakSwiftly.TextProfileDetails.self, from: data) == details)
}

@Test func `normalization errors name the failed resource`() {
    #expect(SpeakSwiftly.TextProfileError.profileAlreadyExists("logs").errorDescription?.contains("'logs'") == true)
    #expect(SpeakSwiftly.TextProfileError.profileNotFound("missing").errorDescription?.contains("'missing'") == true)
    #expect(
        SpeakSwiftly.TextProfileError.replacementNotFound("rule", profileID: "logs")
            .errorDescription?
            .contains("'rule'") == true,
    )
}

private struct NormalizationFixture {
    let directoryURL: URL
    let fileURL: URL

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private func makeNormalizationFixture() -> NormalizationFixture {
    let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return NormalizationFixture(
        directoryURL: directoryURL,
        fileURL: directoryURL.appending(path: "text-profiles.json"),
    )
}
