# v3.0.5 Release Prep

This note captures the intended scope and validation story for the `v3.0.5`
patch release branch.

## Intended Scope

The release should be framed as runtime correctness and validation hardening,
not as a new Marvis overlap feature release.

Included work on `release/v3-0-5-prep`:

- runtime and playback cleanup already present on branch after `v3.0.4`
- startup playback cleanup for issue `#5`
- startup playback environment cleanup for issue `#6`
- maintainer validation-lane documentation
- `TextForSpeech` dependency refresh to `v0.17.0`

Not included:

- a claimed fix for issue `#7`
- experimental Marvis dynamic-overlap policies
- a new `marvis_single_lane` backend
- broader startup or overlap redesign beyond the narrow playback-lazying fix

## Issue Mapping

- `#5` should be referenced as fixed by the runtime startup cleanup:
  - resident models still preload
  - playback hardware now waits for the first actual playback request
- `#6` should be referenced as fixed by the environment-event cleanup:
  - startup no longer emits `playback_output_device_observed` just because the runtime bound its sink
  - output-device observation now happens when playback preparation actually occurs
- `#7` should stay open:
  - this branch improves startup behavior and removes one suspicious preload path
  - it does not prove root cause for the allocator warning

## Validation Performed

Known lane rule:

- plain SwiftPM remains the fast default
- if the vendored `mlx-audio-swift` parser failure in `EnglishG2P.swift` appears, switch to the documented Xcode-backed lane instead of retrying the same SwiftPM command
- GitHub Actions should use that same Xcode-backed fallback for package build-and-test coverage until the vendored parser snag is resolved

Validation already run on this branch:

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
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests'
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun .local/xcode/derived-data/release-v3-0-5-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/ModelClientsTests'
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun .local/xcode/derived-data/release-v3-0-5-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests'
```

The Xcode-backed rebuild was also rerun after updating `TextForSpeech` to
`v0.17.0`.

## Pre-PR Checklist

- ensure `Package.resolved` is committed at `TextForSpeech` `0.17.0`
- write the PR as a patch-release hardening pass, not as a new overlap feature
- reference issues `#5` and `#6`
- explicitly note that `#7` remains investigative
- keep release notes honest about the validation-lane caveat
