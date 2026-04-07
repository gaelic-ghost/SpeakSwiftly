# Multi-Backend Profile Plan

## Why This Exists

This is a durable building-block change, not a local config tweak.

`SpeakSwiftly` currently assumes one logical voice profile maps to one stored reference artifact set:

- one manifest
- one reference audio file
- one reference transcript
- one active resident speech backend family

That model was sufficient while the package only targeted the current Qwen3-based generation path. It stops composing cleanly once we want this near-term use case:

- keep one stable public `profileName`
- let callers switch the active speech backend
- keep the same `createProfile`, `createClone`, `speak`, `queue_speech_file`, and profile-listing APIs
- have the selected backend use a backend-appropriate materialization of that logical profile without making callers rebuild profiles manually per model

The simpler extension path considered first was:

- add a runtime config toggle such as `speechModel = qwen3 | marvis-a | marvis-b`
- branch inside resident-model loading
- continue storing only the current single reference audio/transcript pair

That path is not enough for the use cases we can already see:

- the profile store would still only capture one backend's prepared assets
- the current profile creation flow is explicitly Qwen-shaped
- backend-specific requirements would leak into runtime generation paths
- callers would believe profiles are portable when the implementation would still be relying on one backend's assumptions

If we want backend switching to feel real and stable, the profile system itself has to widen intentionally.

## Research Summary

### Qwen3-TTS

Official sources:

- GitHub: <https://github.com/QwenLM/Qwen3-TTS>
- Hugging Face model card: <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base>

The official Qwen3 base model docs explicitly center voice cloning from user-provided `ref_audio` plus `ref_text`.

That is already very close to `SpeakSwiftly`'s current profile model:

- store a reference audio sample
- store the matching transcript
- reuse those for subsequent synthesis requests

So the existing profile system is naturally aligned with Qwen3.

### Marvis

Official sources:

- GitHub: <https://github.com/Marvis-Labs/marvis-tts>
- Hugging Face model card: <https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.2>

The official Marvis model card describes:

- real-time streaming TTS
- voice cloning from caller-provided reference audio
- operation on consumer devices

The `mlx-audio-swift` Marvis implementation shows two valid prompt modes:

- built-in prompt voices such as `conversational_a` and `conversational_b`
- caller-provided `refAudio` plus `refText`

That means Marvis is not fundamentally profile-hostile.

It does not force us to choose between:

- built-in voice presets only
- user-defined SpeakSwiftly profiles only

It supports both.

### Marvis `conversational_a` vs `conversational_b`

The current `mlx-audio-swift` Marvis implementation exposes:

- `conversational_a`
- `conversational_b`

Both built-in prompts currently appear to use the same companion transcript text, while the prompt audio differs by file.

That strongly suggests the meaningful distinction is:

- different built-in speaker identity
- not a different prompt schema
- not a different profile format

So `conversational_a` and `conversational_b` do not imply two different profile-storage formats.

They imply two built-in speaker presets.

That distinction matters for `SpeakSwiftly`:

- built-in Marvis voices should be modeled as backend voice presets
- user-created logical profiles should remain separate from those presets

If a caller chooses a user-created logical profile while using Marvis, the runtime should prefer the stored Marvis profile materialization instead of silently swapping to `conversational_a` or `conversational_b`.

## Core Conclusion

Marvis is different from Qwen3, but not so different that it requires a totally separate public profile API.

The real difference is:

- Qwen3 profile creation is already the native path
- Marvis also supports backend-native built-in voices
- Marvis profile preparation may need a backend-specific materialization step if we want user-created profiles to behave consistently there

So the right direction is:

- keep one public logical profile system
- store backend-specific profile materializations under each logical profile
- let runtime generation select the right materialization for the currently active backend

## Target Model

### Public API Goal

The public API should remain conceptually stable:

- `createProfile(named:from:voice:...)`
- `createClone(named:from:transcript:...)`
- `profiles()`
- `removeProfile(named:...)`
- `speak(..., using: profileName, ...)`
- `queue_speech_file(..., using: profileName, ...)`

Callers should not need to know:

- which backend generated the stored assets
- whether Marvis and Qwen share the same preparation internals
- whether a profile has one or several backend-specific stored artifacts

### Internal Model Goal

One logical profile should become a container for backend-specific materializations.

At a high level:

- logical profile:
  stable user-facing identity such as `meeting-voice`
- backend materialization:
  the stored assets that a specific backend needs in order to synthesize speech from that logical profile

That means the profile store should move from:

- one manifest + one audio file

to:

- one logical profile manifest
- one or more backend materialization records
- backend-specific stored artifacts where necessary

## Proposed Storage Shape

### Logical Profile Manifest

The top-level logical profile should keep stable user-facing metadata:

- `version`
- `profileName`
- `createdAt`
- `sourceKind`
- `voiceDescription`
- `sourceText`
- `backendMaterializations`

`sourceKind` should distinguish at least:

- generated profile
- imported clone

### Backend Materialization Record

Each backend record should describe:

- backend identifier
- backend model repo or preset
- created-at timestamp
- reference transcript
- reference audio file path
- optional backend-specific metadata

The likely first backend identifiers are:

- `qwen3`
- `marvis`

If Marvis later needs distinct runtime families that genuinely diverge in preparation requirements, we can still keep those under one Marvis backend record with metadata, or split them later if the distinction becomes structural.

We should not start by modeling `conversational_a` and `conversational_b` as separate profile backends, because they are built-in voice presets, not separate profile formats.

## Backend Behavior Model

### Qwen3

Qwen3 should keep the current behavior conceptually:

- use stored `refAudio`
- use stored `refText`
- generate speech using the active Qwen3 resident model

The main change is that Qwen3 assets become one backend materialization under the logical profile instead of the entire profile.

### Marvis

Marvis should support two modes:

- built-in preset mode for explicit backend preset voices
- user-profile mode for logical SpeakSwiftly profiles

For user-profile mode, Marvis should use a stored Marvis backend materialization:

- `refAudio`
- `refText`

That lets `SpeakSwiftly` preserve the same caller mental model:

- create one profile
- switch backend
- keep using the same profile name

### Built-In Marvis Voice Presets

`conversational_a` and `conversational_b` should be treated as backend options, not as generated profiles.

Those presets should likely live in backend configuration, not inside the user profile store.

That avoids muddling two different concepts:

- a user-owned reusable logical profile
- a built-in vendor-defined voice preset

## Recommended Direction

Create all applicable backend materializations at profile-creation time.

That means:

- `createProfile` should generate Qwen3 and Marvis materializations in the same operation
- `createClone` should import and persist Qwen3 and Marvis materializations in the same operation

This gives the most honest implementation of the public API promise:

- the profile exists for the supported backend set as soon as creation succeeds
- switching backends later does not trigger surprising first-use preparation work
- listing profiles can report readiness directly

This also makes error handling more concrete:

- either the profile is fully prepared for supported backends
- or creation can report which backend materializations failed

## Simpler Alternative Considered

The main simpler alternative is lazy backend materialization:

- store one canonical profile source
- derive Marvis or Qwen-specific materializations only when a request first targets that backend

That path is attractive for implementation effort, but it weakens operator expectations:

- first request on a new backend may have surprising latency
- backend-readiness becomes request-time state instead of profile state
- failure handling moves into generation paths instead of staying in profile preparation

Because backend switching is one of the main reasons to do this work at all, eager materialization is the cleaner first implementation.

## Runtime Architecture

This should stay a straight, unidirectional model.

### New Internal Responsibilities

We likely need three coherent pieces:

- backend selection model
- backend-specific profile materialization logic
- backend-specific generation logic

The goal is not to add wrappers for their own sake.

The goal is to keep backend-specific behavior from leaking everywhere.

### Suggested File Shape

- `Sources/SpeakSwiftly/Generation/SpeechBackend.swift`
- `Sources/SpeakSwiftly/Generation/SpeechBackendProfileMaterialization.swift`
- `Sources/SpeakSwiftly/Generation/QwenSpeechGeneration.swift`
- `Sources/SpeakSwiftly/Generation/MarvisSpeechGeneration.swift`

This change would unlock real near-term use cases:

- switch resident backend without rewriting caller-facing API
- keep file-generation and live-playback paths sharing the same backend dispatch model
- add future backends without re-entangling profile storage

The simpler path considered first was a few config conditionals inside `ModelClients.swift` and `FileGenerationOperations.swift`. That path should be rejected because it would spread backend differences across profile creation, file generation, live playback, and profile reads instead of giving those differences one home.

## Concrete Implementation Plan

### Phase 1: Design the backend model

1. Add an internal `SpeechBackend` enum for the supported switchable resident backends.
2. Add backend configuration that can distinguish:
   - active backend family
   - optional built-in backend preset voice where relevant
3. Keep the public request surface stable in this phase.

Exit criteria:

- one runtime selection point decides the active backend
- `SpeakSwiftly` no longer assumes resident generation is always Qwen3

### Phase 2: Expand the profile store

1. Replace the current single-backend manifest shape with a logical profile plus backend materializations.
2. Add migration logic from the current manifest format into the widened profile format.
3. Preserve backward compatibility for already-created profiles on disk by upgrading them during load.

Exit criteria:

- existing profiles still load
- profile reads return one logical profile view
- internal storage can represent backend-specific assets

### Phase 3: Expand profile creation and clone import

1. Update `createProfile` so it generates all supported backend materializations.
2. Update `createClone` so it imports and stores all supported backend materializations.
3. Report backend readiness clearly in completion payloads and logs.

Exit criteria:

- new profiles are ready for both Qwen3 and Marvis
- profile creation no longer bakes in one backend's assumptions as the only stored truth

### Phase 4: Split backend generation paths

1. Move Qwen-specific speech generation into its own generation file.
2. Add Marvis-specific speech generation in its own generation file.
3. Dispatch from the shared runtime generation path based on `SpeechBackend`.
4. Keep file generation and live generation sharing the same backend dispatch primitive.

Exit criteria:

- backend-specific request shaping is no longer in one mixed file
- profile selection logic remains shared and straightforward

### Phase 5: Surface operator-facing backend details

1. Extend status and profile-list responses so operators can inspect:
   - active backend
   - backend readiness per profile
   - backend-specific failures if any
2. Document how built-in Marvis presets differ from user-created profiles.

Exit criteria:

- backend switching is transparent to operators
- profile inspection reflects real readiness

## Open Decisions

### Should profile creation fail hard if one backend materialization fails?

The cleanest default is probably yes.

Reasons:

- a logical profile should mean "ready for the supported backend set"
- partial readiness would be surprising if backend switching is advertised as seamless

If partial success becomes necessary later, it should be explicit in the profile state and not silently accepted.

### Should built-in Marvis presets appear in `profiles()`?

Probably no.

They are backend-owned presets, not user-created logical profiles.

If we want to surface them later, they should likely appear in a separate backend-capabilities read instead of being mixed into the profile namespace.

### Should we widen profile creation to more backends immediately?

No.

The first supported multi-backend set should stay small:

- Qwen3
- Marvis

That keeps the widening intentional without turning it into speculative genericity.

## Non-Goals For This Pass

- no public API expansion just to expose backend internals immediately
- no new queue or subsystem for backend preparation jobs
- no built-in-preset-as-profile compatibility shim
- no attempt to support every `mlx-audio-swift` TTS backend in the first pass

## Recommended Next Step

Implement the model widening in this order:

1. internal backend enum and config
2. widened profile manifest and migration
3. multi-backend profile creation/import
4. backend-specific generation files

That keeps the public story honest from the first real implementation pass:

- one profile system
- one caller-facing API
- backend-specific internals where they belong
- backend switching that actually works instead of only appearing configurable
