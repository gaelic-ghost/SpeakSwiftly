# Worker Runtime Split Plan

## Why This Exists

This is a durable building-block change, not a cosmetic file shuffle.

`Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift` has grown into a 2,300+ line actor file that currently mixes:

- actor-owned state and construction
- stdin request decoding and dispatch
- public library-facing API
- text profile editing
- voice profile creation
- clone profile creation
- queue and playback orchestration
- request completion and stream emission
- stderr logging and playback trace emission

That size is now hurting the near-term use cases we already have:

- adding new request lanes such as `createClone`
- extending text-profile editing without re-reading unrelated playback code
- evolving batch generation later without making the runtime file even denser
- debugging lifecycle or emission behavior without scanning profile and playback helpers

The simpler extension path considered first was to keep one file and keep adding more `// MARK:` sections. That was reasonable when the runtime file was still mostly one subsystem. It is no longer enough now that the file holds several broad responsibilities that change for different reasons.

## Current State

The top-level source layout is already moving in the right direction:

- `Sources/SpeakSwiftly/Generation`
- `Sources/SpeakSwiftly/Playback`
- `Sources/SpeakSwiftly/Runtime`

The remaining issue is inside `Runtime/`, where `WorkerRuntime.swift` was still acting like a mini-subsystem when this plan was written.

That specific normalization concern has now been resolved:

- `Sources/SpeakSwiftly/Normalization/TextNormalizer.swift` now owns `SpeakSwiftly.Normalizer`
- the public text-normalization API now lives in `Sources/SpeakSwiftly/API/TextNormalization.swift`

Playback also widened from a simple engine wrapper into a real feature-owned subsystem during the same cleanup arc:

- `Sources/SpeakSwiftly/Playback/PlaybackController.swift` now owns playback queue state and active playback coordination
- `Sources/SpeakSwiftly/Playback/PlaybackOperations.swift` now owns the playback-facing runtime bridge code that used to live in `Runtime/`

## Split Goal

Keep one actor, one ownership boundary, and one straight request/data flow.

Do not add a new runtime wrapper, manager, bridge, or coordinator just to make the file smaller.

The runtime should stay a single `SpeakSwiftly.Runtime` actor. The split is about moving coherent responsibilities into neighboring files via extensions, not creating new layers.

## Target Shape

### Keep In `WorkerRuntime.swift`

This file should become the runtime composition root:

- nested support types
- stored properties
- init and `live()`
- status subscription setup
- stdin `accept(line:)`
- top-level request dispatch
- generation loop and queue-processing core

### Move To `WorkerRuntime+PublicAPI.swift`

Public library-facing API that Gale or a package consumer reaches for directly:

- `speak`
- text-profile getters and editing methods
- `createProfile`
- `createClone`
- `profiles`
- `removeProfile`
- queue and playback control methods
- `shutdown`

This is the safest first extraction because it is broad but mechanically separable and gives the runtime file a clearer shape immediately.

### Move To `WorkerRuntime+Emission.swift`

Request completion, stream/event emission, queue summaries, playback trace logging, and stderr log helpers:

- request completion helpers
- request stream continuation helpers
- status broadcasting
- playback event logging
- playback finished forensic logging
- JSONL stdout emission
- stderr structured logging
- elapsed-time and best-effort ID helpers

This is the next safest extraction because it is cohesive and mostly orthogonal to request decoding and generation processing.

## Access Control Guidance

The first split will require some runtime implementation details to move from file-private privacy to module-internal visibility so extension files can access the same actor state.

That is acceptable here because:

- the target remains `SpeakSwiftly`
- the actor still owns all mutation
- we are not widening the public API
- the change removes pressure to invent wrapper types purely to preserve file-local privacy

The rule for this pass is:

- preserve `public` exactly where the package surface requires it
- prefer default internal visibility for actor implementation details shared across runtime extension files
- keep nested helper types and properties as narrow as possible without fighting the file split

## Phase 1 Of The Split

This first implementation pass should:

1. add this maintainer note
2. extract the public API surface into `WorkerRuntime+PublicAPI.swift`
3. extract emission and logging helpers into `WorkerRuntime+Emission.swift`
4. keep the processing core in `WorkerRuntime.swift`
5. run `swift build`
6. run `swift test`

### Exit Criteria

- `WorkerRuntime.swift` is materially smaller and easier to scan
- the runtime still has one actor and one ownership boundary
- no new wrapper layers or transitional compatibility shims exist
- `swift build` passes
- `swift test` passes

## Follow-On Split Candidates

Once the first pass lands cleanly, the next likely candidates were:

- `WorkerRuntime+VoiceProfiles.swift`
- playback queue ownership in a real playback-owned type
- `WorkerRuntime+SpeechJobs.swift`

Those should happen only if the first pass still leaves clear responsibility clusters that are painful to maintain together.

## What Landed

This note started as a forward-looking split plan, but the key structural moves have now landed:

- public library-facing runtime API moved into `Sources/SpeakSwiftly/API`
- text-normalization API and logic moved out of `Runtime/`
- voice-profile logic moved into `Sources/SpeakSwiftly/Generation`
- playback queue ownership moved into a real `PlaybackController` actor in `Sources/SpeakSwiftly/Playback`
- playback runtime bridge code moved into `Sources/SpeakSwiftly/Playback/PlaybackOperations.swift`

The runtime is still an important actor boundary, but it is no longer carrying the public API surface or playback queue ownership directly.

## Non-Goals For This Pass

- no playback architecture changes
- no batching work yet
- no text-profile model changes
- no worker protocol redesign
- no new top-level runtime subsystem types

The goal is to clarify the existing runtime, not to widen its architecture again.
