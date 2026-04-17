# v3.1.0 Release Prep

This note captures the intended scope and validation story for the `v3.1.0`
minor release branch.

## Intended Scope

The release should be framed as a new resident backend and coverage expansion,
not as a generic runtime hardening patch.

Included work on `release/chatterbox-turbo-e2e`:

- add the `chatterbox_turbo` resident backend to the typed Swift API, JSONL
  worker surface, and resident model loader
- route Chatterbox generation through stored profile reference audio so existing
  profiles can drive clone-conditioned playback and file generation
- document Chatterbox backend behavior in package-facing docs
- add a serialized Chatterbox end-to-end workflow suite covering:
  - voice design then silent speech then generated file output
  - clone creation with a provided transcript
  - clone creation with inferred transcript
- record the roadmap follow-up for backend-agnostic clone auto-transcription

Not included:

- a backend-specific persisted Chatterbox conditioning artifact format
- non-English Chatterbox routing or multilingual guarantees
- a broader redesign of the clone storage model beyond the roadmap ticket
- any claim that the noisy Contacts or AddressBook host logs emitted by the
  xctest process are a SpeakSwiftly runtime failure

## Validation Performed

Known lane rule:

- plain SwiftPM remains the fast default
- if the vendored `mlx-audio-swift` parser failure in `EnglishG2P.swift`
  appears, switch to the documented Xcode-backed lane instead of retrying the
  same SwiftPM command
- package-release validation should use that same Xcode-backed lane until the
  vendored parser snag is gone

Validation run for this branch:

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
  -derivedDataPath .local/xcode/derived-data/release-v3-1-0-prep \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/release-v3-1-0-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.e2e.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/ChatterboxWorkflowSuite'
```

Observed note:

- the xctest host emits repeated sandboxed Contacts or AddressBook Core Data
  warnings during the Chatterbox E2E lane, but the worker-backed suite still
  completes successfully and the test bundle exits cleanly

Proposed release notes live in `docs/maintainers/v3-1-0-release-notes.md`.

## Pre-PR Checklist

- keep the PR framed as a minor release because it adds a new backend surface
- call out that Chatterbox currently uses stored reference audio rather than a
  backend-native persisted conditioning artifact
- mention that clone auto-transcription for all cloning-capable backends is
  still tracked as roadmap follow-up work
- keep the validation notes explicit about the Xcode-backed package lane
