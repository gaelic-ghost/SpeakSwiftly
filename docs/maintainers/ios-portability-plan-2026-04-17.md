# iOS Portability Plan

Date: 2026-04-17

## Purpose

This note records the current source-level blockers and the recommended
implementation order for making `SpeakSwiftly` a realistic iOS-capable Swift
package.

This is a portability plan, not a claim that the package is already close to
shipping on iOS. The package is still explicitly macOS-only today, and the main
reason is the playback runtime.

## Documented Apple Constraints

These Apple platform rules are the architectural guardrails for the plan:

- `NSWorkspace` is an AppKit type and a macOS environment surface, not an iOS
  API:
  - <https://developer.apple.com/documentation/appkit/nsworkspace>
- `AVAudioRoutingArbiter` exists so macOS apps can participate in AirPods
  Automatic Switching, while iOS apps already participate automatically:
  - <https://developer.apple.com/documentation/avfaudio/avaudioroutingarbiter>
- On iOS, playback apps should configure and activate an `AVAudioSession`
  instead of relying on desktop-style output-device arbitration and workspace
  notifications:
  - <https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback#Configure-the-audio-session>

Those three rules mean the current macOS playback-environment handling cannot be
made portable by sprinkling `#if os(iOS)` around the existing code. The package
needs a narrow platform boundary around playback environment ownership.

## Good News First

The upstream dependency story is not the blocker right now:

- `TextForSpeech` `0.17.2` declares:
  - `.iOS(.v17)`
  - `.macOS(.v14)`
- `mlx-audio-swift` `69.1.5` declares:
  - `.macOS(.v14)`
  - `.iOS(.v17)`

That means the immediate portability pressure is in `SpeakSwiftly` source
organization and playback-environment modeling, not in package-selection churn.

## Hard Blockers In The Current Source Tree

### 1. The package manifest is macOS-only

`Package.swift` currently declares only:

- `.macOS(.v15)`

That is the first hard stop. iOS cannot enter the package graph until the
manifest is widened.

### 2. Playback imports AppKit directly

These files currently import AppKit:

- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver.swift`
- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver+EnvironmentRecovery.swift`

That means the playback target as written cannot compile for iOS.

### 3. Playback recovery is modeled around `NSWorkspace`

`AudioPlaybackDriver+EnvironmentRecovery.swift` currently listens for:

- system sleep and wake
- screen sleep and wake
- session resign-active and become-active

Those are all driven through `NSWorkspace.shared.notificationCenter`, which is a
desktop environment model. iOS does not offer the same lifecycle surface.

### 4. Output-device tracking is modeled around macOS CoreAudio system objects

These files use `AudioObject*` APIs and the default output-device system object:

- `Sources/SpeakSwiftly/Playback/PlaybackConfiguration.swift`
- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver.swift`
- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver+EnvironmentRecovery.swift`

That device-inspection model is tied to macOS output-device ownership. It is
not the iOS route and interruption model.

### 5. Playback startup explicitly assumes macOS routing arbitration

`AudioPlaybackDriver+PlaybackLifecycle.swift` currently begins playback through
`AVAudioRoutingArbiter` and even emits a user-facing error that says:

- `macOS audio routing arbitration`

That path is not the right primitive for iOS playback startup.

### 6. There is no iOS audio-session model in the package yet

The current `Sources/SpeakSwiftly` tree does not contain:

- `AVAudioSession`
- route-change handling
- interruption handling
- iOS-style audio-session activation or category management

So even after removing macOS-only imports, the package would still be missing
the native playback-environment behavior iOS expects.

## What Already Looks Portable

These areas are not the main problem:

- `Storage/ProfileStore.swift` uses
  `FileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)`,
  which is a reasonable sandbox-friendly default for both platforms.
- Normalization, generation, runtime queueing, request observation, and most of
  the typed API surface do not appear to be inherently desktop-only.
- The newest `TextForSpeech` and current `mlx-audio-swift` baselines already
  advertise iOS support, which lowers the risk of starting this work now.

## Recommended Architectural Split

The durable shape is:

1. Keep one platform-neutral playback core.
2. Move platform environment monitoring into a narrow playback-environment
   boundary.
3. Implement one macOS environment adapter and one iOS environment adapter.

In concrete repo terms, that means:

- keep audio buffering, queue draining, chunk scheduling, and playback summary
  logic in the shared playback driver path
- move desktop lifecycle observation out of the main driver type
- stop letting the core playback type own raw `NSWorkspace` and CoreAudio device
  listeners directly
- introduce a narrow protocol or helper boundary for:
  - route preparation
  - route or environment observation
  - interruption or recovery triggers
  - optional platform diagnostics

This should stay a small building-block change, not a new subsystem. The goal
is one explicit platform seam inside playback, not a new manager or coordinator
stack.

## Proposed File-Level Reshape

### Shared files that should remain platform-neutral

- `PlaybackOperations.swift`
- `PlaybackOperations+Events.swift`
- `PlaybackExecutionState.swift`
- `PlaybackSupportModels.swift`
- `PlaybackEvents.swift`
- the queue-drain and scheduling parts of `AudioPlaybackDriver`

### macOS-specific code that should be isolated

- `NSWorkspace` observers
- CoreAudio default-output-device inspection
- CoreAudio output-device change listeners
- `AVAudioRoutingArbiter`

### iOS-specific code that will need to be added

- `AVAudioSession` category selection and activation
- interruption handling
- route-change handling
- any iOS-only app-state coordination that is genuinely required for playback
  recovery

## Concrete Work Order

### Phase 1: Create the playback platform seam

- Extract desktop-only environment observation out of
  `AudioPlaybackDriver.swift` and
  `AudioPlaybackDriver+EnvironmentRecovery.swift`.
- Define the smallest shared boundary that the playback core needs.
- Keep the shared playback driver responsible for playback itself, not for
  learning platform lifecycle semantics.

Exit goal:

- shared playback code compiles without importing AppKit directly
- desktop-specific code lives behind one explicit playback-environment boundary

### Phase 2: Preserve macOS behavior behind the new boundary

- Re-home the existing `NSWorkspace`, CoreAudio output-device, and routing
  arbitration logic into a macOS-specific implementation.
- Keep current macOS recovery behavior working before adding iOS.

Exit goal:

- macOS behavior remains functionally equivalent after the split
- the macOS path proves the seam is real instead of speculative

### Phase 3: Add an iOS playback-environment implementation

- Add an iOS-specific playback environment owner based on `AVAudioSession`.
- Model:
  - audio-session configuration
  - activation
  - interruption handling
  - route-change handling
- Keep the initial iOS path deliberately minimal and honest. It does not need
  to chase macOS feature parity on day one if the underlying lifecycle model is
  different.

Exit goal:

- the library target can compile for iOS
- playback startup and recovery use iOS-native audio-session semantics instead
  of desktop emulation

### Phase 4: Widen the package manifest

- Change `Package.swift` from macOS-only to:
  - `.macOS(.v15)`
  - `.iOS(.v17)`
- Re-check whether `SpeakSwiftlyTool` should remain part of the same package
  surface unchanged or whether it needs an explicit macOS-only posture in docs
  and validation.

Exit goal:

- SwiftPM can resolve the library for iOS consumers without lying about
  supported platforms

### Phase 5: Add platform-aware validation lanes

- Keep the current macOS Xcode-backed lane for release-grade MLX coverage.
- Add an iOS compile-and-smoke lane focused on:
  - package resolution
  - iOS target compilation
  - playback-environment compile coverage
- Do not block early iOS architecture work on full real-model simulator or
  device automation until the playback seam is in place.

Exit goal:

- maintainers can tell whether a regression is:
  - shared playback logic
  - macOS environment glue
  - iOS environment glue

## What Not To Do

- Do not try to make `NSWorkspace` or CoreAudio output-device code
  conditionally portable with scattered `#if os(iOS)` checks.
- Do not bury platform differences inside `AudioPlaybackDriver` until it becomes
  a giant platform switchboard.
- Do not start by adding a new cross-cutting playback manager or coordinator.
- Do not widen the package manifest to iOS before the playback seam exists,
  because that will turn the package into a compile-failure magnet.

## Suggested First Slice

The best first implementation slice is:

1. isolate `NSWorkspace`, CoreAudio device inspection, and routing arbitration
   from `AudioPlaybackDriver`
2. keep current macOS behavior intact behind that seam
3. only then add the first iOS `AVAudioSession` implementation

That slice earns its complexity immediately because it removes the real source
blockers without forcing the package into an iOS-ready claim before the playback
runtime can actually support it.
