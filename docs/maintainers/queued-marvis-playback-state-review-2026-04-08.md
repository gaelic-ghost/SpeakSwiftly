# Queued Marvis Playback State Review

## Summary

This note captures the playback-side findings from the queued live Marvis investigation on `2026-04-08` before implementation work widened further.

The strongest current read is:

- The remaining queued live Marvis stall does not primarily look like a `SpeakSwiftlyServer` snapshot-composition bug after the server cleanup pass.
- The tighter issue in `SpeakSwiftly` is that playback state is still reported from two ownership layers at once.
- Queued live Marvis generation is also still allowed to continue behind active playback, which makes the runtime work harder during the exact phases where playback ownership is most delicate.

## Main Findings

### Playback state is split across two ownership layers

`PlaybackController.stateSnapshot()` currently combines:

- `driver.state()`
- `activeRequestSummary()`

Those values do not come from one source of truth.

This means a snapshot can report:

- `state: idle`
- `active_request: <non-nil>`

without any server-side recomposition bug.

This can happen because:

- `PlaybackController` claims active playback ownership before `AudioPlaybackDriver` reaches a playing state.
- `AudioPlaybackDriver` resets its own `playbackState` to `idle` at the start of `play()`.
- The driver does not mark itself as `playing` until preroll buffering crosses the startup threshold.
- On interruption, the driver can be forced back to `idle` before the controller clears `activePlayback`.

That split is especially visible during:

- startup buffering before `preroll_ready`
- rebuffer handling
- interruption/failure cleanup
- final drain

### Queued live generation can still run behind active playback

The current scheduler still allows later live speech generation to proceed while earlier live playback is active.

That is because `requiresPlaybackDrainBeforeStart` currently only applies to:

- `switch_speech_backend`
- `reload_models`
- `unload_models`

and not to ordinary live speech requests.

That behavior is not automatically wrong, but it means queued live Marvis can keep consuming CPU while an earlier request is still trying to:

- reach preroll stability
- avoid rebuffer churn
- drain scheduled playback cleanly

That makes the queued live Marvis lane harsher than the single-live case and is a plausible amplifier for the hot-CPU stalled repros.

### The public playback state is too thin for the real playback lifecycle

The current public playback state only exposes:

- `idle`
- `playing`
- `paused`

The real playback lifecycle is richer than that and includes at least:

- startup buffering before preroll
- active playback with healthy queue depth
- active rebuffering
- final drain after generation has finished

Because those phases are collapsed into a thin public state, consumers have to infer too much from:

- `active_request`
- progress events
- queue snapshots

That increases the chance of apparently contradictory state.

### Test coverage is stronger on eventual completion than on state consistency

The current runtime tests already do a good job checking:

- queued acknowledgement
- `preroll_ready`
- `playback_finished`
- eventual terminal success/failure

But they do not yet put much pressure on this invariant:

- while a live request is active, `playback_state` and `active_request` should remain mutually consistent

That gap matters because queued Marvis and real AVFoundation playback stress the controller/driver ownership split harder than the fast spy-based playback tests do.

## Immediate Fix Direction

The first fix pass should focus on playback-state ownership, not on broad scheduler changes.

Recommended order:

1. Make `PlaybackController` return a controller-consistent playback state snapshot while a request is active.
2. Add runtime control-surface coverage for `player.state()` during active preroll/queued-live playback.
3. Re-run the focused fast tests.
4. Reassess whether queued live Marvis still needs stricter scheduler gating or backend-sensitive behavior after the state model is trustworthy.

## Follow-up Questions

- Should playback-state reporting remain thin and collapse all active phases into `playing` unless manually paused?
- Or should the public playback state eventually grow explicit buffering/draining states?
- Once playback state is trustworthy, does queued live Marvis still need the freedom to generate behind active playback?
- If so, do we need a backend-sensitive concurrency rule for heavier resident backends like Marvis?

## 2026-04-08 Follow-up Fixes and Verification

Two runtime-side fixes landed after the initial review:

1. `PlaybackController` now reports playback state from controller-owned active playback truth instead of exposing a raw `driver.state()` plus `active_request` pair that can disagree during preroll, interruption, or drain.
2. Live Marvis generation now parks later live requests behind active playback, and queued-event reporting now treats that parked state as a real `waiting_for_active_request` condition instead of silently accepting and parking the work.

Verification after those fixes:

- `swift test --filter 'WorkerRuntimeQueueingTests|WorkerRuntimeControlSurfaceTests'`
- `SPEAKSWIFTLY_E2E=1 swift test --filter marvisAudibleLivePlaybackPrequeuesThreeJobsAndDrainsInOrder`

The targeted queued-live Marvis E2E lane now passes instead of stalling.

Subjective audible result from the latest run:

- the first queued playback was still somewhat janky and hit noticeable rebuffering
- the second queued playback sounded good
- the third queued playback also sounded good

That suggests the deadlock/overlap problem improved meaningfully, but the first live Marvis request is still carrying most of the startup-buffer pressure and likely needs separate tuning around:

- initial startup buffer thresholds
- Marvis-specific chunk cadence or scheduling
- rebuffer recovery targets during the first live request in a drained queue
