# v11.0.0-alpha.1 Draft Release Notes

## What Changed

- Removed Marvis and Chatterbox from the normal backend configuration surface.
- Kept Qwen3 as the only supported speech generation family.
- Split generated-audio output primitives into separate package modules:
  `SpeakSwiftlyCore`, `SpeakSwiftlyPlayback`,
  `SpeakSwiftlyHTTPAudioOutput`, and `SpeakSwiftlyNetworkAudioOutput`.
- Added canonical generated-audio chunks with request ID, sequence number,
  sample rate, channel count, sample format, samples, and final-chunk marker.
- Added `generate.speech(... output:)` for request-scoped live output routing.
- Added HTTP-friendly raw PCM frame payloads plus metadata headers for server
  response streaming.
- Added Network.framework audio frame encoding plus Bonjour audio-receiver
  discovery primitives for LAN receiver selection.

## Breaking Changes

- Marvis and Chatterbox backend names are no longer supported.
- Removed backend values in persisted configuration or worker requests fail as
  invalid input instead of falling back to another backend.
- Live speech output is now modeled as generation plus an output destination.
  Local playback is still the default destination.
- The new output-module shape is intentionally not a compatibility shim for the
  previous backend-switching model.

## Migration Notes

- Hosts should treat Qwen3 as the only supported generation family.
- Use `generate.speech(text:output:)` when a live request should default to
  local playback or explicitly choose another destination.
- Use `generate.speech(text:output:)` with an explicit nonlocal destination
  only from a host that is ready to own HTTP response or LAN transport routing.
- HTTP hosts should serve `HTTPGeneratedAudioFrame.payload` as raw PCM bytes and
  use `HTTPGeneratedAudioFrame.metadataHeaders` for per-frame metadata.
- LAN hosts can use `NetworkAudioDestinationBrowser` to discover advertised
  audio receivers and convert the selected endpoint into an output destination.
- Real `SpeakSwiftlyServer` adoption and two-Mac LAN validation are follow-up
  integration work after this package prerelease.

## Verification

- `swift build`
- `swift test --filter GeneratedAudioOutputTests`
- `swift test --filter NetworkAudioOutputTests`
- `swift test --filter LibrarySurfaceTests`
- `swift test`
- commit-hook repo-maintenance validation, including SwiftFormat, MLX resource
  checks, and SwiftLint

## Follow-Up Before Final v11.0.0

- Wire real HTTP response streaming and LAN transport send/receive behavior.
- Add `generate.audioStream(...)` after the host boundary can return a
  successful chunk stream instead of a failed request handle.
- Validate `SpeakSwiftlyServer` adoption against the prerelease package.
- Run opt-in live worker E2E and real LAN receiver tests when the transport
  integration is ready.
