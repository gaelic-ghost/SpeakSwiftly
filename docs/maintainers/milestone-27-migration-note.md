# Milestone 27 Migration Note

Milestone 27 is a pre-v1 source-breaking cleanup of the typed Swift API. It
keeps the JSONL worker operation names and response payloads stable, but
library callers should update their Swift call sites to use the clearer typed
surface.

## Typed Swift Changes

- Queue controls now keep ownership visible at the use site. Cross-queue
  controls live on `Runtime` through `clearQueue(_:)` and
  `cancel(_:requestID:)`; `Jobs` and `Player` keep only same-queue convenience
  methods. The old `Player.clearQueue(_:)` and `Player.cancel(_:requestID:)`
  cross-queue entry points are removed.
- Text-profile operations on `SpeakSwiftly.Normalizer` now return
  `SpeakSwiftly.TextProfileSummary`, `SpeakSwiftly.TextProfileDetails`, and
  `SpeakSwiftly.TextProfileStyleOption`. `TextForSpeech.Replacement`,
  `InputContext`, and `SourceFormat` remain where callers author real
  TextForSpeech inputs.
- Request observation now exposes typed `SpeakSwiftly.RequestKind` values on
  request handles, snapshots, active requests, and queued requests. JSONL `op`
  strings remain the transport representation.
- Terminal Swift request events now use `SpeakSwiftly.RequestCompletion` instead
  of requiring callers to inspect the broad JSONL `SpeakSwiftly.Success`
  envelope.
- Retained batch work is inspected through canonical `SpeakSwiftly.GenerationJob`
  snapshots from `runtime.jobs.job(id:)` and `runtime.jobs.list()`. `GeneratedBatch`
  remains available only as a JSONL compatibility projection for existing
  worker responses.
- Designed voice creation now uses `voiceDescription:` at the call site, and
  trusted package-owned defaults use `builtInDesign:` instead of `systemDesign:`.

## Compatibility Notes

JSONL operation names, `profile_id` compatibility, and JSONL response payload
keys are intentionally unchanged. Downstream host adoption, including
`SpeakSwiftlyServer`, is handled separately before release so this package does
not regain compatibility shims during the pre-v1 cleanup.
