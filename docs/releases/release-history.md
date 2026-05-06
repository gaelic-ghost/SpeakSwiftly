# Release History Notes

Git tags and GitHub releases are the authoritative release history. This file
keeps durable context from older local release-prep and release-note snapshots
without preserving one stale document per patch release.

## v3.0.9

- Added an iOS Simulator compile-and-smoke validation lane.
- Kept worker-driven E2E coverage macOS-only.
- Fixed runtime memory snapshot portability around process-rusage inspection.
- Documented the iOS validation lane in maintainer and contributor guidance.

## v3.2.2

- Removed SpeakSwiftly's hardcoded Qwen English language override and relied on
  upstream language auto-detection.
- Applied the same Qwen behavior to prepared conditioning, profile creation,
  and direct testing paths.
- Raised the standard Qwen resident streaming cadence to `0.32`.
- Bumped `TextForSpeech` from `0.18.2` to `0.18.3` while keeping the
  `mlx-audio-swift` fork pin at `0.7.0`.

## v3.2.3

- Aligned SpeakSwiftly's Qwen generation token budget with upstream defaults.
- Removed local word-count-derived Qwen max-token caps from resident generation
  and profile generation.
- Updated resident-generation parameter coverage for the upstream-aligned
  default.

## v3.2.5

- Bounded live Qwen generation to two blank-line-separated paragraphs per model
  pass.
- Added a smaller sentence-group fallback for oversized live chunks.
- Kept retained generated-audio file rendering on the original single-pass Qwen
  path.
- Added regression coverage for the live-only scope.

## v3.2.6

- Refreshed `TextForSpeech` to `0.18.6`.
- Added structured logging for the exact live Qwen chunk text handed into
  generation.
- Added an explicit finished-chunk playback boundary marker.
- Changed playback so a finished Qwen chunk drains already queued audio before
  the next chunk starts.

## v4.0.1

- Changed `SpeakSwiftly.RequestContext` to a public typealias for
  `TextForSpeech.RequestContext`.
- Added library-surface coverage for the shared request-context model.
- Refreshed generated-artifact E2E assertions to use the current
  `voice_profile` field.

## v4.0.5

- Hardened `SpeakSwiftlyTesting volume-probe` with explicit analyzed duration,
  sample-count, and span reporting.
- Renamed the endpoint drop metric to `endpoint_rms_delta_pct`.
- Added versioned JSON artifacts for `volume-probe` and `compare-volume`.
- Made `compare-volume` reject mismatched sample rates or counts unless an
  explicit matched-duration mode is requested.
- Moved reusable probe math into `SpeakSwiftlyTestingSupport`.

## v5.0.0-rc.1

- Raised the `TextForSpeech` dependency floor to `0.19.0`.
- Simplified the typed Swift generation surface around `sourceFormat` and
  `requestContext`.
- Removed `SpeakSwiftly.InputTextContext`.
- Rejected removed JSONL generation-context keys with explicit diagnostics.
- Kept downstream `SpeakSwiftlyServer` adoption as separate release-hardening
  work instead of carrying compatibility shims in the package.
