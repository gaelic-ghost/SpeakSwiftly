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

Current `Blaizzy/mlx-audio-swift` `main` behavior as checked on 2026-04-21.

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
| Text chunking before synthesis | Yes. First chunk target `16` words, later chunks `28`, min `8`, max `40` | No comparable runtime chunk planner in the Chatterbox model path | Not documented as the intended inference path |
| Streaming cadence | `0.18s` resident interval for standard non-Qwen resident playback | Generic TTS streaming helpers default to `2.0s`, but current Chatterbox behavior is effectively whole-waveform-per-call for each chunk | No authoritative cadence knob documented in the model card |
| Caller-facing default generation parameters | `maxTokens 4096`, `temperature 0.9`, `topP 1.0`, `repetitionPenalty 1.05` | `ChatterboxModel.defaultGenerationParameters` sets `temperature 0.8` | Model card emphasizes usage and capabilities, not these inference defaults |
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
  - runtime-owned chunking
  - much tighter live cadence
  - warmer sampling (`temperature 0.9`, `topP 1.0`) than the current `mlx-audio-swift` Chatterbox default surface

## Marvis

| Surface | SpeakSwiftly | mlx-audio-swift | model repo/card |
| --- | --- | --- | --- |
| Live generation shape | Native streaming backend plus SpeakSwiftly-specific scheduling and playback heuristics | Native chunked streaming generation path | Model card explicitly describes real-time streaming TTS |
| Native incremental audio streaming | Yes, via upstream Marvis streaming path | Yes | Yes, that is a headline feature in the model repo and card |
| Text chunking before synthesis | No local text chunk planner in the Marvis path | No. Marvis processes the full text context passed into the request | Model card explicitly says Marvis processes full text context rather than regex chunking |
| Streaming cadence | `0.10s` for first drained live Marvis, `0.18s` for overlap follower and standard resident cadence | Core Marvis streaming path uses `0.5s`; generic wrapper defaults to `2.0s` | Model docs emphasize streaming, but do not publish a canonical cadence number |
| Caller-facing default generation parameters | `maxTokens 4096`, `temperature 0.9`, `topP 1.0`, `repetitionPenalty 1.05` | `defaultGenerationParameters` returns `maxTokens 750`, `temperature 0.9`, `topP 0.8` | Published MLX config includes generic generation metadata like `temperature 1.0`, `top_k 50`, `top_p 1.0`, but that is not the same thing as the current MLX Swift sampling path |
| Effective Marvis inference parameters | Local policy object exists, but upstream Marvis currently ignores most caller generation parameters | Current Marvis implementation hardcodes `TopPSampler(temperature: 0.9, topP: 0.8)` and computes `maxAudioFrames 750` internally | Model repo shows a `temperature` and `topk` generate surface in Python, but that is a separate implementation surface |
| Max generated audio frame budget | Local policy says `4096`, but not actually honored by current upstream Marvis wrapper | `maxAudioFrames = Int(60000 / 80.0) = 750` | MLX model config and repo framing align with 12.5 fps audio-token timing and a 24 kHz Mimi codec stack |
| Input sequence budget | No local extra cap; we rely on upstream model limit and runtime scheduling | Input must stay below `2048 - 750 = 1298` sequence positions in the current MLX Swift Marvis path | HF config for the MLX model shows `max_position_embeddings 2048` |
| Context window | We preserve full normalized text instead of pre-chunking | Full prompt context is prepended and processed in one contextual sequence | Model card explicitly says this is a core design goal |
| Codec and sliding-window metadata | No local override | Uses the model artifact as loaded | HF config shows Mimi codec metadata including `sliding_window 250` and `_frame_rate 12.5` |
| Voice lane behavior | SpeakSwiftly keeps two warm resident Marvis lanes and routes by vibe | One model instance has mutable caches; our runtime compensates with two resident model objects | Model card focuses on conversational voices and cloning behavior, not our dual-lane runtime policy |
| Playback stabilization | SpeakSwiftly adds a `firstDrainedLiveMarvis` tuning profile with raised startup and resume floors | No comparable playback policy in `mlx-audio-swift` | Not part of the model repo or card surface |

### Marvis Notes

- Marvis is the opposite of Chatterbox in one key respect: the upstream `mlx-audio-swift` path really does stream audio progressively.
- Our largest Marvis diffs are not the nominal generation-parameter values in `GenerationPolicy`. The largest real diffs are:
  - much tighter streaming cadence
  - dual-lane resident scheduling
  - custom playback thresholds for startup and recovery
- Several local Marvis parameter values are currently more descriptive than operative because upstream `MarvisTTSModel.generate(...)` and `generateStream(...)` ignore the caller-supplied `generationParameters` and use internal sampling values instead.
- If we want Marvis generation knobs in `SpeakSwiftly` to be real knobs, the first prerequisite is changing the upstream Marvis Swift wrapper so it honors caller parameters.

## Practical Conclusions

1. Chatterbox Turbo is not currently native-streaming in the `mlx-audio-swift` path we use. `SpeakSwiftly` fakes live behavior by chunking text and yielding completed chunk waveforms as each chunk finishes.
2. Marvis is currently native-streaming in the `mlx-audio-swift` path we use. `SpeakSwiftly` then layers its own tighter cadence and playback-stability policy on top.
3. "Upstream" must always be split into two labels in future notes:
   - `mlx-audio-swift`
   - model repo/card
4. The settings that matter most to align next are:
   - Chatterbox: chunk sizing, cadence, and whether to stay intentionally more aggressive than `mlx-audio-swift`
   - Marvis: whether we want the wrapper to honor caller generation parameters instead of silently using internal defaults

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
