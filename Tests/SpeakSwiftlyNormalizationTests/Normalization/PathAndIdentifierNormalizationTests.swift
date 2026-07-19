@testable import SpeakSwiftlyNormalization
import Testing

private func occurrenceCount(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

// MARK: - File Paths and Names

@Test func `file paths become spoken paths`() {
    let text = "Path: /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift."

    let normalized = TextNormalizer.normalizeFilePaths(text)

    #expect(normalized.contains("gale wumbo Workspace Speak Swiftly"))
    #expect(normalized.contains("Speech Text Normalizer dot swift"))
}

@Test func `file paths use configured gale aliases`() {
    let text = "Path: /Users/galem/Workspace/SpeakSwiftly."

    let normalized = TextNormalizer.normalizeFilePaths(text)

    #expect(normalized.contains("gale mini Workspace Speak Swiftly"))
}

@Test func `dashed file paths become speech safe spacing`() {
    let text = "Path: /tmp/speak-to-user/path-now."

    let normalized = TextNormalizer.normalizeFilePaths(text)

    #expect(normalized.contains("tmp speak to user path now"))
    #expect(!normalized.contains("dash"))
}

@Test func `file paths inside current directory omit the absolute prefix`() {
    let text = "Path: /Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift."

    let normalized = TextNormalizer.normalizeFilePaths(
        text,
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftly",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
        ),
    )

    #expect(normalized.contains("current directory Sources Speak Swiftly"))
    #expect(normalized.contains("Speech Text Normalizer dot swift"))
    #expect(!normalized.contains("gale wumbo slash Workspace slash Speak Swiftly"))
    #expect(!normalized.contains("gale wumbo Workspace Speak Swiftly slash"))
}

@Test func `file paths inside repo root but outside current directory keep repo root context`() {
    let text = "Path: /Users/galew/Workspace/SpeakSwiftly/README.md."

    let normalized = TextNormalizer.normalizeFilePaths(
        text,
        requestContext: SpeakSwiftlyNormalization.RequestContext(
            reqPurpose: .speech,
            cwd: "/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly",
            repoRoot: "/Users/galew/Workspace/SpeakSwiftly",
        ),
    )

    #expect(normalized.contains("repo root README dot md"))
    #expect(!normalized.contains("gale wumbo slash Workspace slash Speak Swiftly"))
}

@Test func `relative file paths become directory aware speech`() {
    let text = "Path: ./Sources/WorkerRuntime.swift and ../README.md."

    let normalized = TextNormalizer.normalizeFilePaths(text)

    #expect(normalized.contains("current directory Sources Worker Runtime dot swift"))
    #expect(normalized.contains("parent directory README dot md"))
    #expect(!normalized.contains("dot slash Sources"))
    #expect(!normalized.contains("dot dot slash README"))
}

@Test func `file paths speak known extension aliases naturally`() async throws {
    let text = """
    Read /tmp/App.xcodeproj, project.pbxproj, Workspace.xcworkspace, Build.xcconfig, App.xcscheme, App.xctestplan, Run.xcresult, Assets.xcassets, Localizable.xcstrings, PrivacyInfo.xcprivacy, App.entitlements, App.dSYM, guide.mdx, page.tsx, widget.jsx, settings.jsonc, config.toml, workflow.yaml, workflow.yml, notebook.ipynb, module.wasm, cache.sqlite, and state.db.
    """

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("App dot xcode project"))
    #expect(normalized.contains("project dot xcode project file"))
    #expect(normalized.contains("Workspace dot xcode workspace"))
    #expect(normalized.contains("Build dot xcode config"))
    #expect(normalized.contains("App dot xcode scheme"))
    #expect(normalized.contains("App dot xcode test plan"))
    #expect(normalized.contains("Run dot xcode result bundle"))
    #expect(normalized.contains("Assets dot xcode asset catalog"))
    #expect(normalized.contains("Localizable dot xcode string catalog"))
    #expect(normalized.contains("Privacy Info dot privacy manifest"))
    #expect(normalized.contains("App dot entitlements"))
    #expect(normalized.contains("App dot debug symbols bundle"))
    #expect(normalized.contains("guide dot markdown jsx"))
    #expect(normalized.contains("page dot typescript jsx"))
    #expect(normalized.contains("widget dot javascript jsx"))
    #expect(normalized.contains("settings dot json with comments"))
    #expect(normalized.contains("config dot toml"))
    #expect(normalized.contains("workflow dot yaml"))
    #expect(normalized.contains("notebook dot jupyter notebook"))
    #expect(normalized.contains("module dot web assembly"))
    #expect(normalized.contains("cache dot sqlite database"))
    #expect(normalized.contains("state dot database"))
}

@Test func `file line references preserve line narration after extension aliases`() async throws {
    let text = "Inspect project.pbxproj:42:7 and App.xcodeproj:18."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("project dot xcode project file line 42 column 7"))
    #expect(normalized.contains("App dot xcode project at line 18"))
}

// MARK: - Identifier and Code Speech

@Test func `dotted identifiers become spoken identifiers`() async throws {
    let text = "Read NSApplication.didFinishLaunchingNotification once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("NSApplication dot did Finish Launching Notification"))
}

@Test func `dotted identifiers accept hyphenated alias segments`() async throws {
    let normalized = try await SpeakSwiftlyNormalization.Normalize.text("guide.markdown-jsx")

    #expect(normalized.contains("guide dot markdown jsx"))
}

@Test func `snake case identifiers become spoken identifiers`() async throws {
    let text = "Read snake_case_stuff once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("snake case stuff"))
    #expect(!normalized.contains("underscore"))
}

@Test func `dashed identifiers become speech safe spacing`() {
    let normalized = TextNormalizer.spokenIdentifier("kebab-case-stuff")

    #expect(normalized.contains("kebab case stuff"))
    #expect(!normalized.contains("dash"))
}

@Test func `camel case identifiers become spoken identifiers`() async throws {
    let text = "Read camelCaseStuff once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("camel Case Stuff"))
}

@Test func `math and typed identifiers become speech safe phrases`() async throws {
    let text = "Read cosF32, sinF64, and tanU32 once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("cosine float thirty two"))
    #expect(normalized.contains("sine float sixty four"))
    #expect(normalized.contains("tangent unsigned integer thirty two"))
}

@Test func `standalone typed scalar tokens use base pronunciations`() async throws {
    let text = "Use f32, i64, and usize once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("float thirty two"))
    #expect(normalized.contains("signed integer sixty four"))
    #expect(normalized.contains("unsigned integer size"))
}

@Test func `currency amounts become spoken currency phrases`() async throws {
    let text = "Use $73, £4, £3.72, $9.39, and €2.05 once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("seventy three dollars"))
    #expect(normalized.contains("four pounds"))
    #expect(normalized.contains("three pounds, seventy two"))
    #expect(normalized.contains("nine dollars and thirty nine cents"))
    #expect(normalized.contains("two euros and five cents"))
}

@Test func `measured values become spoken unit phrases with or without one space`() async throws {
    let text = "Read 42km, 42 km, 32in, 256GB, 512Gb, 4500RPM, and 165lbs once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("forty two kilometers"))
    #expect(occurrenceCount(of: "forty two kilometers", in: normalized) == 2)
    #expect(normalized.contains("thirty two inches"))
    #expect(normalized.contains("two hundred fifty six gigabytes"))
    #expect(normalized.contains("five hundred twelve gigabits"))
    #expect(normalized.contains("four thousand five hundred rotations per minute"))
    #expect(normalized.contains("one hundred sixty five pounds"))
}

@Test func `measured values cover storage bandwidth and additional distance weight units`() async throws {
    let text = "Read 8 MB, 9Mb, 10 mb, 2TB, 2Tb, 11KBps, 12KB/s, 13Kbps, 14kbps, 15Kb/s, 16MBps, 17MB/s, 18Mbps, 19mbps, 20Mb/s, 21GBps, 22GB/s, 23Gbps, 24gbps, 25Gb/s, 26TBps, 27TB/s, 28Tbps, 29tbps, 30Tb/s, 83 mi, and 90 kg once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("eight megabytes"))
    #expect(normalized.contains("nine megabits"))
    #expect(normalized.contains("ten megabits"))
    #expect(normalized.contains("two terabytes"))
    #expect(normalized.contains("two terabits"))
    #expect(normalized.contains("eleven kilobytes per second"))
    #expect(normalized.contains("twelve kilobytes per second"))
    #expect(normalized.contains("thirteen kilobits per second"))
    #expect(normalized.contains("fourteen kilobits per second"))
    #expect(normalized.contains("fifteen kilobits per second"))
    #expect(normalized.contains("sixteen megabytes per second"))
    #expect(normalized.contains("seventeen megabytes per second"))
    #expect(normalized.contains("eighteen megabits per second"))
    #expect(normalized.contains("nineteen megabits per second"))
    #expect(normalized.contains("twenty megabits per second"))
    #expect(normalized.contains("twenty one gigabytes per second"))
    #expect(normalized.contains("twenty two gigabytes per second"))
    #expect(normalized.contains("twenty three gigabits per second"))
    #expect(normalized.contains("twenty four gigabits per second"))
    #expect(normalized.contains("twenty five gigabits per second"))
    #expect(normalized.contains("twenty six terabytes per second"))
    #expect(normalized.contains("twenty seven terabytes per second"))
    #expect(normalized.contains("twenty eight terabits per second"))
    #expect(normalized.contains("twenty nine terabits per second"))
    #expect(normalized.contains("thirty terabits per second"))
    #expect(normalized.contains("eighty three miles"))
    #expect(normalized.contains("ninety kilograms"))
}

@Test func `measured values use singular unit names for one`() async throws {
    let text = "Read 1 in, 1GB, 1Gb, 1MB, 1Mb, 1TB, 1Tb, 1KBps, 1Kbps, 1MBps, 1Mbps, 1GBps, 1Gbps, 1TBps, 1Tbps, 1lb, 1mi, 1kg, and 1RPM once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("one inch"))
    #expect(normalized.contains("one gigabyte"))
    #expect(normalized.contains("one gigabit"))
    #expect(normalized.contains("one megabyte"))
    #expect(normalized.contains("one megabit"))
    #expect(normalized.contains("one terabyte"))
    #expect(normalized.contains("one terabit"))
    #expect(normalized.contains("one kilobyte per second"))
    #expect(normalized.contains("one kilobit per second"))
    #expect(normalized.contains("one megabyte per second"))
    #expect(normalized.contains("one megabit per second"))
    #expect(normalized.contains("one gigabyte per second"))
    #expect(normalized.contains("one gigabit per second"))
    #expect(normalized.contains("one terabyte per second"))
    #expect(normalized.contains("one terabit per second"))
    #expect(normalized.contains("one pound"))
    #expect(normalized.contains("one mile"))
    #expect(normalized.contains("one kilogram"))
    #expect(normalized.contains("one rotation per minute"))
}

@Test func `line only file references use at line narration`() async throws {
    let text = "Read MarvisTTSModel.swift:208 once."

    let normalized = try await SpeakSwiftlyNormalization.Normalize.text(text)

    #expect(normalized.contains("Marvis TTS Model dot swift at line 208"))
}

@Test func `code heavy lines become spoken code`() {
    let text = #"let fallback = weirdWords.first(where: { $0.hasPrefix("q") }) ?? "nothing""#

    let normalized = TextNormalizer.normalizeCodeHeavyLines(
        text,
        format: .source(.swift),
    )

    #expect(!normalized.contains("open brace"))
    #expect(normalized.contains("nil coalescing"))
    #expect(normalized.contains("has Prefix"))
}

@Test func `unmatched code delimiters still speak`() {
    let text = #"let fallback = weirdWords.first(where: { $0.hasPrefix("q") ]"#

    let normalized = TextNormalizer.normalizeCodeHeavyLines(
        text,
        format: .source(.swift),
    )

    #expect(normalized.contains("open brace"))
    #expect(normalized.contains("close bracket"))
}

@Test func `spiral prone words are spelled out`() {
    let text = "Also say chrommmaticallly and qqqwweerrtyy once."

    let normalized = TextNormalizer.normalizeSpiralProneWords(text)

    #expect(normalized.contains("c h r o m m m a t i c a l l l y"))
    #expect(normalized.contains("q q q w w e e r r t y y"))
}
