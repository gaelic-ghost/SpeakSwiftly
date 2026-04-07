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

- add a runtime config toggle such as `speechBackend = qwen3 | marvis`
- branch inside resident-model loading
- continue storing only the current single reference audio/transcript pair

That path is not enough for the use cases we can already see:

- the current profile creation flow is explicitly Qwen-shaped
- backend-specific routing rules would leak into runtime generation paths
- callers would believe profiles are portable when the implementation would still be relying on one backend's assumptions

If we want backend switching to feel real and stable, the profile system itself has to widen intentionally around stable profile metadata, not just around a config switch.

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

It does not force us to choose between built-in voices and caller-provided conditioning, but it does give us a smaller and cleaner first implementation option than Qwen does.

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
- `SpeakSwiftly` can route Marvis requests by profile metadata without pretending the profile store contains Marvis-specific cloned assets yet

## Core Conclusion

Marvis is different from Qwen3, but not so different that it requires a totally separate public profile API.

The real difference is:

- Qwen3 profile creation is already the native stored-conditioning path
- Marvis can start cleanly as a built-in preset routing path
- both backends still want one stable caller-facing profile identity

So the right direction is:

- keep one public logical profile system
- add required profile metadata that is portable across backends
- let runtime generation select the right backend behavior for the currently active backend

## Target Model

### Public API Goal

The public API should remain conceptually stable:

- `createProfile(named:from:vibe:voice:...)`
- `createClone(named:from:vibe:transcript:...)`
- `profiles()`
- `removeProfile(named:...)`
- `speak(..., using: profileName, ...)`
- `queue_speech_file(..., using: profileName, ...)`

Callers should not need to know:

- which backend generated the stored assets
- whether Marvis and Qwen share the same preparation internals
- which Marvis preset voice a given vibe maps to

### Internal Model Goal

One logical profile should stay the stable user-facing identity, but it now needs portable profile metadata that backend dispatch can trust.

At a high level:

- logical profile:
  stable user-facing identity such as `meeting-voice`
- portable profile metadata:
  required `vibe`, source text, and voice description
- backend behavior:
  Qwen uses stored conditioning assets, while Marvis routes to a built-in resident preset based on `vibe`

## Proposed Storage Shape

### Logical Profile Manifest

The top-level logical profile should keep stable user-facing metadata:

- `version`
- `profileName`
- `createdAt`
- `sourceKind`
- `vibe`
- `voiceDescription`
- `sourceText`
- `backendMaterializations`

`sourceKind` should distinguish at least:

- generated profile
- imported clone

### Backend Materialization Record

Each backend record should describe:

- backend identifier
- backend model repo or preset family
- created-at timestamp
- reference transcript
- reference audio file path
- optional backend-specific metadata

For the current implementation, only Qwen needs a stored backend materialization record.

Marvis does not need per-profile stored assets in this pass because resident requests route to built-in preset voices by `vibe`.

## Backend Behavior Model

### Qwen3

Qwen3 should keep the current behavior conceptually:

- use stored `refAudio`
- use stored `refText`
- generate speech using the active Qwen3 resident model

### Marvis

Marvis should use one stable routing rule in this pass:

- preload both `conversational_a` and `conversational_b`
- route `.femme` and `.androgenous` profiles to `conversational_a`
- route `.masc` profiles to `conversational_b`

That lets `SpeakSwiftly` preserve the same caller mental model:

- create one profile
- switch backend
- keep using the same profile name

without pretending that per-profile Marvis conditioning assets already exist.

## Recommended Direction

Use one logical profile API with required `vibe`, but only store Qwen conditioning artifacts in this pass.

That means:

- `createProfile` should require `vibe` and store that in the logical profile manifest
- `createClone` should require `vibe` and store that in the logical profile manifest
- `createProfile` and `createClone` should continue producing the canonical Qwen-ready reference assets
- Marvis should route from stored `vibe` to a preloaded built-in resident preset at request time

This gives the cleanest first implementation of the public API promise:

- callers create one profile shape
- backend switching is real and immediate
- Marvis stays simple enough to keep both presets warm at once
- future automated analysis can widen profile preparation later without changing the public API again

## Simpler Alternative Considered

The main simpler alternative is no profile widening at all:

- keep existing profile metadata
- expose only backend switching
- force callers to guess Marvis routing or accept hard-coded defaults

That path should be rejected because it would make Marvis behavior implicit and would not give us a stable public contract for future analysis or backend-aware preparation work.

## Runtime Architecture

This should stay a straight, unidirectional model.

### New Internal Responsibilities

We likely need three coherent pieces:

- backend selection model
- portable profile metadata with required `vibe`
- backend-specific generation logic

The goal is not to add wrappers for their own sake.

The goal is to keep backend-specific behavior from leaking everywhere.

### Suggested File Shape

- `Sources/SpeakSwiftly/Generation/SpeechBackend.swift`
- `Sources/SpeakSwiftly/API/Vibe.swift`
- `Sources/SpeakSwiftly/Generation/QwenSpeechGeneration.swift`
- `Sources/SpeakSwiftly/Generation/MarvisSpeechGeneration.swift`

This change would unlock real near-term use cases:

- switch resident backend without rewriting caller-facing API
- keep file-generation and live-playback paths sharing the same backend dispatch model
- add future backends without re-entangling profile storage

The simpler path considered first was a few config conditionals inside `ModelClients.swift` and `FileGenerationOperations.swift`. That path should be rejected because it would spread backend differences across profile creation, file generation, live playback, and profile reads instead of giving those differences one home.

## Concrete Implementation Plan

### Phase 1: Narrow the backend model

1. Keep resident backend selection to two cases only:
   - `qwen3`
   - `marvis`
2. Do not expose `marvis-a` or `marvis-b` as top-level backend choices.
3. Keep Marvis preset selection as an internal routing rule.

Exit criteria:

- one runtime selection point decides the active backend
- `SpeakSwiftly` no longer assumes resident generation is always Qwen3
- public backend configuration stays small and durable

### Phase 2: Widen the profile store around `vibe`

1. Add a required `Vibe` enum to logical profile metadata:
   - `.masc`
   - `.femme`
   - `.androgenous`
2. Add migration logic from older manifests into the widened format.
3. Preserve backward compatibility for already-created profiles on disk by upgrading them during load.

Exit criteria:

- existing profiles still load
- profile reads return one logical profile view with `vibe`
- `createProfile` and `createClone` require `vibe`

### Phase 3: Keep Qwen materialization, not dual backend materialization

1. Continue storing canonical Qwen-ready reference assets for generated and cloned profiles.
2. Do not create per-profile Marvis materializations in this pass.
3. Keep enough metadata that a future analysis pipeline can widen preparation later without changing the caller-facing API again.

Exit criteria:

- new profiles are ready for Qwen immediately
- profile creation does not pretend Marvis has stored per-profile artifacts yet

### Phase 4: Split backend generation paths and Marvis routing

1. Move Qwen-specific speech generation into its own generation file.
2. Keep Marvis-specific generation in its own generation file.
3. Warm both Marvis preset voices at resident startup.
4. Route Marvis requests by stored `vibe`.
5. Keep file generation and live generation sharing the same backend dispatch primitive.

Exit criteria:

- backend-specific request shaping is no longer in one mixed file
- Marvis routing is explicit and deterministic
- profile selection logic remains shared and straightforward

### Phase 5: Surface operator-facing backend details

1. Extend status and profile-list responses so operators can inspect:
   - active backend
   - stored profile `vibe`
2. Document how built-in Marvis presets differ from user-created profiles.
3. Document the current routing rule:
   - `.femme` -> `conversational_a`
   - `.androgenous` -> `conversational_a`
   - `.masc` -> `conversational_b`

Exit criteria:

- backend switching is transparent to operators
- profile inspection reflects the metadata that actually drives runtime routing

## Open Decisions

### Should profile creation generate separate Marvis conditioning assets now?

No.

Reasons:

- the current Marvis routing model does not need them
- we do not yet have the automated analysis pass Gale already expects to add later
- forcing guessed Marvis-specific excerpts now would add complexity without improving the current resident path

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
- no premature per-profile Marvis conditioning-asset generation without the later analysis pipeline

## Recommended Next Step

Implement the model widening in this order:

1. internal backend enum and config
2. widened profile manifest with required `vibe` and migration
3. Marvis dual-preset resident warmup plus vibe-based routing
4. backend-specific generation files

That keeps the public story honest from the first real implementation pass:

- one profile system
- one caller-facing API
- backend-specific internals where they belong
- backend switching that actually works instead of only appearing configurable
