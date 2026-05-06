# Typed Observation API

This note records the agreed breaking public API cleanup for SpeakSwiftly's typed Swift observation surfaces and the implemented shape that landed from that plan.

## Status

Implemented in the typed Swift package surface. Downstream `SpeakSwiftlyServer`
adoption remains separate release-hardening work before `v1.0.0`.

## Decision

The package standardizes observable state around one vocabulary:

- `Event`: something meaningful that just happened.
- `State`: the current semantic condition of an observable surface.
- `Update`: a sequenced, timestamped state publication.
- `Snapshot`: a point-in-time read of the full surface.

`RequestEvent`, `RequestState`, `RequestUpdate`, and `RequestSnapshot` are the model copied across request-scoped synthesis, the generation queue, playback, and runtime resident-model state.

This is a breaking API cleanup. The package does not provide compatibility shims for old typed Swift names.

## Public Families

### Request

Request observation remains the per-request anchor:

- `RequestEvent`
- `RequestState`
- `RequestUpdate`
- `RequestSnapshot`
- `RequestHandle`

Keep this model as the source of truth for individual submitted operations. A request is the only surface that naturally has many concurrent instances, so request updates and snapshots keep request identity.

### Synthesis

The old per-request `GenerationEvent` and `GenerationEventUpdate` names were too broad because `Generate` is now the global generation-queue concern. The per-request model uses synthesis-specific names:

- `SynthesisEvent`
- `SynthesisUpdate`

These events describe model-side production for one request: token ids, generation metrics, and audio chunk sample counts. They do not describe the global generation queue.

Request-handle shape:

```swift
public struct RequestHandle: Sendable {
    public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>
    public let synthesisUpdates: AsyncThrowingStream<SynthesisUpdate, any Swift.Error>
}
```

Runtime lookup:

```swift
func synthesisUpdates(
    for requestID: String
) -> AsyncThrowingStream<SynthesisUpdate, any Swift.Error>
```

### Generate

`runtime.generate` owns the global generation-queue observation surface. It describes whether generation is idle, running, or blocked and exposes the active and queued generation requests.

Family:

- `GenerateEvent`
- `GenerateState`
- `GenerateUpdate`
- `GenerateSnapshot`

Surface:

```swift
extension SpeakSwiftly.Generate {
    func updates() -> AsyncStream<GenerateUpdate>
    func snapshot() async -> GenerateSnapshot
}
```

`GenerateSnapshot` replaces the typed Swift role of request-handle queue
inspection for the generation queue. Keep the JSONL `list_generation_queue`
operation stable, but do not keep a parallel public Swift queue-inspection verb
when `runtime.generate.snapshot()` can answer the same caller question directly.

`GenerateState` stays semantic and compact. The rich queue details belong in `GenerateSnapshot`.

Shape:

```swift
enum GenerateState: Sendable, Equatable {
    case idle
    case running
    case blocked(GenerateBlockReason)
}

struct GenerateUpdate: Sendable, Equatable {
    let sequence: Int
    let date: Date
    let state: GenerateState
}

struct GenerateSnapshot: Sendable, Equatable {
    let sequence: Int
    let capturedAt: Date
    let state: GenerateState
    let activeRequests: [ActiveRequest]
    let queuedRequests: [QueuedRequest]
}
```

`GenerateBlockReason` is the Swift-facing equivalent of generation park reasons such as resident-model warmup, resident-model unload, active generation, playback stability, and Marvis lane serialization.

### Playback

The public handle is `runtime.playback`. The public noun matches the domain and the model family.

Family:

- `PlaybackEvent`
- `PlaybackState`
- `PlaybackUpdate`
- `PlaybackSnapshot`

Surface:

```swift
extension SpeakSwiftly.Runtime {
    nonisolated var playback: SpeakSwiftly.Playback { get }
}

extension SpeakSwiftly.Playback {
    func updates() -> AsyncStream<PlaybackUpdate>
    func snapshot() async -> PlaybackSnapshot
    func pause() async -> RequestHandle
    func resume() async -> RequestHandle
    func clearQueue() async -> RequestHandle
    func cancelRequest(_ requestID: String) async -> RequestHandle
}
```

`PlaybackSnapshot` replaces the typed Swift role of `Player.list()` and
`Player.state()`. Keep JSONL playback queue and playback-state operations stable
for the worker contract, but make the native Swift inspection path direct and
snapshot-shaped.

`PlaybackState` remains small enough for UI and agent consumers to branch on directly. Snapshot carries richer telemetry.

Shape:

```swift
enum PlaybackState: Sendable, Equatable {
    case idle
    case playing
    case paused
    case interrupted
    case recovering
}

struct PlaybackUpdate: Sendable, Equatable {
    let sequence: Int
    let date: Date
    let state: PlaybackState
}

struct PlaybackSnapshot: Sendable, Equatable {
    let sequence: Int
    let capturedAt: Date
    let state: PlaybackState
    let activeRequest: ActiveRequest?
    let queuedRequests: [QueuedRequest]
    let isRebuffering: Bool
    let stableBufferedAudioMS: Int?
    let stableBufferTargetMS: Int?
}
```

Raw playback-driver events such as trace samples, buffer-shape summaries, route-change internals, and rebuffer warnings stay internal diagnostics unless a concrete Swift consumer needs them. The public update stream publishes domain states, not driver chatter.

### Runtime

Replace the public `StatusEvent` and `RuntimeOverview` vocabulary with runtime observation names.

Family:

- `RuntimeEvent`
- `RuntimeState`
- `RuntimeUpdate`
- `RuntimeSnapshot`

Surface:

```swift
extension SpeakSwiftly.Runtime {
    func updates() -> AsyncStream<RuntimeUpdate>
    func snapshot() async -> RuntimeSnapshot
}
```

`RuntimeSnapshot` replaces the typed Swift role of `runtime.status()` and
`runtime.overview()`. Keep JSONL `get_status`, `worker_status`, and
`get_runtime_overview` stable for process-boundary consumers, but make native
Swift runtime inspection direct instead of returning a request handle for a
snapshot read.

Shape:

```swift
enum RuntimeState: Sendable, Equatable {
    case warmingResidentModel
    case residentModelReady
    case residentModelsUnloaded
    case residentModelFailed
}

struct RuntimeUpdate: Sendable, Equatable {
    let sequence: Int
    let date: Date
    let state: RuntimeState
}

struct RuntimeSnapshot: Sendable, Equatable {
    let sequence: Int
    let capturedAt: Date
    let state: RuntimeState
    let speechBackend: SpeechBackend
    let residentState: ResidentModelState
    let defaultVoiceProfile: String
    let storage: RuntimeStorageSnapshot
}
```

`RuntimeSnapshot` replaces the public role of `RuntimeOverview`. Queue and playback details are available through `runtime.generate.snapshot()` and `runtime.playback.snapshot()` instead of making the runtime snapshot a mixed owner for every domain.

## Singleton Observation Broker

The runtime uses one small internal broker for singleton observable surfaces. This is a durable building-block change because generation queue, playback, and runtime all need the same mechanics:

- monotonically increasing sequence
- latest state
- latest snapshot construction
- small replay buffer for late subscribers if useful
- subscriber continuation management
- clean termination and cancellation handling

The simpler alternative is three hand-rolled brokers. That would duplicate actor-owned continuation code and make update semantics drift between surfaces. A shared internal broker removes real duplication without changing public ownership boundaries.

Do not expose this broker publicly. It is an implementation detail that lets the public API stay small.

## Migration Rules

- Removed `runtime.player`; replaced it with `runtime.playback`.
- Removed public `Player`; replaced it with `Playback`.
- Removed typed Swift snapshot-read request-handle methods that are superseded by
  direct snapshots:
  - `runtime.status()` -> `runtime.snapshot()`
  - `runtime.overview()` -> `runtime.snapshot()`
  - `Player.list()` -> `runtime.playback.snapshot()`
  - `Player.state()` -> `runtime.playback.snapshot()`
- Renamed current per-request `GenerationEvent` and `GenerationEventUpdate` to `SynthesisEvent` and `SynthesisUpdate`.
- Replaced `RuntimeOverview` with `RuntimeSnapshot` in the typed Swift surface.
- Replaced `PlaybackStateSnapshot` with `PlaybackSnapshot`.
- Replaced `statusEvents()` with `updates()` on `Runtime`.
- Replaced `RequestCompletion` cases that exposed old observation
  vocabulary so typed completion payloads also use `RuntimeSnapshot`,
  `RuntimeUpdate`, and `PlaybackSnapshot`.
- Kept JSONL `worker_status` and `get_runtime_overview` stable. This plan was about the typed Swift API.
- Updated DocC and tests in the same implementation pass as the public symbols.
- Update `SpeakSwiftlyServer` adoption separately before release.

## Implementation Slices

These slices record the implementation path that was used.

### Slice 1: Model Contract

Added the new public model families and tests for their intended shape.

Expected files:

- `Sources/SpeakSwiftly/SpeakSwiftly.swift`
- `Sources/SpeakSwiftly/API/RequestObservation.swift`
- `Sources/SpeakSwiftly/API/Generation.swift`
- `Sources/SpeakSwiftly/API/Playback.swift`
- `Sources/SpeakSwiftly/API/Configuration.swift`
- `Tests/SpeakSwiftlyTests/API/LibrarySurfaceTests.swift`

### Slice 2: Internal Observation Broker

Added the internal singleton observation broker and covered sequence, replay, snapshot, and subscriber behavior through the typed runtime, generation, playback, and request-observation tests.

The broker lives under `Runtime/` because it is shared by runtime, generation, and playback observation.

### Slice 3: Runtime Observation

Wired runtime resident-model transitions into `RuntimeUpdate` and `RuntimeSnapshot`.

Publish updates for:

- resident warmup start
- resident ready
- resident unload
- resident failure
- backend switch
- model reload
- default voice-profile change when it affects runtime snapshot state

### Slice 4: Playback Observation

Renamed `Player` to `Playback`, converted playback snapshot naming, and published playback updates from meaningful playback-state transitions.

Keep raw playback trace detail internal unless a concrete consumer need appears.

### Slice 5: Generate Observation

Added queue-level generation updates and snapshots from generation queue changes.

Published updates when generation becomes idle, running, or blocked. Snapshot carries active and queued request summaries.

### Slice 6: Per-Request Synthesis Rename

Renamed the current per-request generation event stream to synthesis naming.

This touched request handle fields, runtime lookup methods, tests, and DocC in one pass so consumers get one coherent vocabulary.

### Slice 7: Cleanup And Documentation

Removed stale typed Swift symbols and updated:

- DocC
- `CONTRIBUTING.md`
- `AGENTS.md`
- `ROADMAP.md`
- release notes or migration notes for the next breaking release

Ran the ordinary package validation lane after implementation:

```bash
swift build
swift test
```

Used targeted tests for request observation, runtime control, worker protocol encoding, and library surface shape before the full package test run.

## Non-Goals

- Do not introduce public compatibility shims for the old typed Swift names.
- Do not change JSONL operation names as part of this typed Swift cleanup.
- Do not expose raw playback-driver traces as public playback events without a concrete consumer.
- Do not make runtime snapshots own generation and playback details that belong to `GenerateSnapshot` and `PlaybackSnapshot`.
- Do not replace request-scoped observation; the `Request` family remains the per-request source of truth.

## Implementation Notes

- Public singleton `Event` enums are part of the named family, but the first
  implementation pass kept them compact and meaningful. Add cases only
  for events consumers can branch on usefully now; do not expose internal
  scheduler or playback-driver chatter just to fill the enum.
- Singleton `updates()` streams replay the latest update by default,
  matching the practical behavior of the removed `statusEvents()` and making late UI
  or agent subscribers useful immediately.
- `RequestHandle.completion()` still returns `RequestCompletion` in this
  pass. Operation-specific typed wait helpers can be considered later if real
  call sites show that the single completion enum is still too broad.
