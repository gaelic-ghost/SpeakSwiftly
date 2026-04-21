# Qwen3-TTS Settings Comparison

Date: 2026-04-21

## Scope

This note compares the Qwen3-TTS generation and model settings currently used by
`SpeakSwiftly` against:

- the vendored `mlx-audio-swift` fork pinned in this repository
- the official Qwen3-TTS GitHub repository
- the official Qwen3-TTS Hugging Face model repos and checkpoint configs

The goal is to separate:

- settings where `SpeakSwiftly` is already aligned with upstream Qwen defaults
- settings where `SpeakSwiftly` diverges intentionally for product reasons
- settings where `SpeakSwiftly` diverges in ways that may matter for the active
  long-form decay investigation

## Primary Sources

### Local `SpeakSwiftly`

- `Sources/SpeakSwiftly/API/Configuration.swift`
- `Sources/SpeakSwiftly/Generation/ModelClients.swift`
- `Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift`
- `Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift`
- `Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift`
- `Sources/SpeakSwiftly/Generation/VoiceProfileOperations+Reroll.swift`
- `Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift`
- `Package.resolved`

### Vendored `mlx-audio-swift`

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioCore/Generation/GenerationTypes.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Generation.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/README.md`

### Official Qwen

- GitHub repo: <https://github.com/QwenLM/Qwen3-TTS>
- Base model card: <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base>
- CustomVoice model card: <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice>
- VoiceDesign model card: <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign>
- Published checkpoint defaults:
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base/resolve/main/generation_config.json>
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice/resolve/main/generation_config.json>
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign/resolve/main/generation_config.json>

## Current `SpeakSwiftly` Qwen Surface

### Runtime and model selection

`SpeakSwiftly` currently defaults the runtime to:

- backend: `qwen3`
- Qwen conditioning strategy: `prepared_conditioning`

Source:

- `Sources/SpeakSwiftly/API/Configuration.swift`

The active Qwen model repos are:

- resident generation model: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
- profile-creation model: `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`
- legacy custom-voice repo retained only as a historical constant:
  `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16`

Source:

- `Sources/SpeakSwiftly/Generation/ModelClients.swift`

### Sampling parameters

`SpeakSwiftly` does not rely on vendored generic defaults for Qwen. It always
passes explicit generation parameters:

| Surface | `maxTokens` | `temperature` | `topP` | `repetitionPenalty` |
| --- | ---: | ---: | ---: | ---: |
| resident Qwen generation | `min(2048, max(56, words * 8))` | `0.9` | `1.0` | `1.05` |
| profile VoiceDesign generation | `min(3072, max(96, words * 10))` | `0.9` | `1.0` | `1.05` |

Source:

- `Sources/SpeakSwiftly/Generation/ModelClients.swift`

### Language handling

`SpeakSwiftly` hardcodes `language: "English"` in the important Qwen paths:

- resident raw Qwen generation
- prepared-conditioning creation
- profile creation through VoiceDesign
- profile reroll through VoiceDesign

It does not currently pass `nil`, `Auto`, or a language inferred from the
request text.

Source:

- `Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift`
- `Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift`
- `Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift`
- `Sources/SpeakSwiftly/Generation/VoiceProfileOperations+Reroll.swift`

### Conditioning reuse

`SpeakSwiftly` defaults to persisted prepared conditioning:

- prepare once from `refAudio` + `refText`
- persist the resulting artifact on the profile
- cache it in memory after load
- reuse it across later generations

That is a much stronger reuse policy than the raw upstream `refAudio` /
`refText` path.

Source:

- `Sources/SpeakSwiftly/API/Configuration.swift`
- `Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift`

### Streaming cadence

`SpeakSwiftly` sets the ordinary resident streaming interval to `0.18` seconds
for playback-oriented generation.

Source:

- `Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift`

## Vendored `mlx-audio-swift` Defaults

### Generic library defaults

The vendored library's generic `AudioGenerateParameters` type defaults to:

- `maxTokens: 1200`
- `temperature: 0.6`
- `topP: 0.8`
- `repetitionPenalty: 1.3`
- `repetitionContextSize: 20`

Source:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioCore/Generation/GenerationTypes.swift`

This is important because those are not the real Qwen3-TTS defaults in the same
library.

### Qwen3-TTS model defaults

The vendored Qwen3-TTS model itself overrides the generic defaults with:

- `maxTokens: 4096`
- `temperature: 0.9`
- `topP: 1.0`
- `repetitionPenalty: 1.05`

And the Qwen path hardcodes:

- `topK: 50`
- `minP: 0.0`
- default language fallback: `auto` when `language == nil`
- default streaming interval: `2.0` seconds

Source:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Generation.swift`

### Internal max-token cap

Even if the caller passes a larger token budget, vendored Qwen3-TTS still
applies an internal cap:

- `effectiveMaxTokens = min(maxTokens, max(75, targetTokenCount * 6))`

Source:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`

### Conditioned generation support

The vendored Qwen model already exposes the primitives `SpeakSwiftly` relies on:

- `prepareReferenceConditioning(...)`
- conditioned `generate(...)`
- conditioned `generateStream(...)`

So persisted prepared conditioning is not a foreign concept layered on top of
Qwen3-TTS. What `SpeakSwiftly` adds is durable profile persistence and cache
reuse.

Source:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`

## Official Qwen Defaults and Recommendations

### Model surface

The official Qwen repo treats these as distinct first-class tasks:

| Model | Official role |
| --- | --- |
| `Qwen3-TTS-12Hz-*-Base` | voice clone from reference audio |
| `Qwen3-TTS-12Hz-*-CustomVoice` | fixed named speakers plus optional instruction/style control |
| `Qwen3-TTS-12Hz-1.7B-VoiceDesign` | free-form voice design from natural-language description |

Official Qwen also recommends a composite "Voice Design then Clone" workflow
when you want to design a persona once and then reuse it repeatedly as a cloned
speaker.

Source:

- <https://github.com/QwenLM/Qwen3-TTS>

### Language guidance

The official GitHub examples do not hardcode English.

Instead:

- pass `Auto` or omit `language` for adaptive language selection when the
  language is not known
- set `language` explicitly when the target language is known
- for CustomVoice, prefer each speaker's native language for best quality

Source:

- <https://github.com/QwenLM/Qwen3-TTS>
- <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice>

### Voice-clone prompt reuse

Official Qwen explicitly recommends reusable prompt construction when cloning
many lines from the same reference speaker:

- build once with `create_voice_clone_prompt(...)`
- reuse it across later `generate_voice_clone(...)` calls

That is conceptually very close to `SpeakSwiftly`'s persisted prepared
conditioning path.

Source:

- <https://github.com/QwenLM/Qwen3-TTS>

### Official checkpoint defaults

The published `generation_config.json` files for the three inspected official
checkpoints agree on the main sampling defaults:

| Official checkpoint default | Value |
| --- | ---: |
| `do_sample` | `true` |
| `temperature` | `0.9` |
| `top_p` | `1.0` |
| `top_k` | `50` |
| `repetition_penalty` | `1.05` |
| `max_new_tokens` | `8192` |

They also publish matching `subtalker_*` sampling defaults:

- `subtalker_temperature: 0.9`
- `subtalker_top_p: 1.0`
- `subtalker_top_k: 50`

Source:

- official Hugging Face checkpoint `generation_config.json` files

### Evaluation-time guidance

The official repo says their evaluation runs used:

- `dtype=torch.bfloat16`
- `max_new_tokens=2048`
- all other sampling parameters from the checkpoint's `generate_config.json`
- `language="auto"` for Seed-Test and InstructTTS-Eval
- explicit `language` for the other evaluation sets

Source:

- <https://github.com/QwenLM/Qwen3-TTS>

## Comparison Matrix

| Area | `SpeakSwiftly` | vendored `mlx-audio-swift` | official Qwen | Read |
| --- | --- | --- | --- | --- |
| resident model family | `0.6B-Base-8bit` only | supports Base, CustomVoice, VoiceDesign in MLX ports | treats Base, CustomVoice, VoiceDesign as separate first-class tasks | `SpeakSwiftly` intentionally narrows the model surface |
| profile creation model | `1.7B-VoiceDesign-bf16` | supported | official VoiceDesign model | aligned in broad task choice |
| runtime task shape | design once, then clone from Base model forever | low-level primitives only | officially recommends VoiceDesign-then-Clone as one useful workflow | broadly aligned |
| Qwen conditioning reuse | persisted and cached by default | primitive support exists, but no profile persistence policy | reusable clone prompts explicitly recommended | aligned in spirit, stronger in persistence |
| `temperature` | `0.9` | Qwen default `0.9` | checkpoint default `0.9` | aligned |
| `topP` | `1.0` | Qwen default `1.0` | checkpoint default `1.0` | aligned |
| `repetitionPenalty` | `1.05` | Qwen default `1.05` | checkpoint default `1.05` | aligned |
| `topK` | not exposed directly; inherited as `50` | hardcoded `50` in Qwen path | checkpoint default `50` | aligned |
| generic library defaults | not used for Qwen | `1200 / 0.6 / 0.8 / 1.3 / 20` | not the official Qwen defaults | this generic default set is misleading for Qwen |
| token budget | resident `56..2048`, profile `96..3072` | Qwen default `4096`, then `min(maxTokens, max(75, text_tokens * 6))` | checkpoint default `8192`, evaluation often `2048` | `SpeakSwiftly` is materially stricter |
| language default | hardcoded `"English"` | `auto` when omitted | `Auto` or explicit language depending on certainty | strong divergence |
| streaming interval | `0.18` seconds | default `2.0` seconds, README example `0.32` | official repo emphasizes low latency but does not publish one stable numeric default here | strong divergence |
| speaker / instruct control | not exposed on resident runtime path | supported by CustomVoice / VoiceDesign model paths | core part of official model surface | `SpeakSwiftly` omits official instruction-control tasks from runtime |
| precision / quantization | resident model is 8-bit MLX conversion | MLX ports include 8-bit and bf16 variants | official examples use bf16 with FlashAttention 2 | expected deployment divergence |

## Divergences That Look Most Relevant To The Decay Investigation

### 1. Hardcoded English language selection

This is the most obvious configuration divergence.

Official Qwen guidance is:

- use `Auto` or omit language when the language is not known
- set language explicitly when it is known

`SpeakSwiftly` instead forces `language: "English"` through:

- resident generation
- prepared-conditioning creation
- profile creation
- profile reroll

That means `SpeakSwiftly` is opting out of one of the main upstream control
paths and may be pinning Qwen into an English-specific codec-language regime
even when the prompt, profile, or long-form request would benefit from `auto`
or from an explicit non-English setting.

### 2. Much more aggressive streaming cadence

`SpeakSwiftly` uses `0.18s` streaming cadence for playback-driven resident work.

That is far more aggressive than:

- vendored `generateStream(...)` default `2.0s`
- vendored README example `0.32s`

This may be completely fine for responsiveness, but it is still a meaningful
decode/runtime divergence from the reference integration surface and should stay
on the suspect list for any long-form instability that depends on chunking or
decoder state carry-over.

### 3. Stricter token budgeting

`SpeakSwiftly` does not let Qwen run on the checkpoint default `8192` token
budget or even the vendored Qwen wrapper default `4096`. It supplies smaller
heuristic budgets up front.

That said, one useful nuance emerged from the existing long-form repro:

- a `1184`-word resident probe reaches the local resident cap of `2048`
- that matches the official evaluation token budget of `2048`

So the current long-form decay does not look like a simple "SpeakSwiftly gave
Qwen a wildly larger token budget than upstream expects" story. On long probes,
our cap is actually close to how the official repo says it evaluated the model.

### 4. Narrower model surface

Official Qwen exposes:

- Base for cloning
- CustomVoice for fixed named speakers plus style instructions
- VoiceDesign for natural-language voice descriptions

`SpeakSwiftly` currently narrows that to:

- Base model for resident generation
- VoiceDesign model only for profile creation
- no first-class runtime path for CustomVoice

That means local behavior is dominated by the Base-model voice-clone regime,
even when some official recommendation or demo would instead use a dedicated
CustomVoice or VoiceDesign path.

### 5. Prepared-conditioning persistence is closer to official reusable-prompt guidance than to a fork-only hack

This does not currently look like a bad divergence by itself.

Official Qwen explicitly recommends reusable voice-clone prompts to avoid
recomputing prompt features. `SpeakSwiftly`'s prepared-conditioning default is
basically the same idea, but stored durably on the profile and cached locally.

So for investigation purposes, "prepared conditioning exists at all" looks more
like an aligned optimization than an obviously suspicious invention. The real
question is whether our specific persisted artifact path has a bug, not whether
reuse itself is upstream-incompatible.

## Settings That Already Match Official Qwen Well

The main sampling trio is already aligned:

- `temperature = 0.9`
- `top_p = 1.0`
- `repetition_penalty = 1.05`

And the effective `top_k = 50` behavior is aligned too, even though
`SpeakSwiftly` does not expose it as a local public knob.

That means the first-pass decay suspicion should not center on:

- temperature mismatch
- top-p mismatch
- repetition-penalty mismatch
- top-k mismatch

Those settings are already close to the official checkpoint defaults.

## Current Best Read

The settings comparison points to a fairly specific split:

- broad sampling defaults are not the obvious problem
- model-family narrowing, forced English, aggressive streaming cadence, and
  strict local token heuristics are the bigger integration-level divergences
- prepared-conditioning persistence is a meaningful divergence in mechanism,
  but not in overall direction, because official Qwen also recommends prompt
  reuse for repeated cloning

For the decay investigation, the most suspicious configuration-level
differences are therefore:

1. `language: "English"` being forced through all the major Qwen paths
2. resident playback cadence `0.18s` versus the much looser vendored default
3. always staying on the Base-model clone path at runtime instead of exposing
   the fuller official task split
4. the compound interaction between those choices and our persisted
   prepared-conditioning artifacts

That still fits the current working theory from the investigation notes: the
failure may be a combination of several smaller effects that compound in a
partly non-deterministic way, not one single clean settings bug.
