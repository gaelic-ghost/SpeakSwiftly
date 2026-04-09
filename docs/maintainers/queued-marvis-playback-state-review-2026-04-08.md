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

## 2026-04-08 Warmup Threshold Seeding Follow-up

The next playback-quality pass found a concrete startup-threshold bug:

- `PlaybackThresholdController` started in `.warmup`
- but its initial thresholds were seeded from the `.steady` profile instead of the `.warmup` profile

That meant the first live request in a drained queue could start with startup-buffer targets that were too optimistic until enough chunks arrived for adaptive tuning to catch up.

That bug is now fixed so the first request starts from warmup-biased thresholds immediately.

Verification after that tuning pass:

- `swift test --filter 'adaptivePlaybackThresholdsSeedFromTextComplexityClasses|adaptivePlaybackThresholdsStartFromWarmupBiasedTargets|adaptivePlaybackThresholdsRaiseTargetsForSlowCadenceAndStarvation|adaptivePlaybackThresholdsRaiseTargetsForRepeatedRebuffers|adaptivePlaybackThresholdsLeaveWarmupAfterStableChunkCadence|adaptivePlaybackThresholdsStayInWarmupWhileEarlyCadenceTrailsRealtimePlayback|adaptivePlaybackThresholdsEnterRecoveryAfterRebufferAndReturnToSteadyAfterStableChunks'`
- `SPEAKSWIFTLY_E2E=1 swift test --filter marvisAudibleLivePlaybackPrequeuesThreeJobsAndDrainsInOrder`

The queued-live Marvis lane still passes end to end after the warmup-threshold change.

## 2026-04-08 Architectural Correction Plan

The blunt queued-live Marvis gate that parked all later live generation behind active playback was a correctness-first stopgap, not an acceptable final design.

The durable correction path is:

1. Restore honest multi-active generation bookkeeping instead of keeping a single global active-generation slot.
2. Treat Marvis resident voices as real generation lanes:
   - `conversational_a`
   - `conversational_b`
3. Protect the fragile first-playback window with playback-stability gating instead of blanket serialization:
   - while active playback has not yet reached a stable preroll/resume state, later queued live Marvis generation stays parked
   - once playback is stable, later queued live Marvis generation may start again on any free resident lane
4. Keep same-lane Marvis work serialized even after playback becomes stable.
5. Make queue and scheduler observability explicit enough that future regressions are obvious from logs and control-surface snapshots instead of inferred from hangs.

That means the intended steady-state behavior becomes:

- one live request may be actively playing
- later live Marvis requests may keep generating ahead
- but only after the active playback request has enough buffered audio to tolerate overlap
- and only up to the actual resident-lane capacity

### Implementation shape

The runtime-side implementation work for this correction is:

- replace the single `activeGeneration` slot with multi-active generation tracking
- update generation queue selection so it can start multiple runnable jobs in one pass
- infer Marvis lane ownership from the queued request's profile vibe
- park later live Marvis requests behind playback only while playback is still unstable
- park same-lane Marvis generation while that lane is already active
- surface generation queue truth with `active_requests` rather than only a single `active_request`
- add scheduler and lane observability:
  - `marvis_generation_scheduler_snapshot`
  - `marvis_generation_lane_reserved`
  - `marvis_generation_lane_released`

### Expected validation

The focused validation target for this pass is:

- queued live Marvis request 1 reaches `preroll_ready`
- queued live Marvis request 2 starts generation before request 1 playback finishes
- queued live Marvis request 3 only waits when its resident lane is still occupied
- generation queue introspection reports all active generation requests, not only one
- playback still drains cleanly and the targeted Marvis queued-live E2E lane remains green

## 2026-04-09 Implemented Correction And Verification

The architectural correction is now implemented.

### What changed

- `GenerationController` now tracks multiple active generation jobs instead of a single global active slot.
- The runtime generation scheduler now evaluates all queued work against:
  - resident-model readiness
  - playback stability
  - Marvis resident-lane occupancy
  - backend-specific concurrent-generation capacity
- Queued live Marvis generation is no longer blanket-serialized behind active playback.
- Instead, later live Marvis generation now waits only until the active playback request becomes stable for overlap, then it may start on a free resident lane.
- Same-lane Marvis work still remains serialized.
- Generation queue control-surface results now expose `active_requests` so the runtime can report honest multi-active generation state.
- The runtime now emits explicit queued-state transitions as scheduler park reasons change, instead of only emitting one queued event at initial acceptance time.

### New or strengthened observability

The runtime now emits scheduler-focused observability that makes queued-live Marvis behavior much easier to inspect directly:

- `marvis_generation_scheduler_snapshot`
- `marvis_generation_lane_reserved`
- `marvis_generation_lane_released`
- queued request events with updated reasons when scheduler park conditions change, including:
  - `waiting_for_playback_stability`
  - `waiting_for_marvis_generation_lane`

The scheduler snapshot now captures:

- active generation request IDs
- active Marvis lane assignments
- active playback request ID
- whether playback is currently stable for concurrent generation
- whether playback is currently rebuffering
- stable buffered-audio and target-buffer values
- parked generation reasons for waiting queued requests

### What the corrected queued-live Marvis behavior means

The intended queued-live Marvis path is now:

1. request 1 starts generation first
2. request 1 acquires playback ownership and must reach a stable preroll or resumed state before overlap is allowed
3. request 2 may then start generation on the other Marvis lane before request 1 playback finishes
4. request 3 stays queued only while both resident lanes are effectively occupied
5. playback remains single-owner, but generation may run ahead up to true resident-lane capacity

That restores the design intent much more honestly than the earlier stopgap that effectively reduced queued live Marvis to one useful lane.

### Verification completed

Focused runtime and surface validation passed:

- `swift test --filter 'WorkerRuntimeQueueingTests|WorkerRuntimeControlSurfaceTests|WorkerProtocolTests|LibrarySurfaceTests'`

Targeted queued-live Marvis E2E passed:

- `SPEAKSWIFTLY_E2E=1 swift test --filter marvisAudibleLivePlaybackPrequeuesThreeJobsAndDrainsInOrder`
- pass time: `102.158s`

Full explicit E2E passed:

- `SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests`
- pass time: `616.893s`

Full standard test suite passed:

- `swift test`
- pass time: `152 tests in 7 suites`

### Review of whether this meets the intended requirements

What this now satisfies:

- the runtime again tells the truth about more than one active generation request
- queued live Marvis generation can overlap playback once playback is actually stable
- later queued live Marvis work is no longer artificially serialized behind all active playback
- same-lane Marvis work is still prevented from colliding
- the queue and scheduler state are much more observable than before
- the exact queued-live Marvis E2E lane is green again under the restored overlap model

What still remains true:

- the first live Marvis playback in a drained queue is still the most fragile audible path
- playback-quality tuning and scheduler correctness are now separated much more cleanly
- any remaining first-request roughness should now be treated as a playback-buffer and cadence-tuning problem, not as a reason to collapse the scheduler back into blanket serialization
