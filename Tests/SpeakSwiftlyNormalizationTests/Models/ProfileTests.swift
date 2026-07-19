import Foundation
@testable import SpeakSwiftlyNormalization
import Testing

// MARK: - Profiles

@Test func `profile filters replacements by phase and format`() {
    let profile = SpeakSwiftlyNormalization.Profile(
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "Thing",
                with: "Swift thing",
                id: "swift",
                during: .beforeBuiltIns,
                forTextFormats: [],
                forSourceFormats: [.swift],
            ),
            SpeakSwiftlyNormalization.Replacement(
                "Thing",
                with: "Any source thing",
                id: "source",
                during: .beforeBuiltIns,
                forTextFormats: [],
                forSourceFormats: [.generic],
                priority: 10,
            ),
            SpeakSwiftlyNormalization.Replacement(
                "Thing",
                with: "Final thing",
                id: "final",
                during: .afterBuiltIns,
            ),
        ],
    )

    let beforeBuiltIns = profile.replacements(
        for: SpeakSwiftlyNormalization.Replacement.Phase.beforeBuiltIns,
        in: SpeakSwiftlyNormalization.SourceFormat.swift,
    )
    let afterBuiltIns = profile.replacements(
        for: SpeakSwiftlyNormalization.Replacement.Phase.afterBuiltIns,
        in: SpeakSwiftlyNormalization.SourceFormat.swift,
    )

    #expect(beforeBuiltIns.map(\.id) == ["source", "swift"])
    #expect(afterBuiltIns.map(\.id) == ["final"])
}

@Test func `profile filters text scoped replacements independently from source scoped ones`() {
    let profile = SpeakSwiftlyNormalization.Profile(
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "Thing",
                with: "Markdown thing",
                id: "markdown",
                during: .beforeBuiltIns,
                forTextFormats: [.markdown],
            ),
            SpeakSwiftlyNormalization.Replacement(
                "Thing",
                with: "Swift thing",
                id: "swift",
                during: .beforeBuiltIns,
                forTextFormats: [],
                forSourceFormats: [.swift],
            ),
        ],
    )

    #expect(
        profile.replacements(
            for: SpeakSwiftlyNormalization.Replacement.Phase.beforeBuiltIns,
            in: SpeakSwiftlyNormalization.TextFormat.markdown,
        )
        .map(\.id) == ["markdown"],
    )
    #expect(
        profile.replacements(
            for: SpeakSwiftlyNormalization.Replacement.Phase.beforeBuiltIns,
            in: SpeakSwiftlyNormalization.SourceFormat.swift,
        )
        .map(\.id) == ["swift"],
    )
}

@Test func `generic source scoped replacements apply to specific source formats`() {
    let profile = SpeakSwiftlyNormalization.Profile(
        replacements: [
            SpeakSwiftlyNormalization.Replacement(
                "Thing",
                with: "Any source thing",
                id: "source",
                during: .beforeBuiltIns,
                forTextFormats: [],
                forSourceFormats: [.generic],
            ),
        ],
    )

    #expect(
        profile.replacements(
            for: SpeakSwiftlyNormalization.Replacement.Phase.beforeBuiltIns,
            in: SpeakSwiftlyNormalization.SourceFormat.swift,
        )
        .map(\.id) == ["source"],
    )
    #expect(
        profile.replacements(
            for: SpeakSwiftlyNormalization.Replacement.Phase.beforeBuiltIns,
            in: SpeakSwiftlyNormalization.SourceFormat.python,
        )
        .map(\.id) == ["source"],
    )
}

@Test func `default profile starts empty`() {
    #expect(SpeakSwiftlyNormalization.Profile.default.id == "default")
    #expect(SpeakSwiftlyNormalization.Profile.default.name == "Default")
    #expect(SpeakSwiftlyNormalization.Profile.default.replacements.isEmpty)
}

@Test func `balanced base composes semantic core and balanced style`() {
    let balanced = SpeakSwiftlyNormalization.Profile.builtInBase(style: .balanced)

    #expect(SpeakSwiftlyNormalization.Profile.base == balanced)
    #expect(!balanced.replacements.contains(where: { $0.id == "base-url" }))
    #expect(balanced.replacements.contains(where: { $0.id == "base-text-code-line" }))
}

@Test func `semantic core composes semantic role fragments`() {
    let semanticCore = SpeakSwiftlyNormalization.Profile.semanticCore

    #expect(semanticCore.replacements.contains(where: { $0.id == "base-f32" }))
    #expect(semanticCore.replacements.contains(where: { $0.id == "base-xcodeproj-extension" }))
    #expect(!semanticCore.replacements.contains(where: { $0.id == "base-url" }))
    #expect(semanticCore.replacements.contains(where: { $0.id == "base-currency-amount" }))
    #expect(semanticCore.replacements.contains(where: { $0.id == "base-measured-value" }))
}

@Test func `built in style lookup returns named preset profiles`() {
    #expect(SpeakSwiftlyNormalization.Profile.builtInStyle(.balanced).id == "base")
    #expect(SpeakSwiftlyNormalization.Profile.builtInStyle(.compact).id == "compact-built-in-style")
    #expect(SpeakSwiftlyNormalization.Profile.builtInStyle(.explicit).id == "explicit-built-in-style")
}

@Test func `request context decodes missing attributes as empty dictionary`() throws {
    let json = """
    {
      "reqPurpose": "speech",
      "source": "codex",
      "topic": "normalization"
    }
    """
    let data = Data(json.utf8)

    let decoded = try JSONDecoder().decode(SpeakSwiftlyNormalization.RequestContext.self, from: data)

    #expect(decoded.source == "codex")
    #expect(decoded.topic == "normalization")
    #expect(decoded.reqPurpose == .speech)
    #expect(decoded.prefacePolicy == nil)
    #expect(decoded.attributes.isEmpty)
}

@Test func `request context rejects removed audio stream purpose`() throws {
    let json = """
    {
      "reqPurpose": "audioStream",
      "source": "codex",
      "topic": "stream"
    }
    """
    let data = Data(json.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(SpeakSwiftlyNormalization.RequestContext.self, from: data)
    }
}

@Test func `request context normalizes path context`() {
    let context = SpeakSwiftlyNormalization.RequestContext(
        reqPurpose: .speech,
        cwd: "/Users/galew/Workspace/SpeakSwiftly/../SpeakSwiftly",
        repoRoot: "  /Users/galew/Workspace/SpeakSwiftly  ",
    )

    #expect(context.cwd == "/Users/galew/Workspace/SpeakSwiftly")
    #expect(context.repoRoot == "/Users/galew/Workspace/SpeakSwiftly")
}

@Test func `compact style drops balanced code line rules but keeps semantic core`() {
    let compact = SpeakSwiftlyNormalization.Profile.builtInBase(style: .compact)

    #expect(!compact.replacements.contains(where: { $0.id == "base-url" }))
    #expect(compact.replacements.contains(where: { $0.id == "compact-function-call" }))
    #expect(!compact.replacements.contains(where: { $0.id == "base-text-code-line" }))
    #expect(!compact.replacements.contains(where: { $0.id == "base-source-line" }))
}

@Test func `explicit style carries its own style specific rules`() {
    let explicit = SpeakSwiftlyNormalization.Profile.builtInBase(style: .explicit)

    #expect(explicit.replacements.contains(where: { $0.id == "explicit-function-call" }))
    #expect(explicit.replacements.contains(where: { $0.id == "explicit-cli-flag" }))
    #expect(explicit.replacements.contains(where: { $0.id == "base-text-code-line" }))
}
