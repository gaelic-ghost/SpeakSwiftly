# Marvis vs Qwen Clone Conditioning Plan

Date: 2026-04-07

## Why this exists

This is a durable building-block planning note, not a local implementation detail.

The near-term use case it unlocks is reliable multi-backend profile reuse in `SpeakSwiftly`: one logical profile API for callers, with enough backend-aware conditioning detail underneath that `qwen3` and `marvis` can both sound intentional instead of "technically wired up but accidentally under-conditioned."

The simpler path considered first was: keep using the same full `refAudio` and full `refText` for both backends forever and do nothing else. That path is tempting because the current wrappers accept the same top-level inputs, but it is too hand-wavy. The official Qwen docs and the official Marvis docs point at different cloning assumptions, so we should make that difference explicit before we ossify the profile model further.

## Sources

Official and primary sources consulted:

- Qwen GitHub: https://github.com/QwenLM/Qwen3-TTS
- Qwen 0.6B Base model card: https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base
- Marvis GitHub: https://github.com/Marvis-Labs/marvis-tts
- Marvis HF blog article: https://huggingface.co/blog/prince-canuma/introducing-marvis-tts

Local implementation source consulted:

- `mlx-audio-swift` pinned in this repository at `v0.1.2`
- Marvis prompt assets from the published model:
  - `https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.2/resolve/main/prompts/conversational_a.txt`
  - `https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.2/resolve/main/prompts/conversational_b.txt`

## Findings

### 1. Qwen's public cloning contract is explicit

The official Qwen docs are clear:

- the 0.6B Base model supports "3-second rapid voice clone from user audio input"
- the normal voice-clone path expects both `ref_audio` and `ref_text`
- `ref_text` can be omitted only in `x_vector_only_mode`, and the docs explicitly say quality may be reduced
- the official package also exposes a reusable `voice_clone_prompt` path for repeated generations

Relevant lines:

- Qwen GitHub README says the Base models are "capable of 3-second rapid voice clone from user audio input"
- Qwen GitHub README says voice clone requires `ref_audio` and `ref_text`, with optional `x_vector_only_mode=True` at reduced quality
- the 0.6B Base model card shows the same `ref_audio` + `ref_text` pattern in its quickstart example

### 2. Marvis public docs are partially inconsistent, but still point to audio-plus-context cloning

The public Marvis sources are not perfectly aligned with each other:

- the Marvis GitHub repo says the model enables voice cloning with "just 10 seconds of reference audio"
- the Marvis HF blog also says cloning quality depends on "the 10-second reference audio"
- the same HF blog's "Getting Started" section says advanced voice-cloning features are "coming soon to MLX and Transformers after we release the base model"

So the public messaging is inconsistent about *how exposed* voice cloning is in the released stacks, but not about the higher-level conditioning story: Marvis is still framed around a longer reference-audio prompt than Qwen.

### 3. The current `mlx-audio-swift` Marvis wrapper already accepts `refAudio` + `refText`

This is the most important implementation finding.

In the pinned `mlx-audio-swift` checkout, `MarvisTTSModel` already supports either:

- a built-in voice preset such as `conversational_a` / `conversational_b`, or
- caller-supplied `refAudio` + `refText`

When the caller supplies `refAudio` and `refText`, the wrapper builds:

- `Segment(speaker: 0, text: refText, audio: refAudio)`

When the caller uses a built-in preset instead, the wrapper:

- loads a packaged `.wav`
- loads the matching packaged `.txt`
- then builds the same kind of `Segment`

That means Marvis is not "preset-only" in the current Swift path. It already has the same top-level conditioning *shape* as Qwen from SpeakSwiftly's point of view: audio plus matching transcript text.

### 4. `conversational_a` vs `conversational_b` does not imply a different profile schema

In the current `mlx-audio-swift` Marvis implementation:

- `conversational_a` and `conversational_b` are voice enum cases
- the wrapper resolves each one to a packaged `.wav` prompt and matching `.txt` transcript
- the code path after that is the same

But they are not arbitrary duplicates either.

The Marvis authors describe them as two different expressive English presets:

- `conversational_a` for female
- `conversational_b` for male

The published prompt assets back that up:

- both presets use the same transcript text
- both presets are about the same length, roughly `13.25` seconds at `24 kHz`
- the difference therefore lives in the reference audio identity and delivery, not in the transcript or in a different schema

So these presets do not imply different user-profile schemas. They are backend-owned built-in prompt assets that encode different English voice identities and performances, not a reason to fork SpeakSwiftly's public profile API.

### 5. Qwen and Marvis differ more in conditioning preference than in top-level API shape

This is the practical summary:

- Qwen public docs optimize around very short clone prompts, around 3 seconds
- Marvis public docs optimize around longer prompts, around 10 seconds
- both current Swift-callable paths still fundamentally want `refAudio` + matching `refText` for best-quality custom conditioning

So the real divergence is not "Qwen needs transcript but Marvis does not." The real divergence is that they appear to want different *conditioning window sizes and preparation strategies*.

## Implications for SpeakSwiftly

### What we should not conclude

We should **not** conclude that SpeakSwiftly needs two public profile APIs.

The findings do not justify:

- `QwenProfile`
- `MarvisProfile`
- separate caller-facing profile creation commands
- separate caller-facing clone import commands

That would be unnecessary architectural drift. One logical profile API still makes sense.

### What we should conclude

We should conclude that one logical profile may eventually need multiple backend-specific conditioning materializations beneath it.

That is already compatible with the direction we started:

- one logical profile
- backend-specific materializations under the hood

The open question is not whether backend-specific materializations are valid. They are. The open question is **how much preprocessing we can safely do today** without inventing fake transcript/audio alignment.

## Recommendation

### Short answer

Do **not** rush into generating different clipped `refAudio` and clipped `refText` pairs for Qwen and Marvis yet.

### Why not

Right now SpeakSwiftly stores:

- one canonical reference audio asset
- one transcript string

But it does **not** yet have forced alignment or word timing data.

That means if we try to create:

- a "Qwen 3-second clip"
- a "Marvis 10-second clip"

we immediately run into a hard correctness problem:

- how do we know which exact substring of `refText` matches the clipped audio span?

For imported clones with caller-supplied audio, and for generated profiles from VoiceDesign text, naive waveform slicing without text alignment could create mismatched audio/text pairs. That is worse than using the full aligned source pair we already have.

## Recommended plan

### Phase 1: keep the current shared conditioning pair, but make the policy explicit

Keep using:

- canonical `refAudio`
- canonical `refText`

for both backends for now.

For caller-provided clone imports, document `around 10 seconds` of clear source audio as the target profile-input length. That should be our stable operator-facing recommendation unless upstream guidance changes.

But make the backend policy explicit in the materialization model:

- add a backend conditioning policy field such as `preferred_conditioning_strategy`
- record intended target prompt length or prompt style per backend
- record whether the current materialization is `canonical_full_reference` or a backend-optimized excerpt

This keeps the public profile API stable while making backend differences visible and inspectable.

### Phase 2: add readiness and quality diagnostics before changing assets

Add operator-visible diagnostics for backend/profile fit, for example:

- Qwen profile conditioning is longer than the backend's documented rapid-clone prompt size, using canonical full reference for now
- Marvis profile conditioning is shorter than the backend's documented 10-second target, cloning quality may be reduced

This gives us evidence and observability without inventing bad derived assets.

### Phase 3: only generate backend-specific excerpts after we have transcript alignment

Once SpeakSwiftly can reliably align transcript spans to audio spans, then we should generate backend-specific materializations at profile-creation time:

- Qwen materialization:
  - short excerpt
  - matching short transcript span
  - later possibly cached reusable clone-prompt representation if upstream Swift wrappers expose it cleanly
- Marvis materialization:
  - longer excerpt
  - matching longer transcript span
  - optional fallback to canonical full prompt when source material is too short

That is the right time to truly diverge per-backend prompt assets.

## Concrete implementation plan

### Step 1

Extend `ProfileMaterializationManifest` with policy metadata only, not new derived assets yet.

Suggested fields:

- `conditioningStrategy`
- `conditioningDurationMS`
- `usesCanonicalReference`
- `qualityNotes` or `warnings`

### Step 2

Keep the current stored files as they are:

- one canonical `reference.wav`
- one transcript string

Both backends continue reading those for now.

### Step 3

At runtime, surface backend-specific warnings when the canonical reference is likely suboptimal.

Examples:

- Marvis running on a profile with less than ~10 seconds of source audio
- future Qwen prompt path running on an overly long canonical reference when a shorter prompt would likely be better

### Step 4

Defer true backend-specific asset generation until we can produce transcript-aligned excerpts, either by:

- forced alignment
- token/time alignment from the generation/import path
- or a documented upstream helper that can build reusable backend-native prompt objects directly from the full reference pair

## Decision

The current evidence says:

- SpeakSwiftly does **not** need separate public profile APIs for Qwen vs Marvis
- SpeakSwiftly **does** need backend-aware conditioning policy under one profile model
- SpeakSwiftly should **not yet** synthesize separate clipped `refAudio` / `refText` assets for the two backends without alignment support

So the next good implementation move is:

1. keep one public profile API
2. keep one canonical source pair
3. add backend conditioning policy metadata and warnings
4. postpone true per-backend prompt asset derivation until alignment exists
