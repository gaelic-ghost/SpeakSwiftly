# v3.1.0 Release Notes

## What changed

- added `chatterbox_turbo` as a first-class resident speech backend on the
  typed Swift API and the JSONL worker surface
- routed Chatterbox generation through stored profile reference audio so
  existing profile data can drive clone-conditioned silent playback and
  generated file output
- documented the Chatterbox backend as the resident 8-bit English-only path
- added a serialized Chatterbox end-to-end suite covering:
  - voice design to silent speech to generated file output
  - clone creation with a provided transcript
  - clone creation with inferred transcript
- added a roadmap item to generalize clone auto-transcription across every
  cloning-capable backend instead of leaving it as a Qwen-shaped detail

## Breaking changes

- none

## Migration or upgrade notes

- `chatterbox_turbo` is currently English-only
- Chatterbox uses stored profile reference audio directly; it does not yet
  persist a backend-native prepared conditioning artifact the way Qwen can
- if plain `swift build` or `swift test` hits the vendored `EnglishG2P.swift`
  parser failure, switch to the documented repo-root Xcode-backed package lane
  instead of retrying the same SwiftPM command

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
  -derivedDataPath .local/xcode/derived-data/release-v3-1-0-prep \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
```

```bash
xcodebuild test-without-building \
  -xctestrun .local/xcode/derived-data/release-v3-1-0-prep/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.e2e.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/ChatterboxWorkflowSuite'
```
