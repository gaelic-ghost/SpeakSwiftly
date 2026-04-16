# v3.0.5 Release Notes

## What changed

- deferred playback hardware preparation until the first real playback request
  instead of touching playback at resident-model startup
- stopped emitting startup `playback_output_device_observed` noise before any
  active request exists
- clarified the package validation lanes so maintainers and CI switch cleanly to
  the repo-root Xcode-backed package lane when the vendored
  `mlx-audio-swift` SwiftPM parser snag appears
- refreshed `TextForSpeech` from `0.16.0` to `0.17.0`

## Breaking changes

- none

## Migration or upgrade notes

- if plain `swift build` or `swift test` hits the current vendored parser
  failure in `EnglishG2P.swift`, stop retrying the same SwiftPM lane and switch
  to the documented repo-root Xcode-backed `build-for-testing` plus targeted
  `test-without-building` flow
- issue `#7` remains investigative; this release removes one suspicious startup
  playback path, but it does not claim a root-cause fix for the allocator
  warning

## Verification performed

```bash
sh scripts/repo-maintenance/validate-all.sh
```

```bash
swift package dump-package
```

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/xcode/derived-data/release-v3-0-5-prep \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun .local/xcode/derived-data/release-v3-0-5-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests'
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun .local/xcode/derived-data/release-v3-0-5-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/ModelClientsTests'
```
