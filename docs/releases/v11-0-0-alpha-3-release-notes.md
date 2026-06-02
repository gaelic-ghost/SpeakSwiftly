# v11.0.0-alpha.3 Draft Release Notes

## What Changed

- Added `generate.audioStream(...)` to the typed runtime surface.
- Added `GeneratedAudioStream`, which carries the request handle plus canonical
  generated-audio chunk stream for host-owned output boundaries.
- Routed generated-audio stream jobs through Qwen resident generation without
  entering local playback.
- Updated Runtime Quick Start docs and the roadmap to treat
  `generate.audioStream(...)` as the supported lower-level primitive for HTTP,
  LAN, benchmark, custom playback, and other host-owned output paths.

## Breaking Changes

- This remains part of the v11 major cleanup line. Removed backend and
  request-context compatibility shims from earlier v11 alpha releases remain
  removed.

## Migration Notes

- Use `generate.speech(...)` for high-level speech requests that should enter
  local playback or another server-owned speech workflow.
- Use `generate.audioStream(...)` when the caller owns the output boundary and
  needs canonical `GeneratedAudioChunk` values to frame for HTTP, send over LAN,
  encode, benchmark, or feed into a custom player.
- `SpeakSwiftlyServer` can now adopt this release for remote-generation routing
  without depending on an unreleased package branch.

## Verification

- `swift build`
- `swift test --filter WorkerRuntimeGenerationTests`
- `swift test --filter LibrarySurfaceTests`
- `swift test`
- `bash scripts/repo-maintenance/release.sh --mode standard --version v11.0.0-alpha.3 --remote-ci-mode defer`
- `bash scripts/repo-maintenance/release.sh --mode standard --version v11.0.0-alpha.3 --skip-version-bump --remote-ci-mode defer`

## Follow-Up Before Final v11.0.0

- Update `SpeakSwiftlyServer` to consume this prerelease for local and remote
  generated-audio stream routing.
- Add server-side generation-location selection once the server dependency is
  updated to this tag.
