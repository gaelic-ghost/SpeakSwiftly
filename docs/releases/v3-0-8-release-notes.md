# v3.0.8 Release Notes

## What changed

- bumped `TextForSpeech` to `0.17.1` to pick up the latest upstream patch-level
  bugfix release
- split the oversized playback support types into narrower files for playback
  configuration, events, threshold control, support models, and request state
- reorganized runtime control-surface and storage tests so the test tree more
  closely mirrors the source layout by feature area

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release aimed at upstream bugfix uptake and maintainability
  cleanup inside `SpeakSwiftly`
- the `TextForSpeech` change is a dependency update, not a new local behavior
  flag or migration surface
- if plain SwiftPM validation still trips over the vendored `EnglishG2P.swift`
  parser issue, use the documented Xcode-backed package lane for release-grade
  validation instead of retrying the same plain `swift test` path

## Verification performed

```bash
swift package resolve
```

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/xcode/derived-data/release-v3-0-8-prep \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

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
