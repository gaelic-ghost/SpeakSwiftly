# Higgs Audio v3 Official Pipeline Inventory

Date: 2026-06-24
Branch: `research/apple-speech-pipeline`

## Purpose

Map the official Higgs Audio v3 sources before any Swift or Apple-runtime port
work. This inventory treats Boson, Hugging Face, SGLang-Omni, and vLLM-Omni as
the source surfaces to understand first. Community MLX ports remain comparison
evidence only after this official map is understood.

The generated companion artifact is
[`official-pipeline-map-2026-06-24.json`](official-pipeline-map-2026-06-24.json).
It was produced by
[`../../../../../scripts/repo-maintenance/higgs-audio-v3/inspect-official-higgs-assets.py`](../../../../../scripts/repo-maintenance/higgs-audio-v3/inspect-official-higgs-assets.py)
without downloading model weights.

The first prompt-token parity fixture is
[`tokenizer-parity-fixture-2026-06-26.json`](tokenizer-parity-fixture-2026-06-26.json).
It was produced by
[`../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-tokenizer-parity-fixture.py`](../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-tokenizer-parity-fixture.py)
without downloading model weights.

The first synthetic codebook delay-pattern fixture is
[`codebook-delay-fixture-2026-06-26.json`](codebook-delay-fixture-2026-06-26.json).
It was produced by
[`../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-codebook-delay-fixture.py`](../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-codebook-delay-fixture.py).

The first no-weight codec/vocoder boundary fixture is
[`codec-vocoder-boundary-fixture-2026-06-28.json`](codec-vocoder-boundary-fixture-2026-06-28.json).
It was produced by
[`../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-codec-vocoder-boundary-fixture.py`](../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-codec-vocoder-boundary-fixture.py).

## Source Inventory

### Boson And Hugging Face

- Model card: <https://huggingface.co/bosonai/higgs-audio-v3-tts-4b>
- Model files: <https://huggingface.co/bosonai/higgs-audio-v3-tts-4b/tree/main>
- Prompting guide:
  <https://huggingface.co/bosonai/higgs-audio-v3-tts-4b/blob/main/PROMPTING.md>
- Boson overview:
  <https://docs.boson.ai/models/higgs-audio-tts/overview>
- Boson API:
  <https://docs.boson.ai/api-reference/text-to-speech/create-speech>

Files inspected from Hugging Face:

- `README.md`
- `PROMPTING.md`
- `config.json`
- `tokenizer_config.json`
- `tokenizer.json`
- `chat_template.jinja`
- `model.safetensors.index.json`

No safetensors weight payload was downloaded.

### Official Serving Sources

- SGLang-Omni Higgs cookbook:
  <https://sgl-project.github.io/sglang-omni/cookbook/higgs_tts.html>
- SGLang-Omni Higgs source:
  <https://github.com/sgl-project/sglang-omni/tree/main/sglang_omni/models/higgs_tts>
- vLLM-Omni Higgs recipe:
  <https://github.com/vllm-project/vllm-omni/blob/main/recipes/BosonAI/Higgs-Audio-V3-TTS.md>
- vLLM-Omni Higgs source:
  <https://github.com/vllm-project/vllm-omni/tree/main/vllm_omni/model_executor/models/higgs_audio_v3>

SGLang-Omni provides the clearest official four-stage serving pipeline:
preprocessing, audio encoder, TTS engine, and vocoder. vLLM-Omni provides a
second official decomposition with Stage 0 talker and Stage 1 code-to-waveform,
including synchronous and async chunk handoff behavior.

## Runtime Constants

### Model Identity

| Constant | Value | Source |
| --- | --- | --- |
| Model id | `bosonai/higgs-audio-v3-tts-4b` | Hugging Face |
| Architecture | `HiggsMultimodalQwen3ForConditionalGeneration` | `config.json` |
| Model type | `higgs_multimodal_qwen3` | `config.json` |
| Transformers version | `5.5.0` | `config.json` |
| Audio placeholder id | `-100` | `config.json`, SGLang, vLLM |
| Ignore index | `-100` | `config.json` |

### Qwen3 Text Decoder

| Constant | Value |
| --- | --- |
| Text model type | `qwen3` |
| Text architecture | `Qwen3ForCausalLM` |
| Dtype | `bfloat16` |
| Hidden size | `2560` |
| Intermediate size | `9728` |
| Hidden layers | `36` |
| Attention heads | `32` |
| KV heads | `8` |
| Head dimension | `128` |
| Text vocabulary size | `151936` |
| Max position embeddings | `32768` |
| Max window layers | `36` |
| BOS token id | `151643` |
| EOS token id | `151643` |
| Pad token id | `null` |
| RMSNorm epsilon | `1e-06` |
| RoPE theta | `1000000` |
| RoPE type | `default` |
| Attention dropout | `0.0` |
| Attention bias | `false` |
| Uses cache | `true` |
| Text embeddings tied | `true` |

### Audio Encoder And Codebooks

| Constant | Value | Source |
| --- | --- | --- |
| Audio encoder model type | `higgs_audio_encoder` | `config.json` |
| Encoder type | `discrete` | `config.json` |
| Codebooks | `8` | `config.json`, SGLang, vLLM |
| Codebook vocabulary size | `1026` | `config.json`, SGLang, vLLM |
| Real code values | `1024` | vLLM |
| Beginning-of-codebook id | `1024` | vLLM |
| End-of-codebook id | `1025` | vLLM |
| Mel/code entries per sample | `8` | `config.json` |
| Max chunk size | `50` | `config.json` |
| Output dimension | `2560` | `config.json` |
| Uses delay pattern | `true` | `config.json`, SGLang, vLLM |
| Audio embeddings tied | `true` | `config.json` |
| Codec checkpoint prefix | `tied.embedding.modality_embeddings.0.model.` | HF index, SGLang, vLLM |
| Audio embedding prefix | `tied.embedding.modality_embeddings.0.embedding` | HF index, vLLM |
| Audio sample rate | `24000` | SGLang codec source and model card |

### Weight Index

| Prefix | Count | Meaning |
| --- | ---: | --- |
| `body.layers.` | `396` | Qwen3 decoder body |
| `body.norm` | `1` | Qwen3 final norm |
| `tied.embedding.text_embedding` | `1` | Text embedding |
| `tied.embedding.modality_embeddings.0.embedding` | `1` | Fused audio-codebook embedding |
| `tied.embedding.modality_embeddings.0.model.` | `528` | Bundled codec/vocoder tensors |
| `tied.head` | `0` | No separate tied-head tensor in the index |

The codec/vocoder prefix is the key negative check from earlier MLX probing:
a transformer-body-only artifact is not enough to produce waveform output.

### Tokenizer And Special Tokens

`tokenizer_config.json` identifies the tokenizer class as `Qwen2Tokenizer`.
`tokenizer.json` reports a BPE tokenizer with 84 added tokens. These are the
speech-relevant special-token ids extracted from the official tokenizer:

| Token | Id |
| --- | ---: |
| `<|endoftext|>` | `151643` |
| `<|tts|>` | `151667` |
| `<|streaming_tts|>` | `151668` |
| `<|audio_cont_txt|>` | `151669` |
| `<|audio|>` | `151670` |
| `<|audio_end|>` | `151671` |
| `<|text|>` | `151672` |
| `<|text_end|>` | `151673` |
| `<|await_audio|>` | `151678` |
| `<|ref_audio|>` | `151679` |
| `<|ref_text|>` | `151680` |
| `<|emotion:elation|>` through `<|emotion:helplessness|>` | `151681` through `151701` |
| `<|style:singing|>`, `<|style:shouting|>`, `<|style:whispering|>` | `151704` through `151706` |
| `<|sfx:cough|>` through `<|sfx:sneeze|>` | `151707` through `151715` |
| `<|prosody:speed_very_slow|>` through `<|prosody:long_pause|>` | `151716` through `151723` |
| `<|prosody:expressive_high|>`, `<|prosody:expressive_low|>` | `151725`, `151726` |

Prompting rules from `PROMPTING.md`:

- All control tags use `<|category:tag|>`.
- Emotion, style, and most prosody tags are sentence-level.
- `sfx`, `pause`, and `long_pause` are inline.
- `sfx` tags come before the attached onomatopoeia.

## Pipeline Component Map

### Tokenizer

Swift should own tokenizer loading and parity checks against official Hugging
Face assets before any graph conversion. The first check should validate the
special-token ids above and the plain TTS prompt token layout.

### Prompt Builder

Official serving sources agree on these shapes:

- Plain TTS:
  `<|tts|> <|text|> target text tokens <|audio|>`
- Reference audio without transcript:
  `<|tts|> <|ref_audio|> delayed reference placeholders <|text|> target text tokens <|audio|>`
- Reference audio with transcript:
  `<|tts|> <|ref_text|> reference text tokens <|ref_audio|> delayed reference placeholders <|text|> target text tokens <|audio|>`

The placeholder value is `-100`, and the number of placeholders must match the
delayed reference-audio code row count, `raw frame count + codebook count - 1`.

### Decoder Prefill And Decode

The heavy graph candidate is the Qwen3-derived autoregressive decoder plus fused
multi-codebook embedding/head behavior. Swift should still own request lifecycle,
KV-cache ownership, prompt layout, graph boundary orchestration, and streaming
policy.

The first Core AI candidate should not be chosen until the fixture proves token
layout, prefill input embeddings, one decode-step shape, and sampled codebook
row semantics against official output metadata.

### Eight-Codebook Sampler

Official serving sources describe independent per-codebook sampling with
MusicGen-style delay-pattern handling, BOC/EOC ramp-in and wind-down, and
top-k/top-p policy. SGLang exposes `K_MAX = 1026`, `STOP_CODE = -1`, and
`NO_SEED = -1`; vLLM exposes the fixed BOC/EOC constants and async chunk
handoff defaults.

Swift or Accelerate should own this first unless a graph boundary proves a
measurable advantage. Keeping it Swift-owned makes delay-pattern tests, seed
behavior, stop handling, and codebook ordering visible.

The first checked-in synthetic delay fixture is
[`codebook-delay-fixture-2026-06-26.json`](codebook-delay-fixture-2026-06-26.json).
It pins a 3-frame by 8-codebook raw-code matrix, the 10-row delayed matrix, and
the round trip back to raw rows.

### Codec And Vocoder Decode

The codec/vocoder is the highest-risk boundary. Official sources load a bundled
Higgs Audio v2-style codec from the v3 checkpoint under
`tied.embedding.modality_embeddings.0.model.`. A port that reproduces text to
codebook rows but cannot decode those rows to 24 kHz PCM is not a useful
SpeakSwiftly backend.

The first no-weight boundary fixture is
[`codec-vocoder-boundary-fixture-2026-06-28.json`](codec-vocoder-boundary-fixture-2026-06-28.json).
It captures the bundled codec prefix, weight-entry counts, codebook axis order,
BOC/EOC filtering rule, 24 kHz sample rate, streaming chunk defaults, and the
remaining unknown decoded sample count, dtype, channel count, and container
questions. It still blocks runtime promotion until official serving comparison
captures waveform metadata.

### Waveform Post-Processing And Output

The Apple ownership split should be:

- Accelerate: small numeric kernels, fades, sample validation, and vector
  post-processing when Swift-side ownership is clearer than graph execution.
- CoreMedia/CoreAudio: timestamped PCM buffers, format descriptions, sample
  framing, and low-level audio interoperability.
- AVFoundation: file output, asset inspection, and playback integration.

Current official serving docs are not perfectly aligned on streaming container
language. Boson and SGLang current docs emphasize `pcm` for streaming, while
some model-card wording references streamed base64 WAV chunks. Treat streaming
container behavior as an explicit parity question instead of assuming one doc
settles it.

## First Artifacts To Build Next

1. Add a parity fixture plan for one reference-free English prompt. Done in
   [`parity-fixture-plan-2026-06-24.md`](parity-fixture-plan-2026-06-24.md).
2. Extend the inspector or a second probe to produce a tiny token-layout fixture
   from official tokenizer assets.
   Done in
   [`tokenizer-parity-fixture-2026-06-26.json`](tokenizer-parity-fixture-2026-06-26.json).
3. Produce a JSON fixture with prompt text, special-token ids, prompt token ids,
   expected prompt sections, model constants, and output-container expectations.
4. Compare the fixture against SGLang/vLLM official serving behavior before
   choosing the first Core AI graph boundary.
5. Extend the no-weight fixture set from prompt IDs into sampler state and
   codec/vocoder metadata.
   Done for delay-pattern layout in
   [`codebook-delay-fixture-2026-06-26.json`](codebook-delay-fixture-2026-06-26.json)
   and for codec/vocoder boundary metadata in
   [`codec-vocoder-boundary-fixture-2026-06-28.json`](codec-vocoder-boundary-fixture-2026-06-28.json).
   The next open item is official serving comparison with waveform metadata.

## Current Decision

Continue the official-source path. Do not port the community MLX implementation
file-for-file, do not add a Higgs case to `mlx-audio-swift`, and do not download
large model weights until the tokenizer, prompt, sampler, and codec/vocoder
boundaries are mapped well enough to make the download answer a specific
question.
