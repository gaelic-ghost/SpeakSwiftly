# v3.0.9 Release Notes

## What changed

- added an iOS Simulator compile-and-smoke validation lane to CI
- fenced the worker-driven e2e harness as macOS-only so the shared package test
  target compiles honestly for iOS
- fixed runtime memory snapshot portability by treating `proc_pid_rusage` as a
  macOS-only API
- documented the new iOS validation lane across README, CONTRIBUTING, and
  maintainer notes

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release focused on portability and validation hardening
- the iOS validation lane is intentionally library-first and simulator-based; it
  does not yet imply a full app-hosted or real-device iOS end-to-end workflow
- macOS worker e2e coverage remains macOS-only because the current harness
  launches the published CLI worker process

## Verification performed

```bash
sh scripts/repo-maintenance/validate-all.sh
```

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/derived-data/release-v3-0-9-macos \
  -clonedSourcePackagesDirPath .local/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/derived-data/release-v3-0-9-macos/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests'
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/derived-data/release-v3-0-9-macos/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/ModelClientsTests'
```

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=iOS Simulator,id=4343A7EF-1074-44EB-8FD6-7972330DD08E' \
  -derivedDataPath .local/derived-data/ios-smoke \
  -clonedSourcePackagesDirPath .local/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/derived-data/ios-smoke/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_iphonesimulator26.4-arm64.xctestrun \
  -destination 'platform=iOS Simulator,id=4343A7EF-1074-44EB-8FD6-7972330DD08E' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests' \
  -only-testing:'SpeakSwiftlyTests/SupportResourcesTests' \
  -only-testing:'SpeakSwiftlyTests/ProfileStoreTests'
```
