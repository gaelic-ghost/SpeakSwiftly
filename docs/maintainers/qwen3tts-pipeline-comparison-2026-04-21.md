# Qwen3-TTS Pipeline Comparison

Date: 2026-04-21

## Purpose

This note compares three different Qwen3-TTS surfaces so we can see where the
current `SpeakSwiftly` stack matches upstream intent, where `mlx-audio-swift`
adapts the model shape for Swift/MLX, and where either layer diverges in ways
that may affect quality, latency, reproducibility, or maintenance risk.

Surfaces compared:

- official Qwen3-TTS repo and checkpoint usage guidance
- local `mlx-audio-swift` fork at `d82ad715` on `tests/qwen3tts-decay-repro`
- local `SpeakSwiftly` standalone package

Primary upstream sources:

- [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS)
- [Qwen/Qwen3-TTS-12Hz-0.6B-Base](https://hf.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base)
- [Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign](https://hf.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign)
- [Qwen/Qwen3-TTS-Tokenizer-12Hz](https://hf.co/Qwen/Qwen3-TTS-Tokenizer-12Hz)

Key local code anchors:

- [Sources/SpeakSwiftly/Generation/FileGenerationOperations.swift](../../Sources/SpeakSwiftly/Generation/FileGenerationOperations.swift)
- [Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift](../../Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift)
- [Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift](../../Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift)
- [Sources/SpeakSwiftly/Generation/ModelClients.swift](../../Sources/SpeakSwiftly/Generation/ModelClients.swift)
- [gaelic-ghost/mlx-audio-swift Qwen3TTS.swift](https://github.com/gaelic-ghost/mlx-audio-swift/blob/d82ad715fd1ffb841c7771deacd158faa8183f0c/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift)
- [gaelic-ghost/mlx-audio-swift Qwen3TTSSpeechTokenizer.swift](https://github.com/gaelic-ghost/mlx-audio-swift/blob/d82ad715fd1ffb841c7771deacd158faa8183f0c/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift)

## Executive Summary

The official Qwen3-TTS surface is organized around task-specific Python APIs:
`generate_voice_clone`, `generate_voice_design`, `generate_custom_voice`, and
`create_voice_clone_prompt`. The intended reusable-clone workflow is to create
a `voice_clone_prompt` from reference audio and transcript, then pass that back
into `generate_voice_clone`. The official 12 Hz tokenizer decodes with a
bounded `chunked_decode(...)` path, and the official checkpoints ship a
`generation_config.json` with default sampling values including
`max_new_tokens = 8192`.

`mlx-audio-swift` keeps the same broad model families, but it collapses them
into a more generic Swift `generate(...)` / `generateStream(...)` surface. It
adds a Swift-native prepared-conditioning type,
`Qwen3TTSReferenceConditioning`, and a conditioned generation path that does not
exist as a first-class public type in the upstream Python API. It also adds a
true incremental decoder path through `streamingStep(...)`, while the official
tokenizer's ordinary decode path remains bounded `chunked_decode(...)`.

`SpeakSwiftly` adds another layer on top of that. It turns Qwen into a
resident-worker backend, persists prepared conditioning artifacts on voice
profiles, caches them in memory, normalizes text before generation, and drives
both live playback and retained file output through the streaming event path.
That architecture is useful and deliberate for app/runtime reasons, but it also
means our default stack is no longer very close to the official "one generate
call, one decode call" model. Several of our strongest current risks come from
that distance.

## Official Upstream Baseline

### Public model shape

The official repo exposes separate task-oriented APIs:

- Base voice cloning:
  `create_voice_clone_prompt(...)` plus `generate_voice_clone(...)`
- Voice design:
  `generate_voice_design(...)`
- Custom voice:
  `generate_custom_voice(...)`

Important upstream guidance:

- For reusable cloned voices, upstream explicitly recommends building a prompt
  once and reusing it.
- Base voice cloning supports two modes:
  - ICL mode with `ref_audio` plus `ref_text`
  - `x_vector_only_mode=True`, which skips transcript-conditioned prompting and
    uses only the speaker embedding
- The wrapper validates supported languages and supported speakers against the
  checkpoint metadata.

### Generation defaults

The official checkpoints expose these generation defaults in
`generation_config.json`:

- `do_sample: true`
- `top_k: 50`
- `top_p: 1.0`
- `temperature: 0.9`
- `repetition_penalty: 1.05`
- `subtalker_dosample: true`
- `subtalker_top_k: 50`
- `subtalker_top_p: 1.0`
- `subtalker_temperature: 0.9`
- `max_new_tokens: 8192`

That means our local sampling defaults mostly match upstream, but any lower
token cap is a local policy choice rather than an upstream default.

### Streaming and decode behavior

The official repo describes the model family as supporting streaming, but the
Python wrapper's `non_streaming_mode` flag does not expose a true streamed audio
event API. The wrapper itself says that setting `non_streaming_mode=False`
currently simulates streaming text input rather than enabling true streaming
input or true streaming generation.

For the 12 Hz tokenizer, the ordinary official decode path is bounded:

- `Qwen3TTSTokenizer.decode(...)`
- `Qwen3TTSTokenizerV2Model.decode(...)`
- `decoder.chunked_decode(audio_codes.transpose(1, 2))`

That decode path uses chunk replay with left context instead of keeping one
incremental decoder cache alive for the full utterance.

## `mlx-audio-swift` Shape

### What it preserves well

The Swift port stays close to several important upstream conventions:

- the main sampling defaults match upstream checkpoint defaults
- the model families still map to Base, CustomVoice, and VoiceDesign
- the tokenizer config preserves the 12 Hz decoder structure and carries the
  same important decoder metadata, including `sliding_window`
- the non-streaming tokenizer decode still has a bounded `chunkedDecode(...)`
  surface with the same basic chunk-and-left-context idea as upstream

### Intentional Swift-side adaptations

The Swift port also introduces several real API changes:

- generic `generate(...)` and `generateStream(...)` instead of separate
  task-specific public entry points
- a public
  `Qwen3TTSModel.Qwen3TTSReferenceConditioning` type
- `prepareReferenceConditioning(...)`
- conditioned generation through `generate(text:conditioning:...)` and
  `generateStream(text:conditioning:...)`
- debug helpers for bounded decode, streaming decode, and generated-code capture

This is a meaningful divergence from upstream. Upstream treats clone prompt
reuse as a Python wrapper convenience over tensors passed back into
`model.generate(...)`; the Swift port promotes that reusable conditioning into a
first-class typed API surface.

That is not inherently wrong. It is a practical adaptation for Swift callers.
But it means we should not assume "matching the Swift API" is the same thing as
"matching the official Qwen usage model."

### Important implementation divergences

#### 1. Default streaming cadence differs a lot

`mlx-audio-swift` uses a default `streamingInterval` of `2.0` seconds for
`generateStream(...)`.

Its README shows a much lower-latency example using `streamingInterval: 0.32`.

So the library default is conservative, but the documented streaming example is
already much more aggressive.

#### 2. Non-streaming generation does not use the tokenizer's normal bounded decode path

`Qwen3TTSModel.generateVoiceDesign(...)` calls `decodeChunk(...)` for its final
decode.

`decodeChunk(...)` does not call `speechTokenizer.decode(...)`.

Instead, it iterates over `speechTokenizer.streamingDecode(...)`, which drives
the incremental decoder path through `decoder.streamingStep(...)`.

That means the library's ordinary full-utterance generation path is not really
using the official-style bounded tokenizer decode at the end. It is using the
streaming decoder and stitching those chunks together.

This is one of the most important divergences in the whole stack.

#### 3. The library adds a true incremental decoder with carried state

`Qwen3TTSSpeechTokenizerDecoder.streamingStep(...)` keeps a transformer cache
alive across decode steps.

`chunkedDecode(...)`, by contrast, replays bounded left context per chunk.

The official tokenizer implementation exposes only the bounded decode path in
its normal public wrapper. The Swift port exposes both behaviors and then uses
the incremental one in more places than the official wrapper does.

#### 4. Token cap policy is lower than upstream

The Swift port's `defaultGenerationParameters` sets `maxTokens: 4096`, while
the official checkpoints default to `max_new_tokens: 8192`.

Then `generateVoiceDesign(...)` applies another local cap:

- `effectiveMaxTokens = min(maxTokens, max(75, targetTokenCount * 6))`

So even before `SpeakSwiftly` adds its own policy layer, the Swift port is
already more restrictive than upstream for long-form generation.

#### 5. Public batch generation is missing

The official Python wrapper supports batch generation across several task
surfaces.

The Swift README explicitly says the port does not yet expose a public batch API
and recommends issuing multiple calls at the application layer.

That is not a quality bug, but it is a real architectural divergence with
implications for throughput, consistency, and parity claims.

## `SpeakSwiftly` Shape

### What `SpeakSwiftly` adds on purpose

`SpeakSwiftly` is not trying to be a thin Qwen wrapper. It adds:

- a resident backend model instead of one-shot model objects
- worker-style request scheduling
- profile loading and persisted profile storage
- text normalization before synthesis
- playback queueing and live streamed playback
- retained file generation
- prepared-conditioning persistence and cache reuse

All of that is real product/runtime behavior, not accidental drift.

### The biggest local Qwen-specific divergences

#### 1. Prepared conditioning is the local default

`SpeakSwiftly.Configuration` defaults to `.preparedConditioning`, and
`loadPreparedQwenConditioning(...)` persists a
`Qwen3TTSReferenceConditioning` artifact into the profile store and caches it
for reuse.

This is the local equivalent of upstream's reusable clone prompt, but it is not
the same mechanism:

- upstream reuses a `voice_clone_prompt` object at the Python wrapper level
- `SpeakSwiftly` persists a Swift-native prepared-conditioning artifact on disk

Implication:

- this is a deliberate product optimization
- it is also a real semantic divergence, because the persisted artifact is now
  part of our stable runtime behavior
- our local investigations already suggest that persisted artifacts can change
  long-form behavior and are not always neutral

#### 2. `SpeakSwiftly` hard-codes `language: "English"` in the Qwen runtime path

The live Qwen generation path passes `language: "English"` for both raw and
prepared-conditioning requests.

That is narrower than the official model family, which supports multiple
languages and an `Auto` mode.

Implication:

- current `SpeakSwiftly` Qwen behavior is effectively an English-specialized
  operating mode even though the underlying model family is multilingual
- if we compare ourselves to official multilingual guidance, we should be
  explicit that we are intentionally not exposing most of that surface yet

#### 3. `SpeakSwiftly` applies a much tighter local token budget than either upstream surface

`SpeakSwiftly` resident Qwen generation uses:

- `min(2048, max(56, words * 8))` for resident requests

That is much tighter than:

- official checkpoint default `8192`
- MLX port default `4096`

Implication:

- for long-form generation, we are more likely to terminate or truncate earlier
  than either upstream surface
- we are also changing the operating regime for the model, which makes direct
  output-quality comparisons harder unless we control for prompt length and
  token cap

#### 4. Live playback and retained file generation both use the streaming event path

This is a major local architectural difference.

`handleQueueSpeechFileGeneration(...)` does not call a one-shot non-streaming
generation API and then write that waveform.

Instead, it consumes `residentGenerationStream(...)`, appends streamed chunks
into `[Float]`, and writes the concatenated result as a WAV.

So in `SpeakSwiftly`, even retained-file output is built through the streaming
generation surface.

Implication:

- local retained output is exposed to any differences in the streaming event and
  incremental decode path
- this is one reason a `SpeakSwiftly` file-generation symptom cannot be assumed
  to match the official non-streaming baseline

#### 5. `SpeakSwiftly` forces a much more aggressive streaming cadence

`SpeakSwiftly` uses a resident streaming cadence of `0.18` seconds for Qwen.

That is:

- much more aggressive than the `mlx-audio-swift` library default of `2.0`
- more aggressive than the port README example at `0.32`

Implication:

- we are deliberately trading more decoder churn and more chunk boundaries for
  lower latency
- if there is any instability in the incremental decoder path, `SpeakSwiftly`
  is operating in a regime more likely to surface it

## Comparison Table

| Area | Official Qwen3-TTS | `mlx-audio-swift` | `SpeakSwiftly` | Implication |
| --- | --- | --- | --- | --- |
| Voice-clone reuse | `create_voice_clone_prompt(...)` reused in `generate_voice_clone(...)` | `prepareReferenceConditioning(...)` plus conditioned generate APIs | prepared-conditioning artifact persisted on profile and cached in runtime | Same goal, different semantics. Our persisted artifact becomes a product surface and a possible quality variable. |
| Clone modes | ICL plus `x_vector_only_mode` | conditioned path exists, but public API is unified and does not mirror upstream task names | prepared vs raw conditioning strategy; no local `x_vector_only_mode` surface | We do not currently preserve the full official base-model mode matrix. |
| Language handling | multilingual plus `Auto` support | generic `language` parameter retained | Qwen runtime currently hard-codes `"English"` | Current app behavior is narrower than model capability. |
| Sampling defaults | checkpoint defaults from `generation_config.json`, `max_new_tokens = 8192` | same sampling defaults, but `maxTokens` defaults to `4096` | resident policy clamps to `<= 2048` | Long-form behavior is not directly comparable without controlling for token budget. |
| Non-stream decode | tokenizer `chunked_decode(...)` | ordinary generation ends in `decodeChunk(...)`, which uses streaming decode | retained-file generation consumes streaming event chunks | Our stack leans much harder on the incremental decoder than upstream does. |
| Streaming API | wrapper exposes pseudo-streaming mode, not a rich audio event stream | real `generateStream(...)` with token/info/audio events | worker-driven live stream and file reconstruction | `SpeakSwiftly` is built around a streaming-first architecture, not an upstream-style single-shot architecture. |
| Streaming cadence | not exposed as the same kind of public low-latency audio-event API | default `2.0`, README example `0.32` | runtime default `0.18` | We are running the streaming path in a more aggressive regime than the port documents as its example. |
| Batch generation | supported in Python wrapper | public batch API not exposed | app-level queueing and batch file jobs above the model layer | Feature parity exists only at the app layer, not at the model wrapper layer. |

## Which Differences Look Deliberate vs Risky

### Deliberate and defensible

- resident backend ownership in `SpeakSwiftly`
- profile persistence and text normalization
- prepared-conditioning reuse as a performance optimization
- event-stream-based live playback
- using `mlx-community` MLX model repos instead of Python/HF runtime

These are real product choices, not accidental drift.

### Worth rechecking, because they may be causing quality drift

- `mlx-audio-swift` non-streaming generation decoding through
  `streamingDecode(...)` instead of the tokenizer's bounded decode surface
- `SpeakSwiftly` retained-file generation going through the streaming event path
  instead of a direct final waveform call
- `SpeakSwiftly`'s very aggressive `0.18` streaming cadence
- local token-cap policy being much lower than upstream defaults
- persisted prepared-conditioning artifacts being treated as neutral reusable
  state even though current evidence suggests they can alter long-form behavior
- lack of an exposed `x_vector_only_mode` equivalent in `SpeakSwiftly`

## Current Evidence From Local Investigation

The existing local investigation notes already point in a consistent direction:

- the severe long-form failure is not explained by playback shaping alone
- the severe long-form failure is not explained by streamed-vs-bounded decode
  alone
- persisted conditioning artifacts appear to be a real amplifying factor
- profile choice and prompt length matter
- the worst collapse is at least somewhat stochastic across reruns

That means the most likely current picture is a combination effect:

- upstream model behavior and sequence sensitivity
- `mlx-audio-swift` decode-path differences
- `SpeakSwiftly` streaming-first runtime policy
- persisted profile artifact reuse

## Practical Implications

### For correctness and parity claims

We should be careful saying that `SpeakSwiftly` "matches Qwen3-TTS defaults."
It does not.

A more accurate statement would be:

- `SpeakSwiftly` uses Qwen3-TTS through an MLX Swift port
- `mlx-audio-swift` preserves much of the model behavior but adds a Swift-native
  conditioning and streaming surface
- `SpeakSwiftly` then adds a streaming-first resident runtime with persisted
  conditioning artifacts and tighter generation limits

### For debugging

When quality drifts, we should separate the layers in this order:

1. official Qwen baseline behavior
2. `mlx-audio-swift` one-shot bounded decode behavior
3. `mlx-audio-swift` incremental streaming decode behavior
4. `SpeakSwiftly` raw conditioning, direct capture, and retained streamed output
5. `SpeakSwiftly` prepared-conditioning artifact reuse

That is the only reliable way to tell whether a bug belongs to:

- the model
- the Swift port
- the app/runtime layer
- the persisted artifact layer

### For future architecture choices

If we want closer upstream parity, the highest-value candidates are:

- add an explicit "official-like" Qwen lane in `SpeakSwiftly` that uses raw
  conditioning and a final bounded decode for retained files
- keep prepared conditioning as an optimization, but stop treating it as the
  only normal path
- compare `0.18`, `0.32`, and a less aggressive streaming cadence under the
  same profile and prompt
- separate "latency-optimized live path" from "fidelity/reference retained-file
  path" instead of routing both through the same streamed chunk surface
- consider whether an `x_vector_only_mode` equivalent belongs in the local API
  so we can compare against the official base-model fallback more faithfully

## Recommended Next Steps

1. Add one controlled retained-file comparison lane in `SpeakSwiftly` that
   bypasses streamed chunk accumulation and asks `mlx-audio-swift` for a final
   waveform directly.

2. Run the same prompt/profile through:
   - official Python base model
   - local MLX bounded decode
   - local MLX incremental decode
   - `SpeakSwiftly` raw conditioning
   - `SpeakSwiftly` prepared conditioning

3. Treat persisted conditioning artifacts as a first-class investigation
   variable, not a transparent cache.

4. Decide explicitly whether `SpeakSwiftly` wants:
   - best upstream parity
   - best live latency
   - best reusable profile ergonomics

Right now the architecture is clearly optimized for the third and partly the
second, not for strict parity with the official Qwen runtime.
