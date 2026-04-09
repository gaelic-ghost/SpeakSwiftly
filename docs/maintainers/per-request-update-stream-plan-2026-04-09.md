# Per-Request Update Stream Plan

## Summary

This note captures the planned implementation for on-demand per-request observation in `SpeakSwiftly` as of `2026-04-09`.

The immediate goal is modest and deliberate:

- add a strong in-process per-request observation surface for callers that know only a request ID
- keep the existing `RequestHandle.events` surface source-compatible
- avoid widening this into a cross-process persistence or subscription system yet

This is a durable building-block change, not a local convenience helper, because it changes the runtime's request-observation model from one private stream per original submitter to one runtime-owned per-request event broker with multiple in-process subscribers.

## Current Problem

Today, the package only offers per-request updates to the code that originally submitted the request.

That behavior comes from the current shape in `WorkerRuntime`:

- `runtime.submit(_:)` creates a `RequestHandle`
- that handle owns a single `AsyncThrowingStream`
- the stream continuation is stored in `requestContinuations[requestID]`
- `yieldRequestEvent` pushes updates only into that one continuation
- terminal success or failure removes the continuation entirely

That is workable for direct library callers, but it has two real limitations:

1. a caller that only knows a request ID cannot attach later
2. a caller that disconnects and reconnects inside the same process has no clean way to rehydrate current request state before watching live updates again

That gap is exactly what makes consumers like `SpeakSwiftlyServer` lean harder on queue snapshots, playback snapshots, and host-side inference than they should.

## Goals

- let an in-process caller reattach to a request using only its request ID
- expose current per-request state separately from live updates so callers can avoid attach-time races
- support multiple simultaneous subscribers to the same request
- preserve the existing `RequestHandle.events` experience for callers already using it
- make failure and cancellation readable as data for new late-subscriber APIs
- document the lifecycle clearly enough that callers do not need to inspect runtime internals

## Non-Goals

- no durable cross-process subscription contract yet
- no persisted event history yet
- no worker-protocol or JSONL subscription channel yet
- no requirement that `SpeakSwiftlyServer` consume this immediately
- no speculative general event bus beyond per-request observation

## Proposed Public API

### Snapshot read

Add a public runtime API:

- `runtime.request(id: String) async -> SpeakSwiftly.RequestSnapshot?`

This returns the runtime's current in-memory truth for a request ID if the runtime still knows about it.

The snapshot should include:

- `id`
- `operation`
- `profileName`
- `acceptedAt`
- `lastUpdatedAt`
- `sequence`
- `state`

The state should be a data enum that can represent:

- queued
- acknowledged
- started
- progress
- completed
- failed
- cancelled

If the runtime no longer knows the request, this returns `nil`.

### Live update stream

Add a public runtime API:

- `runtime.updates(for requestID: String) -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Error>`

This is the new on-demand observation surface for in-process callers.

The returned stream should:

- attach to the runtime-owned broker for that request ID
- deliver live updates after attachment
- optionally deliver a bounded replay window if the implementation chooses that mode
- finish cleanly after terminal completion if the request ends successfully
- finish after yielding terminal failure or cancellation as data

For an unknown request ID, the initial implementation should prefer a simple, unsurprising behavior:

- return a stream that finishes immediately without yielding values

That keeps the API side-effect free and lets callers pair it naturally with `request(id:)`.

### Keep `RequestHandle.events`

Do not remove or rename the existing surface:

- `RequestHandle.events: AsyncThrowingStream<RequestEvent, any Error>`

Instead, make it an adapter over the new broker so existing direct callers keep working.

That keeps the package source-compatible while letting new consumers use the stronger per-request APIs.

## Proposed Public Models

### `RequestSnapshot`

Add a public snapshot type:

- `SpeakSwiftly.RequestSnapshot`

Intended fields:

- `id: String`
- `operation: String`
- `profileName: String?`
- `acceptedAt: Date`
- `lastUpdatedAt: Date`
- `sequence: Int`
- `state: RequestState`

### `RequestUpdate`

Add a public update type:

- `SpeakSwiftly.RequestUpdate`

Intended fields:

- `id: String`
- `sequence: Int`
- `date: Date`
- `state: RequestState`

### `RequestState`

Add a public enum:

- `SpeakSwiftly.RequestState`

The cases should be data-first and closed:

- `queued(QueuedEvent)`
- `acknowledged(Success)`
- `started(StartedEvent)`
- `progress(ProgressEvent)`
- `completed(Success)`
- `failed(Failure)`
- `cancelled(Failure)`

The important shift is that terminal failure and cancellation should be represented as data here, not only as a thrown stream termination.

That makes late-subscriber and MCP-style consumers much simpler.

## Runtime Architecture

### Replace single continuation bookkeeping

Replace the current single-map shape:

- `requestContinuations[requestID] -> one continuation`

with a runtime-owned broker model per request ID.

Each request broker should track:

- static request metadata such as operation and profile name
- a monotonically increasing sequence number
- current `RequestSnapshot`
- terminal state if one exists
- active subscribers
- a bounded replay buffer of recent `RequestUpdate` values

### Broker lifecycle

The broker should be created when the runtime first accepts a request.

More specifically:

- create the broker before any queued, acknowledgement, or started event can be emitted
- stamp `acceptedAt` at broker creation time
- use the broker as the single source of truth for later `lastUpdatedAt` and `sequence` changes

It should then receive every request lifecycle transition:

- queued
- acknowledged
- started
- progress
- completed
- failed

On each transition the broker should:

1. increment sequence
2. update `lastUpdatedAt`
3. update the current snapshot
4. append the new update to the replay buffer
5. fan it out to active subscribers

When the request reaches a terminal state:

- keep the terminal snapshot available for later `request(id:)` lookups
- keep a bounded terminal replay buffer available for short-lived late subscribers
- close active subscribers after delivering the terminal update

### Retention policy

The runtime needs a clear eviction rule so this does not become an unbounded in-memory log.

Recommended initial policy:

- keep active request brokers indefinitely while the request is alive
- keep terminal brokers for a short bounded time window or bounded count after completion
- evict oldest terminal brokers first when the cap is exceeded

That policy should be runtime-internal and intentionally simple for the first pass.

## Replay Policy

This is the main design choice to make before implementation.

### Option A: live tail only

When a caller attaches with `updates(for:)`, they only receive future updates.

Pros:

- simplest semantics
- lowest memory footprint

Cons:

- easy attach-time race unless the caller also reads `request(id:)` immediately first

### Option B: bounded replay on attach

When a caller attaches, they first receive the broker's buffered updates, then live ones.

Pros:

- easier caller ergonomics
- more resilient reconnect story

Cons:

- more subtle semantics around duplicate observation when a caller also reads `request(id:)`

### Recommendation

Implement bounded replay on attach, but keep it modest and explicit:

- replay the buffered updates in sequence order
- then continue live
- document that `request(id:)` returns the latest snapshot and `updates(for:)` may replay recent events

If we later need cursor-based replay, that should be a separate additive API, not hidden in the first version.

## Data Structure Preference

If the replay buffer is easier to express with a dedicated queue type, prefer a small dependency on `swift-collections` and use `Deque<RequestUpdate>` rather than writing a bespoke ring buffer.

That would be an intentional foundational dependency, not speculative abstraction:

- real near-term use case unlocked: bounded replay buffers with clean append-drop-oldest behavior
- current pain removed: hand-rolled queue logic in runtime event bookkeeping
- simpler path considered first: plain `Array`

If `Array` remains obviously adequate after implementation sketching, keep it.

## Compatibility Story

### Existing `RequestHandle.events`

Keep it source-compatible.

Implementation plan:

- when `runtime.submit(_:)` accepts a request, it still returns a `RequestHandle`
- `RequestHandle.events` becomes an adapter over the new broker stream
- for compatibility, that adapter may still terminate with thrown failure semantics if needed

### Existing queue and overview APIs

Keep them.

The new per-request APIs complement:

- `jobs.generationQueue()`
- `player.list()`
- `player.state()`
- `runtime.overview()`

They do not replace those global observation surfaces.

## Test Plan

### New fast tests

Add focused coverage for:

- attaching to `updates(for:)` before any events and seeing the full live sequence
- attaching to `updates(for:)` after queued or started and receiving replay plus live continuation
- attaching after terminal success and still receiving a terminal update plus clean finish
- attaching after terminal failure and receiving terminal failure as data
- multiple simultaneous subscribers receiving the same ordered updates
- `request(id:)` returning current state at queued, started, progress, and terminal phases
- broker eviction rules for old terminal requests

### Compatibility tests

Keep or add coverage proving that:

- `RequestHandle.events` still emits the expected ordering
- `RequestHandle.events` still tears down correctly on success
- `RequestHandle.events` still reports failure and cancellation compatibly for old callers

### E2E-oriented fast integration tests

Add at least one test that simulates server-like usage:

1. submit request
2. drop direct handle reference
3. reconnect using request ID
4. observe progress and completion through `request(id:)` plus `updates(for:)`

That is the real consumer value of this milestone.

## Documentation Plan

Once implemented, update:

- `README.md`
- package docs or DocC once that milestone lands
- `ROADMAP.md`

The docs should present one clear story:

1. submit a request and keep the `RequestHandle` if you are the original caller
2. reconnect later with `runtime.request(id:)` and `runtime.updates(for:)` if you only have the request ID
3. use queue and overview surfaces for global state, not for per-request lifecycle reconstruction

## Implementation Sequencing

Recommended order:

1. add internal broker types and runtime storage
2. route existing lifecycle emission through the broker
3. adapt `RequestHandle.events` onto the broker
4. add `request(id:)`
5. add `updates(for:)`
6. add replay and eviction policy
7. add compatibility and late-subscriber tests
8. update docs

That order keeps existing behavior working while the stronger APIs are brought online.

## Review Checklist Before Coding

Before implementation starts, confirm:

- in-process only is still the intended boundary
- replay-on-attach is the preferred first version
- `RequestHandle.events` should remain source-compatible instead of being redesigned now
- terminal brokers should be retained for a bounded short-lived reconnect window

## Expected Outcome

When this milestone is complete:

- a caller can reconnect to request state using only the request ID
- a caller like `SpeakSwiftlyServer` can track one request directly instead of reconstructing it from global snapshots
- direct library callers keep the existing `RequestHandle.events` ergonomics
- the runtime has one deliberate per-request observation model instead of a one-off continuation map
