# v3.0.6 Release Prep

Date: 2026-04-17

This note captures the intended scope and validation story for the `v3.0.6`
patch release.

## Intended Scope

The release should be framed as:

- the Chatterbox backend landing follow-up
- the runtime-owned live-playback correction that makes non-streaming
  Chatterbox synthesis behave like real live playback through text chunking
- the docs and roadmap cleanup that brings package and maintainer surfaces back
  in sync with the actual implementation

Included work on the merged branch:

- add `chatterbox_turbo` as a first-class resident backend on the typed Swift
  API, JSONL worker surface, and resident model loader
- route Chatterbox generation through stored profile reference audio so
  existing profiles can drive clone-conditioned playback and file generation
- add runtime-owned chunked live generation for Chatterbox so normalized text
  is segmented up front and synthesized sequentially into the live playback
  buffer
- add serialized Chatterbox end-to-end coverage for:
  - voice design then live speech then generated file output
  - clone creation with a provided transcript
  - clone creation with inferred transcript
- keep the Chatterbox suite silent by default and allow audible reruns through
  `SPEAKSWIFTLY_AUDIBLE_E2E=1`
- record follow-up work for backend-agnostic clone auto-transcription and
  broader backend-aware profile materialization in the roadmap
- clean out stale maintainer planning notes whose durable outcomes already live
  in current docs, tests, and roadmap history

Not included:

- a backend-specific persisted Chatterbox conditioning artifact format
- multilingual guarantees for Chatterbox
- a general backend-agnostic profile-materialization redesign beyond the
  roadmap follow-up
- a claim that Chatterbox itself is a truly incremental streaming backend

## Validation Performed

Repo gate:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

Green Xcode-backed package and e2e lane:

```bash
xcodebuild build-for-testing \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/xcode/derived-data/validation \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/validation/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.chatterbox-audible.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/ChatterboxWorkflowSuite'
```

Observed result:

- `ChatterboxWorkflowSuite` passed with all three tests green
- the live path now emits multiple synthesized chunks instead of one
- first audible startup lands after the first generated chunk instead of after
  full-request synthesis

Known note:

- the xctest host still emits noisy sandboxed Contacts or AddressBook Core Data
  warnings during this lane, but the worker-backed suite still completes
  cleanly and those host logs are not treated as SpeakSwiftly runtime failure

Post-merge CI on `main`:

- `Validate Repo Maintenance` passed
- `Swift` passed with the Xcode-backed package lane and targeted package tests

## Release Checklist

- keep the GitHub release notes focused on the Chatterbox backend plus the
  chunked-live follow-up
- mention that Chatterbox is still English-only
- mention that Chatterbox live playback is runtime-chunked rather than
  backend-native streaming
- mention that clone auto-transcription for all cloning-capable backends is
  still tracked as roadmap follow-up work
- keep the validation notes explicit about the Xcode-backed lane and the noisy
  but non-failing xctest host logs
