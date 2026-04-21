# Qwen3-TTS Upstream Comparison Report

Date: 2026-04-21

## Scope

This report compares four surfaces:

1. `SpeakSwiftly`'s current Qwen generation pipeline
2. the pinned `mlx-audio-swift` fork used by this package
3. upstream `Blaizzy/mlx-audio-swift` as the Swift-side baseline
4. the official Qwen3-TTS GitHub and Hugging Face surfaces

The goal is to answer two questions clearly:

1. Where are we already aligned with the official Qwen defaults and workflow?
2. Where do `SpeakSwiftly` and the MLX Swift port diverge in architecture, defaults, or operator guidance, and what do those differences imply?

## Primary Sources

### Local `SpeakSwiftly`

- `Package.swift`
- `Package.resolved`
- `Sources/SpeakSwiftly/API/Configuration.swift`
- `Sources/SpeakSwiftly/Generation/ModelClients.swift`
- `Sources/SpeakSwiftly/Generation/ModelClients+Speech.swift`
- `Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift`
- `Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift`
- `Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift`
- `Sources/SpeakSwiftly/Generation/VoiceProfileOperations+Reroll.swift`
- `Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift`
- `Sources/SpeakSwiftly/Storage/QwenConditioningArtifacts.swift`

### Swift-side Qwen baseline

- Upstream repo: <https://github.com/Blaizzy/mlx-audio-swift>
- Local baseline checkout used for inspection:
  `/Users/galew/Workspace/Blaizzy/mlx-audio-swift`
- Key files:
  - `Sources/MLXAudioCore/Generation/GenerationTypes.swift`
  - `Sources/MLXAudioTTS/Generation.swift`
  - `Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`
  - `Sources/MLXAudioTTS/Models/Qwen3TTS/README.md`

### Official Qwen

- GitHub repo: <https://github.com/QwenLM/Qwen3-TTS>
- Hugging Face model cards:
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base>
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice>
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign>
- Published checkpoint defaults:
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base/resolve/main/generation_config.json>
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice/resolve/main/generation_config.json>
  - <https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign/resolve/main/generation_config.json>

## Executive Summary

The good news is that the core sampling defaults we use for Qwen in
`SpeakSwiftly` are already intentionally aligned with the official Qwen
checkpoint defaults: temperature `0.9`, `top_p` `1.0`, `top_k` `50`, and
repetition penalty `1.05`.

The bigger differences are not the headline sampling knobs. They are the
surrounding architecture and runtime policy:

- `SpeakSwiftly` hard-pins Qwen language handling to `"English"` in the main
  generation and conditioning paths, while official Qwen recommends `Auto` when
  the language is not known and explicit language selection when it is.
- `SpeakSwiftly` uses a much smaller effective token budget than official Qwen
  and even smaller than the MLX port's Qwen defaults.
- `SpeakSwiftly` has a stronger reusable-conditioning model than the official
  package, because it persists prepared conditioning artifacts on disk and
  caches them in memory instead of rebuilding prompt features on demand.
- The MLX Swift port exposes a real streamed-audio API, but the official Python
  package presents task-oriented batch APIs and treats `non_streaming_mode`
  mostly as prompt-layout behavior rather than a public streamed-audio surface.
- The MLX Swift README diverges materially from official Qwen guidance in a few
  places and currently misstates some model roles.

That means the most important practical differences are:

- multilingual behavior
- long-form generation budget
- conditioning reuse semantics
- streamed decode behavior
- operator expectations about which model is supposed to do what

## Official Qwen Baseline

### Task model

Official Qwen treats the model family as three distinct jobs rather than one
generic generation surface:

- `generate_custom_voice(...)`
- `generate_voice_design(...)`
- `generate_voice_clone(...)`

That separation is visible both in the public README and in the Python package
wrapper at `qwen_tts/inference/qwen3_tts_model.py`.

The official repo also treats "Voice Design then Clone" as a first-class
recommended workflow:

1. synthesize a short reference clip with VoiceDesign
2. convert that clip into a reusable clone prompt with
   `create_voice_clone_prompt(...)`
3. reuse that prompt across many later clone generations

This is an important reference point because `SpeakSwiftly`'s stored prepared
conditioning strategy is conceptually very close to that official reuse pattern.

### Published generation defaults

The inspected official checkpoint `generation_config.json` files agree on these
defaults:

| Setting | Official published value |
| --- | ---: |
| `do_sample` | `true` |
| `temperature` | `0.9` |
| `top_p` | `1.0` |
| `top_k` | `50` |
| `repetition_penalty` | `1.05` |
| `subtalker_dosample` | `true` |
| `subtalker_temperature` | `0.9` |
| `subtalker_top_p` | `1.0` |
| `subtalker_top_k` | `50` |
| `max_new_tokens` | `8192` |

The official Python wrapper merges user-provided kwargs with checkpoint defaults
from `generate_config.json`, and only falls back to its smaller hard defaults if
the checkpoint does not provide a value.

### Language guidance

Official Qwen guidance is flexible rather than fixed:

- pass `Auto` or omit `language` when the language is not known
- pass the target language explicitly when it is known
- for CustomVoice speakers, prefer each speaker's native language for best
  quality

That guidance appears both in the README examples and in the model cards.

### Clone prompt reuse

The official reusable clone-prompt container stores:

- reference code
- speaker embedding
- whether the prompt is x-vector-only
- whether ICL mode is active
- optional reference text

That object is intentionally reusable and batch-friendly.

### Streaming semantics

The official Qwen public package does support streaming-oriented internal model
behavior, but its public Python wrapper does not expose a streamed-audio event
API like the MLX Swift port does.

Instead, the wrapper exposes `non_streaming_mode`, and the docs explicitly say
that when it is `false` it currently simulates streaming text input rather than
providing true public streaming input or streaming generation at that wrapper
layer.

## Upstream `mlx-audio-swift` Baseline

### Generic defaults vs Qwen defaults

The generic `AudioGenerateParameters` defaults in `MLXAudioCore` are:

| Setting | Generic MLX default |
| --- | ---: |
| `maxTokens` | `1200` |
| `temperature` | `0.6` |
| `topP` | `0.8` |
| `repetitionPenalty` | `1.3` |

Those generic defaults are not the effective Qwen defaults.

The actual Qwen3-TTS model overrides them with:

| Setting | Qwen MLX default |
| --- | ---: |
| `maxTokens` | `4096` |
| `temperature` | `0.9` |
| `topP` | `1.0` |
| `repetitionPenalty` | `1.05` |
| `topK` | `50` |
| `minP` | `0.0` |
| fallback language | `"auto"` |
| default streaming interval | `2.0` seconds |

So the MLX implementation is intentionally aligned with the official Qwen
sampling defaults more than its generic library surface suggests.

### Internal token-budget cap

Even when the caller passes a larger budget, the MLX port applies:

`effectiveMaxTokens = min(maxTokens, max(75, targetTokenCount * 6))`

This already makes the practical budget smaller than official Qwen's published
`8192` maximum for longer prompts.

### Public streaming shape

The MLX Swift port diverges from the official Python wrapper in one important
way: it exposes a real audio-event streaming API.

It incrementally decodes generated code chunks with
`speechTokenizer.decoder.streamingStep(...)` and yields audio chunks on an
`AsyncThrowingStream`.

That is a meaningful architectural difference, not just a naming difference.

### Subtalker controls

Official Qwen publishes separate `subtalker_*` defaults and forwards those to
the underlying model generate call.

The MLX Qwen port does not expose separate public subtalker controls. Its Qwen
generation loop uses the same top-k, top-p, and temperature values across the
main codebook token and the later codebook predictions. This is close to the
official published defaults because the defaults match, but it is still a
surface-level divergence because the knobs are not distinct in Swift.

### Public task surface

Official Qwen uses task-specific public methods. The MLX port instead maps the
whole family onto a generic surface:

- `text`
- `voice`
- `refAudio`
- `refText`
- `language`
- `generationParameters`

That simplifies integration, but it also hides official task boundaries:

- in CustomVoice, `voice` really acts like speaker-plus-style conditioning
- in VoiceDesign, `voice` really acts like an instruction string
- in Base, `refAudio` plus `refText` really mean clone prompt inputs

### README drift in the MLX port

The current Qwen README in `mlx-audio-swift` is materially out of sync with the
official Qwen semantics in a few places:

- it shows a bare Base-model example with no reference audio or transcript
- it labels `0.6B-Base` as "Fast, predefined voices", which is not how official
  Qwen describes the Base checkpoints
- it groups preset speakers under "Base / CustomVoice", even though official
  Qwen associates named supported speakers with CustomVoice

That documentation drift is likely to confuse maintainers about the intended
role of each checkpoint family.

## The Pinned Fork in `SpeakSwiftly`

`SpeakSwiftly` is not pinned to upstream `Blaizzy/mlx-audio-swift` `main`.
It is pinned to Gale's fork branch:

- repo: `https://github.com/gaelic-ghost/mlx-audio-swift.git`
- branch: `tests/qwen3tts-decay-repro`
- revision: `d82ad715fd1ffb841c7771deacd158faa8183f0c`

Compared with upstream `main`, the inspected diff in the Qwen file is dominated
by two categories of changes:

- reusable prepared-conditioning support
- debug and decode-capture hooks

Those fork changes do not appear to rewrite the main Qwen sampling defaults or
the core generation loop policy. They mostly make the existing Qwen internals
addressable from `SpeakSwiftly` for conditioning reuse and investigation work.

## Current `SpeakSwiftly` Qwen Pipeline

### Runtime shape

`SpeakSwiftly` defaults to:

- speech backend: `qwen3`
- Qwen conditioning strategy: `prepared_conditioning`

The active resident and profile model repos are:

- resident generation model:
  `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
- profile creation model:
  `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`

This is mostly aligned with official Qwen's "Voice Design then Clone" idea:

- create a canonical profile voice with VoiceDesign
- reuse a Base-family resident model for later generation

### Sampling policy

`SpeakSwiftly` explicitly sets Qwen generation parameters instead of depending
on generic defaults:

| Surface | `maxTokens` policy | `temperature` | `topP` | `repetitionPenalty` |
| --- | --- | ---: | ---: | ---: |
| resident generation | `min(2048, max(56, words * 8))` | `0.9` | `1.0` | `1.05` |
| profile generation | `min(3072, max(96, words * 10))` | `0.9` | `1.0` | `1.05` |

That means our sampling defaults are aligned, but our token budgets are
significantly tighter than the official checkpoint defaults and also tighter
than the MLX Qwen defaults.

### Language policy

`SpeakSwiftly` currently hardcodes `"English"` in the important Qwen paths:

- resident raw generation
- prepared-conditioning creation
- profile creation
- profile reroll
- clone transcription

This is the clearest functional divergence from official Qwen recommendations.
It means we currently suppress:

- official `Auto` language adaptation
- explicit non-English target-language selection
- CustomVoice native-language guidance
- dialect-sensitive language-id behavior that official Qwen performs

### Prepared conditioning

This is the most important architectural divergence, and it is mostly an
intentional one.

`SpeakSwiftly`:

1. loads or creates a prepared conditioning object
2. persists it on disk
3. caches it in memory
4. reuses it across later generations

The stored artifact contains:

- speaker embedding
- reference speech codes
- reference text token ids
- resolved language
- codec language id

That is stronger and more durable than the official Qwen wrapper's reusable
prompt flow, but it is philosophically aligned with it. The practical effect is
that `SpeakSwiftly` turns Qwen clone prompt reuse into a stable profile asset
instead of an in-memory helper object.

### Streaming cadence

`SpeakSwiftly` sets the resident streaming interval to `0.18` seconds for
playback-oriented generation.

That is far more aggressive than the MLX Qwen default of `2.0` seconds and much
closer to a low-latency playback policy than to an ordinary library default.

## Side-by-Side Divergences

### 1. Model-role semantics

| Area | Official Qwen | MLX port | `SpeakSwiftly` | Implication |
| --- | --- | --- | --- | --- |
| Base checkpoint role | voice clone from reference audio | generic `generate(...)`; README partly misdescribes it | resident generation model with raw or prepared clone conditioning | local runtime behavior is clone-shaped, but MLX docs can mislead maintainers |
| CustomVoice role | named speakers, optional instruction control | mapped through generic `voice` field | currently not the active resident path | task semantics are compressed in Swift |
| VoiceDesign role | natural-language voice design | mapped through generic `voice` field | profile creation and reroll | this part is conceptually aligned |

### 2. Sampling defaults

| Area | Official Qwen | MLX Qwen | `SpeakSwiftly` | Read |
| --- | --- | --- | --- | --- |
| temperature | `0.9` | `0.9` | `0.9` | aligned |
| top-p | `1.0` | `1.0` | `1.0` | aligned |
| top-k | `50` | `50` | inherited from MLX Qwen | aligned |
| repetition penalty | `1.05` | `1.05` | `1.05` | aligned |
| subtalker knobs | explicit and distinct | not distinct publicly | not surfaced | close in defaults, divergent in control surface |

### 3. Token budget

| Area | Official Qwen | MLX Qwen | `SpeakSwiftly` | Implication |
| --- | --- | --- | --- | --- |
| published max token default | `8192` | `4096` default, then capped by text length | `2048` or `3072`, then still subject to MLX cap | long-form behavior can diverge before sampling even starts |

### 4. Language behavior

| Area | Official Qwen | MLX Qwen | `SpeakSwiftly` | Implication |
| --- | --- | --- | --- | --- |
| unspecified language | `Auto` / adaptive | `"auto"` fallback | `"English"` | local runtime loses multilingual and dialect-aware behavior |
| known target language | pass explicit value | supported | currently not exposed in the main runtime path | local package is effectively English-shaped |
| CustomVoice native-language recommendation | explicit | not encoded in README surface | not used | quality can suffer when using non-native language paths |

### 5. Conditioning reuse

| Area | Official Qwen | MLX upstream | `SpeakSwiftly` | Implication |
| --- | --- | --- | --- | --- |
| reusable clone prompt | `create_voice_clone_prompt(...)` | upstream `main` does not expose an equivalent reusable public object | persisted prepared conditioning artifact | `SpeakSwiftly` has the strongest reuse story here |
| speaker-only mode | `x_vector_only_mode=True` supported | not exposed in the inspected Swift surface | not exposed in the package runtime | local runtime is more opinionated toward text-aligned ICL conditioning |

### 6. Streaming architecture

| Area | Official Qwen Python wrapper | MLX Qwen | `SpeakSwiftly` | Implication |
| --- | --- | --- | --- | --- |
| public streamed audio API | no equivalent event stream at wrapper layer | yes, chunked audio events | yes, used for playback | local runtime depends heavily on the streamed decode path |
| non-streaming mode concept | prompt-layout / simulated streaming input switch | not modeled the same way | not modeled the same way | public semantics differ even when model family is the same |
| chunk cadence | not exposed like MLX | `2.0s` default | `0.18s` resident playback | `SpeakSwiftly` stresses the streamed decoder much more aggressively |

## Implications

### What looks healthy

- Our core Qwen sampling knobs are not the source of an upstream-default mismatch.
- Using VoiceDesign for profile creation and a Base-family model for later reuse
  is consistent with official Qwen's recommended "design then clone" workflow.
- Prepared conditioning is not an alien invention. It is a stronger,
  more durable version of official prompt reuse.

### What is most likely to matter for real behavior

#### Language pinning

Hardcoding `"English"` is the cleanest and highest-confidence divergence from
official guidance. It changes prompt construction semantics and can suppress the
language-id behavior official Qwen would normally derive from `Auto` or an
explicit target language.

This matters even for English-heavy use because it removes the possibility of:

- true multilingual requests
- dialect-sensitive CustomVoice behavior
- profile conditioning artifacts that carry the correct resolved language

#### Token budget shrinkage

Official Qwen publishes `8192` as the checkpoint default. The MLX port already
cuts that down materially, and `SpeakSwiftly` cuts it further.

That means long-form failures, premature EOS behavior, or degraded later
sections of a response can come from token-budget policy before we even get to
questions about decoder stability or playback.

#### Streamed decode path

The loudness-decay investigation should keep treating streamed decode as a
first-class suspect.

Why:

- official Qwen's public package surface is not centered on the same streamed
  audio event API shape
- the MLX port uses `decoder.streamingStep(...)` incrementally while the
  non-streaming path performs a full decode after generation
- `SpeakSwiftly` further tightens the cadence to `0.18` seconds, which
  increases pressure on that streamed path

If the same generated codes sound healthy through bounded/full decode but decay
through incremental streamed decode, that would point to the decoder path rather
than the higher-level sampling defaults.

#### README and API semantic drift

The MLX port's generic public API is usable, but it obscures the official task
boundaries. The README drift makes that worse by implying that Base checkpoints
act like predefined speaker models.

That documentation mismatch is not just cosmetic. It can push future
maintainers toward the wrong mental model when debugging or adding features.

## Recommendations

### 1. Keep the current core sampling defaults

There is no evidence in this comparison that `temperature`, `top_p`, `top_k`,
or repetition penalty should be changed for "upstream alignment" reasons.

### 2. Revisit language handling before retuning generation

The next alignment pass should probably focus on language policy first:

- allow request-level language selection
- use `Auto` when the language is not known
- stop hardcoding `"English"` into prepared-conditioning creation

This is the largest obvious divergence from official recommendations.

### 3. Keep prepared conditioning, but document it as the local analogue to
official clone-prompt reuse

This part is a product-strengthening change, not an upstream mistake.
What would help is clearer maintainer documentation that says:

- official Qwen reuses prompt items in memory
- `SpeakSwiftly` persists the same idea as a stable profile artifact

### 4. Treat streamed decode and cadence as the primary divergence for decay
forensics

For the loudness-decay investigation, the best compare-first lane is:

1. hold sampling defaults fixed
2. hold generated codes fixed
3. compare full decode, bounded chunk decode, and streamed incremental decode
4. compare a calmer cadence against the current `0.18s` playback cadence

That isolates the part of the stack most likely to differ from the official
reference behavior.

### 5. Sync MLX-side Qwen docs with official model roles

At minimum, the MLX README should stop implying that Base checkpoints are
predefined-voice models and should stop presenting the CustomVoice speaker list
as if it were also a Base-model concept.

## Bottom Line

The main story is not "our Qwen settings are wildly off from upstream." They
are not.

The real story is:

- `SpeakSwiftly` is aligned on the core Qwen sampling defaults
- `SpeakSwiftly` intentionally adds stronger reusable conditioning than official
  Qwen's in-memory prompt reuse
- `SpeakSwiftly` diverges most clearly on language policy, token budget, and
  aggressive streamed-audio cadence
- the MLX Swift port diverges most clearly on public API shape, subtalker
  control exposure, and some README semantics

So if we are trying to explain quality or stability differences, the highest
value places to look next are:

1. hardcoded English language routing
2. reduced token budget
3. streamed decoder behavior under `0.18s` cadence
