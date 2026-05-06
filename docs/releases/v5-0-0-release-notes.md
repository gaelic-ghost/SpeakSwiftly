# v5.0.0 Release Notes

## What Changed

- Raised the `TextForSpeech` dependency floor to `0.19.0`.
- Simplified the typed Swift generation surface around `sourceFormat` and
  `requestContext`.
- Removed the public `SpeakSwiftly.InputTextContext` type.
- Routed live playback, retained audio generation, generated-file manifests,
  generation jobs, generated batches, request observation, and JSONL emission
  through the simplified source/request context model.
- Kept `source_format` as the JSONL whole-source selector and
  `request_context` as the JSONL metadata and path-context container.
- Rejected removed JSONL generation-context keys with explicit diagnostics
  instead of silently ignoring stale caller payloads.
- Merged batch-item top-level `cwd` and `repo_root` fields into nested
  `request_context` the same way single generation requests do.
- Updated release E2E live-service helpers to prefer the current
  `SpeakSwiftlyServer` `/models/unload` and `/models/reload` routes while
  retaining fallback support for the older `/runtime/models/...` routes.
- Standardized typed Swift observation around `Event`, `State`, `Update`, and
  `Snapshot` families for Request, Synthesis, Generate, Playback, and Runtime.
- Kept JSONL `worker_status` and `get_runtime_overview` compatibility while
  making native Swift runtime, generation, and playback snapshots direct reads.

## Breaking Changes

- Swift callers must replace `inputTextContext:` with `sourceFormat:` and
  `requestContext:`.
- `SpeakSwiftly.InputTextContext` is removed.
- `runtime.player` and `SpeakSwiftly.Player` are removed; use
  `runtime.playback` and `SpeakSwiftly.Playback`.
- Per-request `GenerationEvent` / `GenerationEventUpdate` are removed; use
  `SynthesisEvent` / `SynthesisUpdate`.
- `runtime.status()`, `runtime.overview()`, `Player.list()`, `Player.state()`,
  and `runtime.statusEvents()` are removed from the typed Swift surface; use
  `runtime.snapshot()`, `runtime.generate.snapshot()`,
  `runtime.playback.snapshot()`, and `updates()` streams.
- JSONL generation callers must stop sending `input_text_context`,
  `text_format`, and `nested_source_format`.
- Mixed prose, Markdown, HTML, logs, CLI output, and agent text should omit
  source hints and let `TextForSpeech` detect structure internally.

## Migration Notes

- Use `sourceFormat: .swift` or JSONL `source_format: "swift_source"` only when
  the entire input is source code.
- Use `requestContext` or JSONL `request_context` for app, agent, project,
  topic, `cwd`, and `repo_root` metadata.
- Keep using `voice_profile` and `text_profile` on new JSONL callers.
  Compatibility aliases `profile_name` and `text_profile_id` remain accepted.
- Native Swift callers should use `handle.synthesisUpdates` or
  `runtime.synthesisUpdates(for:)` for request-scoped model-side telemetry.
- Native Swift callers should use `runtime.updates()`, `runtime.snapshot()`,
  `runtime.generate.updates()`, `runtime.generate.snapshot()`,
  `runtime.playback.updates()`, and `runtime.playback.snapshot()` for singleton
  observation.

## Verification

- `swift build`
- `swift test`
- `bash scripts/repo-maintenance/validate-all.sh`
- `sh scripts/repo-maintenance/run-e2e-full.sh`
