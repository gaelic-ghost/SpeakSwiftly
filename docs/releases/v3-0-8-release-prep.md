# v3.0.8 Release Prep

Date: 2026-04-17

This note captures the intended scope and validation story for the `v3.0.8`
patch release.

## Intended Scope

The release should be framed as:

- a dependency uptake patch that moves `SpeakSwiftly` onto the `TextForSpeech`
  `0.17.1` bugfix release
- a source-layout cleanup that splits oversized playback support types into
  narrower files
- a test-layout cleanup that mirrors runtime and storage coverage more cleanly
  to the source tree

Included work on the current branch:

- bump the `TextForSpeech` package requirement to `0.17.1` and refresh
  `Package.resolved`
- split the old playback support sink file into focused files for playback
  configuration, events, threshold control, support models, and mutable request
  state
- reorganize runtime control-surface tests into narrower files with shared test
  support helpers
- move storage-store tests into `Tests/SpeakSwiftlyTests/Storage` so the test
  tree mirrors the source layout by feature area
- validate the release slice through the Xcode-backed end-to-end lane covering
  Chatterbox, generated artifacts, Marvis, and Qwen workflows

Not included:

- a public API redesign
- a broader playback-runtime behavior change beyond the existing refactor and
  the upstream `TextForSpeech` bugfix uptake
- benchmark-only or deep-trace-only e2e lanes

## Dependency Mapping

- `TextForSpeech` `0.17.1` should be referenced as the dependency update:
  - `SpeakSwiftly` now picks up the significant upstream bugfix from that patch
    release
  - this release should describe the package bump honestly as dependency uptake,
    not as a local reimplementation of the upstream fix

## Validation Performed

Dependency resolution:

```bash
swift package resolve
```

Xcode-backed package build:

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/xcode/derived-data/release-v3-0-8-prep \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

Xcode-backed real-model e2e lane:

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/release-v3-0-8-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.e2e.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/ChatterboxWorkflowSuite' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/GeneratedBatchSuite' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/GeneratedFileSuite' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/MarvisWorkflowSuite' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/QwenWorkflowSuite'
```

## Release Checklist

- keep the GitHub release notes focused on the `TextForSpeech` `0.17.1`
  dependency uptake and the maintainability cleanup in `SpeakSwiftly`
- mention that the real-model Xcode-backed e2e slice passed with 14 tests across
  6 suites
- describe the source and test reorganization as internal cleanup rather than a
  public-surface change
- keep verification notes explicit about using the Xcode-backed package lane
  rather than plain SwiftPM e2e execution
