# Observation API Cleanup Plan

This note records the agreed breaking public API cleanup for SpeakSwiftly's typed Swift observation surfaces.

## Decision

The package will standardize observable state around one vocabulary:

- `Event`: something meaningful that just happened.
- `State`: the current semantic condition of an observable surface.
- `Update`: a sequenced, timestamped state publication.
- `Snapshot`: a point-in-time read of the full surface.

`RequestEvent`, `RequestState`, `RequestUpdate`, and `RequestSnapshot` are the model to copy. The cleanup should adapt that shape across request-scoped synthesis, the generation queue, playback, and runtime resident-model state.

This is a breaking API cleanup. Do not leave compatibility shims for old typed Swift names unless Gale explicitly approves that compromise before implementation.

## Target Public Families

### Request

Request observation remains the per-request anchor:

- `RequestEvent`
- `RequestState`
- `RequestUpdate`
- `RequestSnapshot`
- `RequestHandle`

Keep this model as the source of truth for individual submitted operations. A request is the only surface that naturally has many concurrent instances, so request updates and snapshots keep request identity.

### Synthesis

The current per-request `GenerationEvent` and `GenerationEventUpdate` names are too broad because `Generate` should become the global generation-queue concern. Rename the per-request model to synthesis-specific names:

- `SynthesisEvent`
- `SynthesisUpdate`

These events describe model-side production for one request: token ids, generation metrics, and audio chunk sample counts. They do not describe the global generation queue.

Target request-handle shape:

```swift
public struct RequestHandle: Sendable {
    public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>
    public let synthesisUpdates: AsyncThrowingStream<SynthesisUpdate, any Swift.Error>
}
```

Target runtime lookup:

```swift
func synthesisUpdates(
    for requestID: String
) -> AsyncThrowingStream<SynthesisUpdate, any Swift.Error>
```

### Generate

`runtime.generate` should own the global generation-queue observation surface. It should describe whether generation is idle, running, or blocked and expose the active and queued generation requests.

Target family:

- `GenerateEvent`
- `GenerateState`
- `GenerateUpdate`
- `GenerateSnapshot`

Target surface:

```swift
extension SpeakSwiftly.Generate {
    func updates() -> AsyncStream<GenerateUpdate>
    func snapshot() async -> GenerateSnapshot
}
```

`GenerateState` should stay semantic and compact. The rich queue details belong in `GenerateSnapshot`.

Candidate shape:

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

`GenerateBlockReason` should be the Swift-facing equivalent of generation park reasons such as resident-model warmup, resident-model unload, active generation, playback stability, and Marvis lane serialization.

### Playback

Rename the public handle from `runtime.player` to `runtime.playback`. The public noun should match the domain and the model family.

Target family:

- `PlaybackEvent`
- `PlaybackState`
- `PlaybackUpdate`
- `PlaybackSnapshot`

Target surface:

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

`PlaybackState` should remain small enough for UI and agent consumers to branch on directly. Snapshot carries richer telemetry.

Candidate shape:

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

Raw playback-driver events such as trace samples, buffer-shape summaries, route-change internals, and rebuffer warnings should stay internal diagnostics unless a concrete Swift consumer needs them. The public update stream should publish domain states, not driver chatter.

### Runtime

Replace the public `StatusEvent` and `RuntimeOverview` vocabulary with runtime observation names.

Target family:

- `RuntimeEvent`
- `RuntimeState`
- `RuntimeUpdate`
- `RuntimeSnapshot`

Target surface:

```swift
extension SpeakSwiftly.Runtime {
    func updates() -> AsyncStream<RuntimeUpdate>
    func snapshot() async -> RuntimeSnapshot
}
```

Candidate shape:

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

`RuntimeSnapshot` replaces the public role of `RuntimeOverview`. Queue and playback details should be available through `runtime.generate.snapshot()` and `runtime.playback.snapshot()` instead of making the runtime snapshot a mixed owner for every domain.

## Singleton Observation Broker

Add one small internal broker for singleton observable surfaces. This is a durable building-block change because generation queue, playback, and runtime all need the same mechanics:

- monotonically increasing sequence
- latest state
- latest snapshot construction
- small replay buffer for late subscribers if useful
- subscriber continuation management
- clean termination and cancellation handling

The simpler alternative is three hand-rolled brokers. That would duplicate actor-owned continuation code and make update semantics drift between surfaces. A shared internal broker removes real duplication without changing public ownership boundaries.

Do not expose this broker publicly. It is an implementation detail that lets the public API stay small.

## Migration Rules

- Remove `runtime.player`; replace it with `runtime.playback`.
- Remove public `Player`; replace it with `Playback`.
- Rename current per-request `GenerationEvent` and `GenerationEventUpdate` to `SynthesisEvent` and `SynthesisUpdate`.
- Replace `RuntimeOverview` with `RuntimeSnapshot` in the typed Swift surface.
- Replace `PlaybackStateSnapshot` with `PlaybackSnapshot`.
- Replace `statusEvents()` with `updates()` on `Runtime`.
- Keep JSONL `worker_status` and `get_runtime_overview` stable unless a separate wire-contract decision is made. This plan is about the typed Swift API.
- Update DocC and tests in the same implementation pass as the public symbols.
- Update `SpeakSwiftlyServer` adoption separately before release.

## Implementation Slices

### Slice 1: Model Contract

Add the new public model families and tests for their intended shape.

Expected files:

- `Sources/SpeakSwiftly/SpeakSwiftly.swift`
- `Sources/SpeakSwiftly/API/RequestObservation.swift`
- `Sources/SpeakSwiftly/API/Generation.swift`
- `Sources/SpeakSwiftly/API/Playback.swift`
- `Sources/SpeakSwiftly/API/Configuration.swift`
- `Tests/SpeakSwiftlyTests/API/LibrarySurfaceTests.swift`

### Slice 2: Internal Observation Broker

Add the internal singleton observation broker and unit coverage for sequence, replay, snapshot, subscriber removal, and terminal behavior where relevant.

The broker should live under `Runtime/` or a small support file if it is genuinely shared by runtime, generation, and playback.

### Slice 3: Runtime Observation

Wire runtime resident-model transitions into `RuntimeUpdate` and `RuntimeSnapshot`.

Publish updates for:

- resident warmup start
- resident ready
- resident unload
- resident failure
- backend switch
- model reload
- default voice-profile change when it affects runtime snapshot state

### Slice 4: Playback Observation

Rename `Player` to `Playback`, convert playback snapshot naming, and publish playback updates from meaningful playback-state transitions.

Keep raw playback trace detail internal unless a concrete consumer need appears.

### Slice 5: Generate Observation

Add queue-level generation updates and snapshots from generation queue changes.

Publish updates when generation becomes idle, running, or blocked. Snapshot should carry active and queued request summaries.

### Slice 6: Per-Request Synthesis Rename

Rename the current per-request generation event stream to synthesis naming.

This should touch request handle fields, runtime lookup methods, tests, and DocC in one pass so consumers get one coherent vocabulary.

### Slice 7: Cleanup And Documentation

Remove stale typed Swift symbols and update:

- DocC
- `CONTRIBUTING.md`
- `AGENTS.md`
- `ROADMAP.md`
- release notes or migration notes for the next breaking release

Run the ordinary package validation lane after implementation:

```bash
swift build
swift test
```

Use targeted tests between slices when the implementation touches request observation, runtime lifecycle, playback, or generation scheduling.

## Non-Goals

- Do not introduce public compatibility shims for the old typed Swift names.
- Do not change JSONL operation names as part of this typed Swift cleanup.
- Do not expose raw playback-driver traces as public playback events without a concrete consumer.
- Do not make runtime snapshots own generation and playback details that belong to `GenerateSnapshot` and `PlaybackSnapshot`.
- Do not replace request-scoped observation; the `Request` family remains the per-request source of truth.

## Open Checks Before Implementation

- Confirm whether `RuntimeEvent`, `GenerateEvent`, and `PlaybackEvent` need public payload cases immediately, or whether `State`/`Update`/`Snapshot` is enough for the first breaking pass.
- Decide whether singleton `updates()` streams should replay the latest update by default, matching the practical behavior of current `statusEvents()`.
- Decide whether `RequestHandle.completion()` should keep returning `RequestCompletion` or whether operation-specific typed wait helpers should be introduced later.
