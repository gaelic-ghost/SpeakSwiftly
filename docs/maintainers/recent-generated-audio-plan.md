# Recent Generated Audio Plan

## Summary

Add first-class recent generated audio support to `SpeakSwiftly` so live speech can be replayed after it has already played, while new generated speech continues queueing behind operator-requested replays.

This is a runtime playback-history feature, not a playback-driver rewind hack. Each speech generation should produce one canonical generated-audio chunk stream, and the runtime may attach multiple output consumers to that stream:

- live local playback
- short-lived in-memory chunk capture
- recent file artifact writing
- explicit retained file generation

The preferred direction is a hybrid cache: keep a bounded in-memory replay buffer for fast near-term rewind and also write completed recent generations as file artifacts for full replay, queue insertion, and engine-reset resilience.

Current implementation status: memory-backed capture, typed Swift replay APIs,
JSONL/tool controls, bounded retention configuration, and docs have landed.
Artifact-backed replay remains future work.

## Goals

- Retain the last 3 to 5 live speech generations by default.
- Allow operators or API callers to replay one recent generation or all recent generations.
- Queue replayed recent audio ahead of normal generated speech that has not started playing yet.
- Keep active generation and new generation queueing intact while replay is requested.
- Reuse the canonical `GeneratedAudioChunk` stream and the file-audio output module instead of inventing a second audio representation.
- Keep file generation and recent-audio retention shaped similarly, with different retention policies.

## Non-Goals For The First Slice

- Do not implement true seek/rewind inside an active `AVAudioEngine` playback item yet.
- Do not require every replay to interrupt current playback.
- Do not keep unlimited PCM in memory.
- Do not make recent audio user-retained by default; recent items are evictable cache entries.
- Do not change Qwen generation behavior or CoreML/Metal Flash Attention work.

## Proposed Model

Add recent-audio models to the public/runtime surface:

- `RecentGeneratedAudioItem`
- `RecentGeneratedAudioSnapshot`
- `RecentGeneratedAudioRetentionPolicy`
- `RecentGeneratedAudioReplayMode`

Important item fields:

- recent item ID
- request ID
- text preview
- voice profile name
- creation and completion timestamps
- sample rate and channel count
- duration when known
- artifact ID or file URL when available
- buffer state such as `active`, `complete`, `evicted`, or `failed`

## Proposed Runtime Flow

For live speech:

1. Qwen generation emits canonical `GeneratedAudioChunk` values.
2. Playback consumes chunks live.
3. A recent in-memory capture records a bounded amount of chunks.
4. A file writer records the completed generation as a recent artifact.
5. On final chunk, the runtime registers the completed item in recent history.
6. Eviction removes old memory buffers and recent-cache artifacts according to limit and age.

For generated files:

1. The same file writer machinery writes an explicit retained artifact.
2. The generated file job does not need live playback.
3. The artifact retention policy is explicit/user-retained rather than recent-cache eviction.

## Replay Policy

Replay should initially mean queueing a recent item into playback, not seeking the live playback engine backward.

Default queue policy:

- current active playback continues
- manual replay queue comes next
- normal generated playback waits behind requested replay

This gives the practical behavior Gale wants: if they miss audio after stepping away, they can pull back one or more recent generations without losing queued new speech.

## Stream Fanout

`AsyncAlgorithms.share()` may be useful, but the first implementation should be careful about audio backpressure. Live playback should not rebuffer because a recent artifact writer is slow.

Preferred first durable building block:

- a small generated-audio fanout or capture helper with bounded buffering per consumer
- playback branch has priority
- capture/artifact branch can fail independently and mark the recent item failed without failing live playback

## Public API Sketch

Place user-facing recent controls on `Playback`, because the operator action is playback-history control:

```swift
let recent = await runtime.playback.recentGeneratedAudio()

let replay = await runtime.playback.replayRecent(id: recent.items[0].id)
try await replay.completion()

let replayHandles = await runtime.playback.replayRecentAll()

await runtime.playback.clearRecentGeneratedAudio()
```

Configuration sketch:

```swift
let configuration = SpeakSwiftly.Configuration(
    recentGeneratedAudioLimit: 5
)
```

## Implementation Slices

1. [x] Add recent generated audio models and a bounded in-memory store.
2. [x] Add unit tests for store insert, completion, failure, eviction, and snapshot ordering.
3. [ ] Add generated-audio stream capture/fanout helpers with tests for slow capture consumers.
4. [x] Wire live speech generation into recent capture without changing playback behavior.
5. [ ] Reuse file-audio output for recent artifact writing and cleanup.
6. [x] Add playback queue support for replaying recent items from memory.
7. [x] Expose public API and JSONL/tool contract controls for list/replay/replay all/clear.
8. [x] Add docs and unit/integration smoke coverage after the unit/integration surface is stable.
9. [ ] Add artifact-backed replay once generated-file playback and file-handoff ergonomics are reviewed.

## Test Plan

- Store unit tests for active, complete, failed, evicted, and cleared items.
- Fanout tests proving playback consumption is not blocked by a slow capture branch.
- Runtime tests proving live speech records recent history while preserving existing playback queue behavior.
- Replay queue tests proving manual replay enters ahead of normal queued generated speech.
- File-output tests proving recent artifacts are written and evicted separately from explicit retained artifacts.
- JSONL/tool contract tests for list/replay/replay all/clear controls.
- E2E smoke only after the structural path is stable.
