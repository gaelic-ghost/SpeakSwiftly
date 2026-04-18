# v3.0.9 Release Prep

Date: 2026-04-17

This note captures the intended scope and validation story for the `v3.0.9`
patch release.

## Intended Scope

The release should be framed as:

- an iOS portability and validation hardening pass
- a package-test cleanup that keeps macOS worker e2e coverage out of the iOS
  simulator smoke lane
- a small runtime portability fix for process-rusage inspection on non-macOS
  platforms

Included work on the current branch:

- add an iOS Simulator compile-and-smoke CI lane to `.github/workflows/swift.yml`
- document the iOS lane in maintainer notes, README, and CONTRIBUTING guidance
- fence `Tests/SpeakSwiftlyTests/E2E/` as macOS-only so the shared test target
  compiles honestly for iOS
- move the long chunk-planner fixture in `ModelClientsTests` out of the macOS
  e2e harness
- make `WorkerDependencies.currentRuntimeMemorySnapshot()` treat
  `proc_pid_rusage` as macOS-only and return `nil` process-rusage fields on iOS

Not included:

- a new public API surface
- a new app-hosted iOS end-to-end harness
- a change to the macOS-first worker-runtime ownership model

## SemVer Framing

- this should ship as a patch release
- the work widens supported validation and compile coverage, but it does not
  add a new consumer-facing feature flag or break an existing public contract

## Validation Performed

Shared guidance and formatting gate:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

macOS Xcode-backed package validation:

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/xcode/derived-data/release-v3-0-9-macos \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/release-v3-0-9-macos/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests'
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/release-v3-0-9-macos/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/ModelClientsTests'
```

iOS Simulator compile-and-smoke validation:

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=iOS Simulator,id=4343A7EF-1074-44EB-8FD6-7972330DD08E' \
  -derivedDataPath .local/xcode/derived-data/ios-smoke \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/ios-smoke/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_iphonesimulator26.4-arm64.xctestrun \
  -destination 'platform=iOS Simulator,id=4343A7EF-1074-44EB-8FD6-7972330DD08E' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests' \
  -only-testing:'SpeakSwiftlyTests/SupportResourcesTests' \
  -only-testing:'SpeakSwiftlyTests/ProfileStoreTests'
```

## Release Checklist

- keep the release notes focused on portability and validation hardening, not as
  a new app-facing feature release
- call out that the iOS lane is still a library-first simulator smoke lane, not
  a full app-hosted or real-device end-to-end harness
- mention that macOS worker e2e coverage remains macOS-only by design
