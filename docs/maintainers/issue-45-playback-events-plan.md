# Issue 45 Playback Events Plan

## Purpose

Issue 45 is not about adding a new playback observation stream. SpeakSwiftly
already exposes the runtime-level playback observation surface that the original
issue asked for:

- `runtime.playback.updates()`
- `runtime.playback.snapshot()`
- `SpeakSwiftly.PlaybackUpdate`
- `SpeakSwiftly.PlaybackSnapshot`

The remaining gap is narrower. `SpeakSwiftly.PlaybackEvent` currently only
reports `stateChanged(PlaybackState)`. That is enough for coarse playback state,
but not enough for host/operator surfaces that need to react to meaningful
playback milestones without parsing request logs or polling snapshots.

## Branch Context

- Continue this work on `docs/profile-lock-and-events`.
- Keep the existing profile-lock docs commit and add the playback-event API work on top of that branch.
- Do not split this work back onto a separate feature branch.
- The implementation target is issue 45 only: richer event values inside the existing public playback update stream.
- No code WIP should be carried in this plan commit.

## Public API Decision

- Keep `runtime.playback.updates()` as the public stream.
- Keep `SpeakSwiftly.PlaybackUpdate` as the public envelope.
- Keep `SpeakSwiftly.PlaybackSnapshot` as the point-in-time read model.
- Do not add a second playback stream.
- Expand `SpeakSwiftly.PlaybackEvent` so consumers can distinguish meaningful playback milestones without parsing worker logs or polling snapshots.
- Keep `PlaybackUpdate.state` authoritative by deriving it from the current playback snapshot when publishing any event.
- Preserve `PlaybackUpdate` and `PlaybackSnapshot` as the main public observation envelope.
- Treat this as a durable public API vocabulary change, not a worker-log naming pass.

## Public Playback Event Vocabulary

- `stateChanged(PlaybackState)` for coarse state transitions, including pause and resume.
- `started(requestID: String)` for the moment a live playback request becomes the active playback job.
- `activeRequestChanged(ActiveRequest?)` for host/operator surfaces that track which request is currently active.
- `queueChanged(activeRequest: ActiveRequest?, queuedRequests: [QueuedRequest])` for queue handoff, enqueue, clear, and cancel changes.
- `firstChunk(requestID: String)` for the first audio chunk observed by playback.
- `prerollReady(requestID: String, bufferedAudioMS: Int, startupBufferTargetMS: Int)` for buffer readiness before sustained playback.
- `rebufferStarted(requestID: String, queuedAudioMS: Int, resumeBufferTargetMS: Int)` for rebuffer entry.
- `rebufferResumed(requestID: String, bufferedAudioMS: Int, resumeBufferTargetMS: Int)` for rebuffer recovery.
- `completed(requestID: String)` for the playback job reaching its terminal drain/completion path.
- `outputDeviceChanged(previousDevice: String?, currentDevice: String?)` for stable output-device changes.
- `interruptionChanged(isInterrupted: Bool, shouldResume: Bool?)` for stable interruption begin/end changes.

## Playback Start And Preroll

- Playback start and preroll are related but not the same public milestone.
- `started(requestID:)` means the request has become active playback work and consumers should treat it as the current audible request.
- `prerollReady(...)` means playback has enough buffered audio to satisfy the startup threshold.
- The public stream should expose both so SpeakSwiftlyServer can update active-request state separately from buffer-readiness state.

## Completion And Drain

- Completion should be documented from the consumer point of view.
- `completed(requestID:)` means the playback job reached the terminal drain/completion path for that request.
- Consumers should not need to infer terminal playback from request logs or from the disappearance of an active request alone.
- Existing request-scoped completion and progress events should remain intact.

## Events That Stay Internal

- Detailed trace events.
- Chunk-gap warnings.
- Schedule-gap warnings.
- Queue-depth-low diagnostics.
- Rebuffer-thrash warnings.
- Buffer-shape summaries.
- Engine-configuration noise unless it becomes a stable public playback state.
- Recovery internals.
- Inter-job boop events.
- Starvation logs unless a future public starvation event is explicitly designed.

## Runtime Publisher Design

- Add a helper that publishes `PlaybackUpdate` from the current `PlaybackSnapshot` plus a specific `PlaybackEvent`.
- Keep the existing state-only behavior by defaulting to `stateChanged(snapshot.state)` when no event is provided.
- Add focused helpers for active-request and queue changes only if they keep call sites readable.
- Do not let call sites hand-author `PlaybackUpdate.state`.
- The helper should read the current snapshot so state, active request, queued requests, and rebuffer telemetry stay coherent.
- The implementation should keep the current replay behavior for new subscribers: the latest playback update should still be yielded when a consumer subscribes.

## Playback Hook Wiring

- In `RuntimePlaybackEvents.swift`, map internal `.firstChunk` to public `.firstChunk(requestID:)`.
- Map internal `.prerollReady` to public `.prerollReady(requestID:bufferedAudioMS:startupBufferTargetMS:)`.
- Map internal `.rebufferStarted` to public `.rebufferStarted(requestID:queuedAudioMS:resumeBufferTargetMS:)`.
- Map internal `.rebufferResumed` to public `.rebufferResumed(requestID:bufferedAudioMS:resumeBufferTargetMS:)`.
- Map internal environment `.outputDeviceChanged` to public `.outputDeviceChanged`.
- Map internal environment `.interruptionStateChanged` to public `.interruptionChanged`.
- Keep all existing logs and request-scoped progress events intact.
- Keep trace-only playback diagnostics in logs rather than promoting them into `PlaybackEvent`.

## Queue, Control, And Completion Wiring

- Publish `.queueChanged(...)` after a live playback request is enqueued.
- Publish `.started(requestID:)` when `PlaybackQueue.startNextIfPossible()` promotes a queued request to active playback.
- Publish `.activeRequestChanged(...)` when the active playback request changes.
- Publish `.completed(requestID:)` from the playback completion path after the request reaches terminal playback drain/completion.
- Publish queue or active-request changes after finish so consumers see the active request disappear or the next request take over.
- Publish queue changes after `clearQueue`, queue-specific cancel operations, broad cancel operations, and playback queue discard paths that materially alter playback work.
- Preserve pause and resume through `stateChanged(.paused)` and `stateChanged(.playing)`.
- Test pause and resume explicitly because issue 45 calls those transitions out.

## Documentation Updates

- Update DocC API/quick-start guidance where playback observation is described.
- Update the typed observation maintainer doc so the planned API shape matches the actual public API.
- Document the public event vocabulary and what each event means from a consumer/operator point of view.
- Explicitly say detailed trace-only playback diagnostics remain internal logs, not public `PlaybackEvent` cases.
- Tell SpeakSwiftlyServer-style consumers to subscribe to `runtime.playback.updates()` and branch on `update.event`.
- Tell consumers to use `update.state` for the current coarse playback state.
- Tell consumers to use `runtime.playback.snapshot()` when they need a fresh aggregate read of active request, queued requests, and rebuffer telemetry.

## Tests

- Add a public API shape test in `LibrarySurfaceTests` for the new `PlaybackEvent` cases and `PlaybackUpdate.event` key path.
- Add a fast runtime observation test that subscribes to `runtime.playback.updates()` and confirms first chunk, preroll ready, rebuffer started/resumed, and completion events appear for a fake playback driver.
- Add a queue/active-request observation test for enqueue and handoff, ideally with two live playback requests and a gated fake playback driver.
- Add a pause/resume observation test confirming state-changed events for `.paused` and `.playing`.
- Add an environment event observation test for output-device and interruption events using existing fake environment-event injection.
- Keep tests in the normal SwiftPM package test lane.
- Do not require real MLX model/audio E2E for this issue.

## Validation

- Run targeted Swift tests for the playback observation/API tests first.
- Run `swift build` if the enum/Codable shape or public API changes need compile proof beyond targeted tests.
- Run `swift test` or the repo-maintenance validation lane before commit if the targeted tests pass and time allows.
- Commit on `docs/profile-lock-and-events` after docs, implementation, and tests are coherent.
- Push `docs/profile-lock-and-events`; do not create another branch for issue 45.
