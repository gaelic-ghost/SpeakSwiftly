# Release Candidate Notes

Date: 2026-04-17

These are the current branch-level release notes before the final tag is chosen.
Rewrite the heading and any tag-specific wording when the real release version
is selected.

## What changed

- added `chatterbox_turbo` as a first-class resident speech backend on the
  typed Swift API and the JSONL worker surface
- routed Chatterbox generation through stored profile reference audio so
  existing profile data can drive clone-conditioned playback and generated file
  output
- added runtime-owned chunked live generation for Chatterbox so normalized text
  is segmented up front, synthesized sequentially, and fed into playback chunk
  by chunk instead of waiting for one full-request waveform
- documented Chatterbox as the resident 8-bit English-only path with silent
  default e2e coverage and an audible opt-in lane
- cleaned up stale maintainer planning docs and folded their durable outcomes
  into the roadmap history and current package docs

## Breaking changes

- none

## Migration Or Upgrade Notes

- `chatterbox_turbo` is currently English-only
- Chatterbox uses stored profile reference audio directly; it does not yet
  persist a backend-native prepared conditioning artifact the way Qwen can
- Chatterbox live playback is currently achieved through runtime-owned text
  chunking on top of a non-streaming backend path, not through backend-native
  incremental audio generation
- clone auto-transcription across every cloning-capable backend remains tracked
  as roadmap follow-up work
- if plain `swift build` or `swift test` hits the vendored `EnglishG2P.swift`
  parser failure, switch to the documented repo-root Xcode-backed package lane
  instead of retrying the same SwiftPM command

## Verification Performed

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
