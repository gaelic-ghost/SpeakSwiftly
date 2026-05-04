# v4.1.0 Release Notes

This historical release note was superseded by the `TextForSpeech 0.19.0`
surface simplification. Current callers use `sourceFormat` for whole-source
generation and `requestContext` for request metadata and path context.

## What changed

- refreshed the `TextForSpeech` dependency to `0.18.9`
- kept `SpeakSwiftly.RequestContext` on the shared `TextForSpeech.RequestContext`
  model so request-origin metadata comes from TextForSpeech
- centralized generation normalization through
  `SpeakSwiftly.Normalizer.speechText(...)` for live playback and retained file
  output
- preserved selected text profiles, active built-in style, source format,
  request context, and TextForSpeech summarization-provider selection through the shared
  normalization path
- kept JSONL text-profile payloads on the compatible `profile_id` field while
  mapping from the current `TextForSpeech.Runtime.Profiles.Details.id` source
  model
- queued live playback state before generation admission so async
  normalization cannot race generation ahead of playback registration
- aligned `runtime.player.cancelRequest(_:)` with its documented broad
  request-id behavior while keeping queue-specific cancellation available

## Breaking changes

- Swift callers should use `sourceFormat` only for whole-source generation and
  `requestContext` for request metadata and path context
- JSONL request and response compatibility is preserved

## Migration or upgrade notes

- continue using `request_context` in JSONL requests; use `source_format` only
  for whole-source generation
- use `runtime.cancel(.generation, requestID:)` or
  `runtime.cancel(.playback, requestID:)` when a cancellation must stay scoped
  to one queue
- use `runtime.player.cancelRequest(_:)` when the operator intent is to cancel
  the named request wherever it currently lives

## Verification to complete before release

```bash
swift build
```

```bash
swift test
```

```bash
swift test --enable-code-coverage
```

```bash
git diff --check
```

```bash
sh scripts/repo-maintenance/validate-all.sh
```

```bash
sh scripts/repo-maintenance/run-e2e-full.sh
```
