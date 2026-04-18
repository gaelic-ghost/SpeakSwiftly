# SpeakSwiftly Validation Lanes

This note exists so maintainers stop rediscovering the same validation snags.

## What To Use First

For ordinary package work, start with the fast SwiftPM lane:

```bash
swift build
swift test
```

That is still the right default for quick compile and unit-coverage feedback.

## Known SwiftPM Snag

The current vendored `mlx-audio-swift` checkout can fail under plain SwiftPM
with parser errors in `EnglishG2P.swift`. When that happens, treat it as a
known lane limitation, not as a fresh repository mystery.

Typical symptom:

```text
.../EnglishG2P.swift: error: new Swift parser generated errors for code that C++ parser accepted
```

When that happens:

1. Stop retrying the same `swift build` or `swift test` command.
2. Switch to the Xcode-backed package workspace lane.
3. Keep validation targeted so the signal stays readable.

## Xcode-Backed Fallback Lane

Use this for:

- release hardening
- MLX-backed real-model coverage
- Marvis overlap investigation
- any validation pass blocked by the SwiftPM parser failure

Build once:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/xcode/derived-data/validation \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

Then run one targeted test lane at a time with `test-without-building`.

Example targeted package test rerun:

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/xcode/derived-data/validation/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests'
```

For GitHub Actions, keep the manifest sanity check as:

```bash
swift package dump-package
```

Then use the same Xcode-backed package lane for build-and-test coverage instead
of plain `swift build` / `swift test` until the vendored parser snag is gone.
The current macOS CI target set is:

- `SpeakSwiftlyTests/WorkerRuntimePlaybackTests`
- `SpeakSwiftlyTests/LibrarySurfaceTests`
- `SpeakSwiftlyTests/ModelClientsTests`

## iOS Compile-And-Smoke Lane

The iOS lane is intentionally smaller than the macOS package lane. Its job is
to prove that:

- the package resolves for iOS
- the shared library and playback-environment code compile for iOS Simulator
- a small library-first smoke slice still runs under Simulator

Build once:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -derivedDataPath .local/xcode/derived-data/ios-smoke \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

Then run the current smoke slice:

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/xcode/derived-data/ios-smoke/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests' \
  -only-testing:'SpeakSwiftlyTests/SupportResourcesTests' \
  -only-testing:'SpeakSwiftlyTests/ProfileStoreTests'
```

Keep this lane library-first. The worker-driven e2e harness is macOS-only and
should stay out of the iOS simulator smoke path unless we deliberately create an
app-hosted iOS e2e story later.

## E2E and Real-Model Notes

Plain `swift test` remains the default opt-in path for many e2e commands in
this repository, but the Xcode-backed lane is the current reliable fallback
whenever the SwiftPM parser issue blocks progress.

For Marvis overlap and trace work, prefer the dedicated runbook:

- [marvis-overlap-profiling-runbook-2026-04-16.md](marvis-overlap-profiling-runbook-2026-04-16.md)

## Practical Rules

- Never run multiple heavy validation commands at the same time.
- Never run multiple SwiftPM or Xcode build or test processes concurrently.
- Prefer one clean targeted rerun over broad shotgun retries.
- If the failure is clearly the vendored parser snag, document that lane choice in your notes instead of treating it as an unexplained flake.
