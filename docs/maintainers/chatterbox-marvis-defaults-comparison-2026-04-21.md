# Chatterbox And Marvis Defaults Comparison

## Purpose

This note compares the current `SpeakSwiftly` runtime behavior against two distinct upstream surfaces:

- `mlx-audio-swift`: the Swift wrapper and model integration layer we build on
- model repo/card: the backend model's own GitHub repository and Hugging Face card or config

Keep those two upstreams separate when reading diffs. The model repo or card describes the model family and published artifacts. `mlx-audio-swift` describes the current Swift runtime behavior we inherit unless `SpeakSwiftly` overrides it.

## Direct Answer

### Chatterbox Turbo

Chatterbox Turbo does not currently give us native incremental audio streaming through the `mlx-audio-swift` path we use.

More precisely:

- the `mlx-audio-swift` API is stream-shaped for Chatterbox
- but the current Chatterbox implementation still synthesizes a full chunk waveform before yielding audio
- `SpeakSwiftly` gets live playback by chunking text in the runtime and synthesizing those text chunks sequentially

So the correct statement is:

- Chatterbox Turbo is not currently native-streaming in the `mlx-audio-swift` integration we use
- `SpeakSwiftly` adds chunk-at-a-time live delivery on top of that non-incremental backend behavior

### Marvis

Marvis is different. The current `mlx-audio-swift` Marvis path does perform real chunked streaming generation. `SpeakSwiftly` still overrides cadence and playback policy, but it is building on a genuinely streaming backend path there.

## Source Labels

### `SpeakSwiftly`

Current local package behavior in this repository.

### `mlx-audio-swift`

Current `Blaizzy/mlx-audio-swift` `main` behavior as checked on 2026-04-22.

### `model repo/card`

The model's own public repo and published Hugging Face surfaces:

- Chatterbox Turbo:
  - `resemble-ai/chatterbox`
  - `ResembleAI/chatterbox-turbo`
  - `mlx-community/chatterbox-turbo-8bit`
- Marvis:
  - `Marvis-Labs/marvis-tts`
  - `Marvis-AI/marvis-tts-250m-v0.2`
  - `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit`

## Chatterbox Turbo

| Surface | SpeakSwiftly | mlx-audio-swift | model repo/card |
| --- | --- | --- | --- |
| Live generation shape | Runtime-owned chunked live playback over sequential text chunks | Stream-shaped API, but current Chatterbox path still renders one chunk waveform before yielding audio | Public docs describe ordinary `generate(...)` style synthesis, not token-by-token audio streaming |
| Native incremental audio streaming | No | No, not in the current Chatterbox integration path | Not clearly claimed in the model card or repo usage docs |
| Text chunking before synthesis | Yes. First chunk `3` sentences, later chunks `2` sentences | No comparable runtime chunk planner in the Chatterbox model path | Not documented as the intended inference path |
| Streaming cadence | `0.5s` resident interval for standard non-Qwen resident playback | Generic TTS streaming helpers default to `2.0s`, but current Chatterbox behavior is effectively whole-waveform-per-call for each chunk | No authoritative cadence knob documented in the model card |
| Caller-facing default generation parameters | `temperature 0.8`, `topP 0.8` | `ChatterboxModel.defaultGenerationParameters` sets `temperature 0.8` | Model card emphasizes usage and capabilities, not these inference defaults |
| Effective Chatterbox Turbo inference parameters | Our `temperature` and `topP` are passed through | Turbo inference uses dynamic `maxTokens`, `topK 1000`, caller `temperature`, caller `topP`, and hardcoded `repetitionPenalty 1.2` | Not described at this level in the repo or card |
| Max text window | No local hard cap beyond what upstream model path accepts; we reduce risk by pre-chunking | Turbo config uses `max_text_tokens 2048` | HF config also shows `max_text_tokens 2048` |
| Max speech token window | Local policy says `4096`, but upstream computes this internally for Chatterbox | Turbo config uses `max_speech_tokens 4096`, with fallback cap `min(768, max(200, textLen * 10))` when prompt speech tokens are missing | HF config shows `max_speech_tokens 4096` |
| Context window | We avoid long single-pass text by chunking in the runtime | GPT-2 Turbo backbone config uses `n_ctx 8196` and `n_positions 8196` | HF config for `mlx-community/chatterbox-turbo-8bit` shows the same `8196` context size |
| Voice conditioning default | Uses stored profile reference audio when available, otherwise built-in default conditioning | Chatterbox model ships built-in default conditioning for Turbo | HF config exposes built-in conditioning-related config and the MLX card explicitly mentions a default voice path |

### Chatterbox Notes

- The important distinction is not "stream API versus non-stream API." The important distinction is whether audio is yielded incrementally during one synthesis call. In the current `mlx-audio-swift` Chatterbox path, that answer is still no.
- `SpeakSwiftly` gets live playback by turning one request into many smaller Chatterbox calls. That is a runtime orchestration strategy, not a native model-streaming capability.
- Our local `maxTokens 4096` and `repetitionPenalty 1.05` do not cleanly map to the final Chatterbox Turbo inference path because upstream Chatterbox computes the effective speech-token cap itself and hardcodes `repetitionPenalty 1.2` inside Turbo inference.
- The most meaningful Chatterbox diffs today are:
  - runtime-owned sentence chunking
  - still-live but now less aggressive `0.5s` cadence instead of our older faster local cadence
  - upstream-aligned `temperature 0.8` and `topP 0.8`

## Marvis

| Surface | SpeakSwiftly | mlx-audio-swift | model repo/card |
| --- | --- | --- | --- |
| Live generation shape | Native streaming backend plus SpeakSwiftly-specific scheduling and playback heuristics | Native chunked streaming generation path | Model card explicitly describes real-time streaming TTS |
| Native incremental audio streaming | Yes, via upstream Marvis streaming path | Yes | Yes, that is a headline feature in the model repo and card |
| Text chunking before synthesis | No local text chunk planner in the Marvis path | No. Marvis processes the full text context passed into the request | Model card explicitly says Marvis processes full text context rather than regex chunking |
| Streaming cadence | `0.5s` for standard resident playback and both Marvis-specific cadence roles | Core Marvis streaming path uses `0.5s`; generic wrapper defaults to `2.0s` | Model docs emphasize streaming, but do not publish a canonical cadence number |
| Caller-facing default generation parameters | No local Marvis override. `SpeakSwiftly` passes an empty `GenerateParameters()` because upstream ignores caller knobs here | `defaultGenerationParameters` returns `maxTokens 750`, `temperature 0.9`, `topP 0.8` | Published MLX config includes generic generation metadata like `temperature 1.0`, `top_k 50`, `top_p 1.0`, but that is not the same thing as the current MLX Swift sampling path |
| Effective Marvis inference parameters | We intentionally defer to upstream internal defaults | Current Marvis implementation hardcodes `TopPSampler(temperature: 0.9, topP: 0.8)` and computes `maxAudioFrames 750` internally | Model repo shows a `temperature` and `topk` generate surface in Python, but that is a separate implementation surface |
| Max generated audio frame budget | No local override | `maxAudioFrames = Int(60000 / 80.0) = 750` | MLX model config and repo framing align with 12.5 fps audio-token timing and a 24 kHz Mimi codec stack |
| Input sequence budget | No local extra cap; we rely on upstream model limit and runtime scheduling | Input must stay below `2048 - 750 = 1298` sequence positions in the current MLX Swift Marvis path | HF config for the MLX model shows `max_position_embeddings 2048` at the backbone level, with Mimi codec `max_position_embeddings 8000` and `sliding_window 250` in codec metadata |
| Context window | We preserve full normalized text instead of pre-chunking | Full prompt context is prepended and processed in one contextual sequence | Model card explicitly says this is a core design goal |
| Codec and sliding-window metadata | No local override | Uses the model artifact as loaded | HF config shows Mimi codec metadata including `sliding_window 250` and `_frame_rate 12.5` |
| Resident voice policy | Configurable. Default is `dual_resident_serialized`, which keeps the `femme` and `masc` resident routes warm while serializing generation. Optional `single_resident_dynamic` reuses one resident model object for whichever route the next request needs | One model instance has mutable caches; upstream does not provide our policy surface | Model card focuses on conversational voices and cloning behavior, not our runtime policy choices |
| Marvis generation concurrency | Serialized. SpeakSwiftly now allows only one Marvis generation at a time | No equivalent SpeakSwiftly-style scheduler policy | Not part of the model repo or card surface |
| Playback stabilization | SpeakSwiftly applies one conservative Marvis live-startup profile with raised startup and resume floors across live Marvis playback | No comparable playback policy in `mlx-audio-swift` | Not part of the model repo or card surface |

### Marvis Notes

- Marvis is the opposite of Chatterbox in one key respect: the upstream `mlx-audio-swift` path really does stream audio progressively.
- After the 2026-04-22 alignment pass, Marvis no longer differs from `mlx-audio-swift` on the live cadence we request or on nominal caller sampling overrides. Those were explicit local differences before; they are not the main diffs now.
- After the later 2026-04-22 simplification pass, SpeakSwiftly now serializes Marvis generation outright instead of trying to overlap two Marvis generations across resident lanes.
- After the follow-up 2026-04-22 playback pass, all live Marvis requests now use the same conservative Marvis startup profile instead of only the first request getting the larger preroll.
- The largest real Marvis diffs now are:
  - resident loading policy, either `dual_resident_serialized` or `single_resident_dynamic`
  - serialized Marvis generation on top of the upstream model
  - custom playback thresholds for startup and recovery, now applied as one Marvis live-startup profile
  - simple `femme` versus `masc` route selection on top of the upstream model
- We now intentionally avoid pretending Marvis has local operative sampling knobs. `SpeakSwiftly` passes an empty `GenerateParameters()` for Marvis because upstream `MarvisTTSModel.generate(...)` and `generateStream(...)` still ignore the caller-supplied generation parameters and use internal sampling values instead.
- If we want Marvis generation knobs in `SpeakSwiftly` to become real knobs, the first prerequisite is still changing the upstream Marvis Swift wrapper so it honors caller parameters.
- The latest audible Marvis runs after serialization plus unified startup tuning make the remaining bottleneck look more like raw MLX Marvis throughput than overlap policy:
  - the first serialized request still improves materially
  - later serialized requests also now start with the same larger preroll instead of falling back to tiny `standard` startup buffering
  - that reduces the earlier later-request cliff, but it still does not make Marvis playback fully clean end to end

## Practical Conclusions

1. Chatterbox Turbo is not currently native-streaming in the `mlx-audio-swift` path we use. `SpeakSwiftly` fakes live behavior by chunking text and yielding completed chunk waveforms as each chunk finishes.
2. Marvis is currently native-streaming in the `mlx-audio-swift` path we use. `SpeakSwiftly` now matches the upstream `0.5s` streaming cadence, but still layers its own playback-stability and resident-lane policy on top.
3. "Upstream" must always be split into two labels in future notes:
   - `mlx-audio-swift`
   - model repo/card
4. The settings that matter most to align next are:
   - Chatterbox: sentence chunk sizing and whether to keep runtime-owned chunking at all
   - Marvis: whether the remaining audible instability is mostly an `mlx-audio-swift` throughput issue, and whether we want the wrapper to honor caller generation parameters instead of silently using internal defaults

## Sources

### SpeakSwiftly

- [Sources/SpeakSwiftly/Generation/ModelClients.swift](../../Sources/SpeakSwiftly/Generation/ModelClients.swift)
- [Sources/SpeakSwiftly/Generation/LiveSpeechChunkPlanner.swift](../../Sources/SpeakSwiftly/Generation/LiveSpeechChunkPlanner.swift)
- [Sources/SpeakSwiftly/Generation/SpeechGeneration+Chatterbox.swift](../../Sources/SpeakSwiftly/Generation/SpeechGeneration+Chatterbox.swift)
- [Sources/SpeakSwiftly/Generation/SpeechGeneration+Marvis.swift](../../Sources/SpeakSwiftly/Generation/SpeechGeneration+Marvis.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntimeProcessing+GenerationSupport.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntimeProcessing+GenerationSupport.swift)
- [Sources/SpeakSwiftly/Playback/PlaybackThresholdController.swift](../../Sources/SpeakSwiftly/Playback/PlaybackThresholdController.swift)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)

### mlx-audio-swift

- [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)
- [`GenerationTypes.swift`](https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/main/Sources/MLXAudioCore/Generation/GenerationTypes.swift)
- [`Generation.swift`](https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/main/Sources/MLXAudioTTS/Generation.swift)
- [`ChatterboxModel.swift`](https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/main/Sources/MLXAudioTTS/Models/Chatterbox/ChatterboxModel.swift)
- [`ChatterboxConfig.swift`](https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/main/Sources/MLXAudioTTS/Models/Chatterbox/ChatterboxConfig.swift)
- [`MarvisTTSModel.swift`](https://raw.githubusercontent.com/Blaizzy/mlx-audio-swift/main/Sources/MLXAudioTTS/Models/Marvis/MarvisTTSModel.swift)

### Model repo/card

- [resemble-ai/chatterbox](https://github.com/resemble-ai/chatterbox)
- [ResembleAI/chatterbox-turbo](https://huggingface.co/ResembleAI/chatterbox-turbo)
- [mlx-community/chatterbox-turbo-8bit](https://huggingface.co/mlx-community/chatterbox-turbo-8bit)
- [Marvis-Labs/marvis-tts](https://github.com/Marvis-Labs/marvis-tts)
- [Marvis-AI/marvis-tts-250m-v0.2](https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.2)
- [Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit](https://huggingface.co/Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit)
