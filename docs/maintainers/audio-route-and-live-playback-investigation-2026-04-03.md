# Audio Route And Live Playback Investigation

## 2026-04-03 context

Context:

- The live `speak-to-user-mcp` host accumulated a long-running background playback request and a growing playback queue instead of draining normally.
- Host-side status eventually showed one active playback job plus a multi-hour queued backlog behind it.
- The same live period also surfaced a user-visible suspicion around automatic device or headphone switching, especially across macOS output changes and AirPods-style route changes.
- This note investigates whether a more direct fix belongs inside `SpeakSwiftly` itself instead of only in the MCP host that launches it.

Important scope note:

- The live host symptoms do **not** prove that a route change caused the stuck playback.
- What we can say confidently is narrower:
  - the worker produced repeated rebuffer signals without a terminal completion event
  - the native playback runtime currently does not observe output-device or engine-configuration changes
  - that missing observability and recovery path makes route-change failures plausible and hard to prove

## What we observed from the live host

Observed host behavior:

- One background playback request began running and never emitted a terminal completion event that the host could use to retire it.
- Later background playback requests queued behind that active request for hours.
- The host continued to surface repeated `playback_rebuffer_started` and `playback_rebuffer_resumed` events from the worker path instead of a clean `playback_finished` or a terminal failure.

Why this matters for `SpeakSwiftly`:

- The live host is mostly a launcher and queue observer here; the actual audio engine and playback lifecycle live inside `SpeakSwiftly`.
- If native playback gets wedged after an output-device transition or an engine configuration change, the most direct place to detect and recover is the worker runtime itself.

## Current `SpeakSwiftly` playback behavior

Relevant code:

- [`Playback/PlaybackController.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Playback/PlaybackController.swift)
- [`Playback/PlaybackOperations.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Playback/PlaybackOperations.swift)
- [`Runtime/WorkerRuntime.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift)
- [`Runtime/WorkerProtocol.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Runtime/WorkerProtocol.swift)

Current `PlaybackController` behavior:

- `PlaybackController` is now a real playback-owned actor that coordinates queued playback jobs, active playback state, cancellation, and shutdown.
- The lower-level AVFoundation engine driver is internal to the playback feature rather than being the thing that owns queue state.
- `prepare(sampleRate:)` only rebuilds the engine when the engine is missing, the player node is missing, or the stored sample rate has changed.
- If the engine already exists and the sample rate is unchanged, the controller only tries to restart `audioEngine` if it is not running and then calls `playerNode.play()` if needed.
- `rebuildEngine(sampleRate:)` creates a fresh `AVAudioEngine`, attaches `AVAudioPlayerNode`, connects it to `mainMixerNode`, prepares, starts, and begins playback.

Concrete code points:

- [`Playback/PlaybackController.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Playback/PlaybackController.swift)
- [`Playback/PlaybackOperations.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Playback/PlaybackOperations.swift)

What is missing today:

- No observer for output-device changes.
- No observer for audio-engine configuration changes.
- No explicit snapshot of the current output device, hardware format, or route state in playback logs.
- No runtime-specific recovery path that says "the output device changed during active playback, so rebuild the engine and either resume safely or fail loudly."

Repo-wide source search did **not** find current use of:

- `AVAudioSession.routeChangeNotification`
- `AVAudioEngineConfigurationChangeNotification`
- `NotificationCenter`-based playback reconfiguration hooks for route changes
- Core Audio default-output listeners such as `AudioObjectAddPropertyListenerBlock`

Interpretation:

- If macOS output routing changes underneath a running request, the current runtime has no explicit place to notice that transition, record it, and decide whether to rebuild or fail.
- That is a real runtime blind spot even if the specific live-service stall we saw turns out to have another trigger.

## Apple API behavior that matters here

This package targets native macOS, not iOS.

Documented APIs consulted:

- `AVAudioEngineConfigurationChangeNotification`
- `AVAudioEngine`
- `AudioObjectAddPropertyListenerBlock`
- `kAudioHardwarePropertyDefaultOutputDevice`
- `AVAudioSession.routeChangeNotification`
- `AVAudioSession.currentRoute`

Documented behavior we should rely on:

- Apple documents `AVAudioEngineConfigurationChangeNotification` as the engine-side signal that audio-hardware configuration changed. When the engine I/O unit observes an input or output hardware sample-rate or channel-count change, the engine stops and uninitializes. Nodes remain attached, but the app may need to reestablish connections if formats must change.
- Apple documents Core Audio default-device property listeners, including `AudioObjectAddPropertyListenerBlock` and `kAudioHardwarePropertyDefaultOutputDevice`, as the native macOS mechanism for learning that the system output device changed.
- Apple documents `AVAudioSession.routeChangeNotification` and `currentRoute`, but those APIs are for iOS-family platforms and Mac Catalyst rather than native AppKit macOS audio routing.

Interpretation:

- For native macOS `SpeakSwiftly`, the likely direct fix path is **not** "just add `AVAudioSession.routeChangeNotification`."
- The more appropriate direct fix path is:
  - observe `AVAudioEngineConfigurationChangeNotification`
  - observe Core Audio output-device changes on macOS
  - decide, in one place, how an active playback request should recover or fail when those events occur

## Could this be fixed more directly in `SpeakSwiftly`?

Yes, very likely.

The direct fix should live in `SpeakSwiftly` if we want reliable behavior when the actual playback engine loses alignment with macOS audio state. The host can add queue controls and watchdogs, but those are operational safety nets. They are not substitutes for runtime-level device-change handling in the code that owns `AVAudioEngine`.

The smallest credible direct fix shape looks like:

1. Add a native macOS output-device observer.
2. Add an `AVAudioEngineConfigurationChangeNotification` observer.
3. Record explicit structured events when either one fires.
4. When an event lands during active playback, choose one of two clear policies:
   - rebuild the engine and continue if the runtime can do so safely and deterministically
   - fail the active request immediately with a descriptive worker error instead of hanging in repeated rebuffer or drain limbo

Why a clear fail policy matters:

- A clean failure is much easier for the host to recover from than a request that keeps emitting partial playback-side warnings forever.
- Even if we are not ready to implement seamless output-device migration, explicit fail-fast behavior would already be an operational improvement over silent wedging.

## Existing control surfaces already present in `SpeakSwiftly`

This investigation also confirmed that the worker already implements queue-control operations:

- `list_queue`
- `clear_queue`
- `cancel_request`

Relevant code:

- [`Runtime/WorkerProtocol.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Runtime/WorkerProtocol.swift)
- [`Runtime/WorkerRuntime.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift)
- [`Playback/PlaybackOperations.swift`](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/Sources/SpeakSwiftly/Playback/PlaybackOperations.swift)

Interpretation:

- `SpeakSwiftly` already has the beginnings of an operator-recovery story.
- The current host simply does not expose those worker controls yet.
- That is useful, but it should be viewed as separate from the direct runtime fix. Queue controls help us recover after a stall. Route and engine observers help us avoid or explain the stall in the first place.

## Recommended observability to add in `SpeakSwiftly`

The current playback forensics are already useful, but they stop short of the route and hardware state that would help explain this class of failure. The following additions would materially improve diagnosis.

### 1. Route or device snapshots at playback start

Emit a structured event at request start with:

- current default output device identifier
- current default output device human-readable name
- transport type if available
- hardware sample rate
- hardware channel count
- engine running state
- engine output format sample rate and channel count
- whether the engine was freshly rebuilt or reused

Suggested event name:

- `playback_output_snapshot`

### 2. Explicit route or device change events

Emit a structured event whenever the observed output device changes:

- previous device identifier and name
- new device identifier and name
- whether a playback request was active
- active request ID if present
- whether the change was detected by Core Audio device observation, engine configuration observation, or both

Suggested event names:

- `playback_output_device_changed`
- `playback_default_output_changed`

### 3. Explicit engine configuration change events

Emit a structured event when `AVAudioEngineConfigurationChangeNotification` fires:

- active request ID if present
- previous engine format
- new engine format if available
- engine running state before and after handling
- whether the runtime rebuilt the engine
- whether playback resumed or the request failed

Suggested event names:

- `playback_engine_configuration_changed`
- `playback_engine_rebuilt_after_configuration_change`

### 4. Recovery-attempt events

If the runtime tries to recover rather than failing immediately, emit explicit structured attempts and outcomes:

- trigger kind
- request ID
- whether buffers were dropped or preserved
- whether player node was recreated
- whether engine restart succeeded
- elapsed recovery time

Suggested event names:

- `playback_recovery_attempt_started`
- `playback_recovery_attempt_succeeded`
- `playback_recovery_attempt_failed`

### 5. Stall-watchdog events

If repeated rebuffers continue without terminal progress, emit a watchdog event before the request becomes effectively immortal:

- request age
- time since last chunk arrived
- time since last buffer was scheduled
- time since last completion callback
- current queued audio estimate
- rebuffer count so far
- whether device or engine-change signals occurred earlier in the same request

Suggested event name:

- `playback_stall_watchdog_warning`

### 6. Lightweight worker status surface for the host

Expose a compact status payload that the MCP host could query without scraping logs:

- active request summary
- queued request count
- current playback phase
- last known output device
- last route or device change timestamp
- last engine configuration change timestamp
- last recovery attempt result
- current engine running state

This would let the host explain "what the worker thinks is happening" instead of only reporting backlog symptoms.

## Recommended implementation direction

Near-term direction:

- Add native macOS output-device observation and engine-configuration observation inside `PlaybackController` or a tightly adjacent playback-owned type.
- Keep the implementation simple and local to the existing playback subsystem rather than introducing a new manager layer unless a concrete need appears.
- On observed change during active playback, prefer a deterministic path:
  - either rebuild and resume with strong structured logging
  - or fail the active request immediately with a descriptive error

Important architecture caution:

- A new abstraction layer, wrapper, manager, bridge, or coordinator for this should be treated with caution.
- The current evidence points to a missing runtime hook, not to a need for a broad new subsystem.
- A small playback-owned implementation is easier to reason about and easier to verify than a large coordination layer spread across the worker.

## Current best read

The strongest conclusion from this investigation is:

- there is a plausible direct fix path in `SpeakSwiftly`
- it belongs at the native playback-engine layer
- the current runtime lacks the specific device-change and engine-change observability needed to prove or disprove route-switching as the cause of the live-service stall

That makes the next highest-signal work:

1. add output-device and engine-configuration observation
2. emit explicit route and recovery events
3. choose a deterministic recovery-or-fail policy during active playback
4. only then decide whether host-only queue watchdogs are still needed beyond operator convenience
