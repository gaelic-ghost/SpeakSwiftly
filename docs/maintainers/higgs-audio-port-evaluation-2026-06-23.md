# Higgs Audio V3 Port Evaluation

Date: 2026-06-23
Branch: `research/higgs-audio-mlx-port`

## Purpose

Evaluate whether Higgs Audio v3 TTS should become a candidate SpeakSwiftly
generation backend through MLX first, then Core AI if the MLX probe proves the
model is worth deeper Apple-platform port work.

This is a backend-extension research note. It does not add a runtime backend,
does not download model weights into the repository, and does not change the
current Qwen3 resident backend defaults.

## Summary

Higgs Audio v3 is a credible future SpeakSwiftly research lane. It is a
Qwen3-derived multimodal autoregressive TTS model with clear architecture
metadata, controllable speech tags, multilingual scope, and at least one
third-party MLX-labeled 4-bit conversion already visible on Hugging Face.

The next useful step is MLX, not Core AI. The MLX path can answer the first
practical question: whether a local Apple-silicon runtime can load and generate
acceptable speech from the existing 4-bit candidate without first building a
full conversion pipeline.

Core AI is the relevant newer Apple custom-model deployment path for a later
first-party port. Local Xcode 27 beta documentation and tools describe Core AI
as a framework for `.aimodel` and `.aimodelc` assets, with specialization,
caching, PyTorch-extension conversion, `coreai-build`, Xcode model inspection,
the Core AI Debugger, a debug gauge, and an Instruments template for CPU, GPU,
and Neural Engine profiling.

## Candidate Ranking

1. Higgs Audio v3 through MLX: best near-term research path.
2. Higgs Audio v3 through Core AI: plausible later first-party port path.
3. Higgs Audio v3 through Core ML: keep only as a legacy/reference comparison
   unless Core AI tooling proves blocked for this model.

## Model Inventory

Primary model:

- Hugging Face: `bosonai/higgs-audio-v3-tts-4b`
- Pipeline: `text-to-speech`
- Library: `transformers`
- Architecture: `HiggsMultimodalQwen3ForConditionalGeneration`
- Model type: `higgs_multimodal_qwen3`
- Parameter metadata: about 4.65B BF16 parameters
- Storage metadata: about 18.6 GB used
- License: Boson Higgs Audio v3 Research and Non-Commercial License
- Repo files inspected: `README.md`, `PROMPTING.md`, `config.json`,
  `tokenizer_config.json`, `model.safetensors.index.json`

Architecture signals from the model card:

- Qwen3-style autoregressive decoder.
- 36 layers, hidden size 2560, GQA 32 query heads / 8 KV heads.
- 8 audio codebooks, 1026-token audio vocabulary per codebook.
- 25 fps audio-token frame rate.
- 24 kHz waveform output.
- Delay-pattern handling for multi-codebook audio tokens.
- Inline control tags for emotion, style, prosody, pauses, and sound effects.

Related conversion signal:

- Hugging Face has `Reza2kn/Higgs-Audio-v3-TTS-4bit-MLX`, tagged as a 4-bit MLX
  quantization of `bosonai/higgs-audio-v3-tts-4b`.
- Treat that artifact as a useful starting probe, not as production evidence.
  It needs local load, generation, quality, latency, memory, and license checks.

### Higgs 4-bit MLX Candidate

Candidate model:

- Hugging Face: `Reza2kn/Higgs-Audio-v3-TTS-4bit-MLX`
- Pipeline: `text-to-speech`
- Library: `transformers`
- Architecture: `higgs_multimodal_qwen3`
- Storage metadata: about 2.06 GB used
- Repo files inspected: `README.md`, `config.json`, `quantization_config.json`,
  `functional_test_report.json`, `quant_error_report.json`,
  `studio_mlx_smoke.json`, `tensor_manifest.json`,
  `coreml_transformers_blocker_probe.json`, `tokenizer_config.json`

The candidate is not a drop-in runtime. Its own README says it is a
transformer-body quantized artifact and that runtime integration is still
required for Higgs custom multi-codebook TTS generation.

Quantization scope:

- Quantized scope: `body.layers.*` 2D transformer weights.
- Preserved scope: codec/vocoder, fused modality embedding/head, norms, biases,
  and non-2D tensors.
- Quantized parameter fraction: about 78.05%.
- Quantized parameters: 3,633,315,840 out of 4,654,850,537 parameters seen.

Published smoke/quality report signals:

- `functional_test_report.json` tested 24 tensors.
- Mean weight relative L2: about 0.0690.
- Max weight relative L2: about 0.0763.
- Mean matmul relative L2: about 0.0689.
- Max matmul relative L2: about 0.0755.
- `quant_error_report.json` lists 252 quantized tensors, mean relative L2 about
  0.0670, max relative L2 about 0.1033, and max absolute error about 0.0751.

Loader blocker signal:

- `coreml_transformers_blocker_probe.json` says vanilla Transformers in the
  tested environment did not recognize `higgs_multimodal_qwen3` for AutoConfig,
  AutoModelForCausalLM, or AutoModelForTextToWaveform.
- AutoProcessor loaded as `Qwen2Tokenizer`.
- The candidate README points to SGLang-Omni or a custom loader for runtime
  integration.

Practical conclusion:

- The artifact is worth a config/layout probe because the size is manageable and
  the author published useful validation metadata.
- It is not yet evidence that SpeakSwiftly can load Higgs through the current
  Swift MLX stack. The first local probe should stop at metadata/config loading
  before any 2 GB weight download.

## Local MLX Preflight

Local preflight on 2026-06-23:

- Free space before weight download: about 23 GB available on the data volume.
- Non-weight candidate files: 14 files totaling about 11.7 MB.
- Candidate weight file: `quantized.safetensors`, about 2.0 GB.
- Local Python packages checked with system `python3`: `mlx`, `mlx_lm`,
  `transformers`, `huggingface_hub`, and `torch` were not installed.
- Downloaded non-weight candidate files only into a system temporary directory
  for inspection.
- Did not download `quantized.safetensors`.

Config/tokenizer findings:

- `config.json` names `higgs_multimodal_qwen3` and
  `HiggsMultimodalQwen3ForConditionalGeneration`.
- Text config matches the 4B Qwen3-style body: hidden size 2560, 36 layers,
  32 attention heads, 8 KV heads, 151,936 text vocab entries, and 32,768 max
  position embeddings.
- The public config does not expose `audio_tokenizer`, `codebook_size`, or
  `num_codebooks` values.
- `tokenizer.json` uses a BPE model, NFC normalizer, sequence pre-tokenizer, and
  ByteLevel post-processor.
- The tokenizer has 84 added tokens. The first special tokens include
  `<|endoftext|>`, `<|im_start|>`, and `<|im_end|>`.

Preflight decision:

- Do not download the 2.0 GB weights yet.
- The immediate blocker is not disk. The blocker is runtime shape: the candidate
  still needs either SGLang-Omni integration or a custom Swift/MLX loader for
  `higgs_multimodal_qwen3`, multi-codebook delayed generation, and waveform
  decode.
- The next useful proof is source/runtime inventory for Higgs' loader path, not
  a weight-only download.

## Local MLX Metadata Probe

Temporary environment:

- Location: system temporary directory outside the repository
- Package cache: system temporary directory outside the repository
- Installed source: `mlx-audio` from
  `Blaizzy/mlx-audio@412cf7cd381c2a3f6a8189af04a95af24cb415b6`
- Installed versions: `mlx-audio 0.4.4`, `mlx 0.31.2`, `mlx-lm 0.31.3`,
  `transformers 5.12.1`, `huggingface-hub 1.20.1`
- No model weights downloaded for this probe.

Executable checks that passed:

- `mlx_audio.tts.utils.get_model_and_args("higgs_multimodal_qwen3", ...)`
  resolves to `model_type == "higgs_audio_v3"` and exposes
  `mlx_audio.tts.models.higgs_audio_v3.Model`.
- The downloaded candidate `config.json` parses through
  `HiggsAudioV3Config.from_dict(...)` as eight codebooks, 1026-token audio
  codebooks, BOC/EOC ids 1024/1025, 24 kHz output, hidden size 2560, 36 layers,
  32 attention heads, 8 KV heads, vocab size 151,936, and rope theta 1,000,000.
- The candidate `tokenizer.json` loads through `tokenizers` and
  `PreTrainedTokenizerFast`; the prompt builder finds required Higgs v3 special
  tokens. Observed ids: `<|tts|>` 151667, `<|audio|>` 151670, `<|text|>` 151672,
  and `<|ref_audio|>` 151679.
- Delay-pattern round trip passed for synthetic eight-codebook rows.
- Prompt assembly placed one placeholder per delayed reference-audio row.
- A tiny synthetic Higgs v3 MLX model ran one forward pass, produced audio-logit
  shape `[1, 4, 10]`, and completed one delayed sampler step.

Probe warning:

- `transformers` reported that PyTorch was not installed. That is acceptable for
  this metadata-level proof because only tokenizers/config utilities and MLX
  execution were used.

## Runtime Source Inventory

The strongest MLX lead is `Blaizzy/mlx-audio` at commit
`412cf7cd381c2a3f6a8189af04a95af24cb415b6`. It contains a concrete
`mlx_audio/tts/models/higgs_audio_v3/` implementation, not only a model-name
remapping.

Files inspected:

- `mlx_audio/tts/models/higgs_audio_v3/README.md`
- `mlx_audio/tts/models/higgs_audio_v3/config.py`
- `mlx_audio/tts/models/higgs_audio_v3/generation.py`
- `mlx_audio/tts/models/higgs_audio_v3/model.py`
- `mlx_audio/tts/models/higgs_audio_v3/prompt.py`
- `mlx_audio/tts/tests/test_higgs_audio_v3.py`
- `mlx_audio/tts/utils.py`

MLX implementation signals:

- `MODEL_REMAPPING` maps `higgs_multimodal_qwen3` to `higgs_audio_v3`.
- The Higgs v3 config parser extracts Qwen3 text config and audio encoder
  config values from the upstream `config.json`.
- The model wraps `mlx_lm.models.qwen3.Qwen3Model`, adds one fused
  multi-codebook audio embedding table, and reuses that table as an audio
  logits head.
- The loader creates a `PreTrainedTokenizerFast` from `tokenizer.json` and
  loads the Higgs audio codec from either an `audio_tokenizer/` directory or the
  Higgs checkpoint.
- Weight sanitization maps upstream keys from `tied.embedding.text_embedding`,
  `body.layers`, `body.norm`, and
  `tied.embedding.modality_embeddings.0.embedding` into the MLX model shape.
  It intentionally skips the upstream modality projection and tied head keys.
- Prompt assembly uses Higgs special tokens for `<|tts|>`, `<|ref_audio|>`,
  `<|text|>`, and `<|audio|>`, with `-100` placeholders for delayed reference
  audio-code rows.
- The sampler implements independent per-codebook sampling, delay-pattern
  ramp-in, end-of-code wind-down, top-k, and top-p.
- The generation loop builds prompt embeddings, prefills a Qwen3 cache, samples
  delayed audio rows, embeds each sampled row for the next autoregressive step,
  reverses the delay pattern, decodes through the Higgs codec, and yields a
  `GenerationResult`.
- The README exposes both plain TTS and zero-shot voice cloning APIs, including
  reusable preencoded reference audio codes.

The `mlx-audio` tests cover the exact pieces a Swift port would need to mirror:
source-config parsing, loader remapping, delay-pattern round trip, sampler
ramp-in/wind-down, prompt placeholder placement, upstream weight-key
sanitization, fused embedding/head shape, tiny forward shape, reference-audio
encoding, and preencoded reference-code reuse.

Related CUDA/server runtime references:

- `sgl-project/sglang-omni` at commit
  `86e73bdbece7875255434e9730876c3892fec125` has a Higgs TTS pipeline with
  preprocessing, audio encoder, autoregressive TTS engine, and vocoder stages.
- `vllm-project/vllm-omni` at commit
  `d35cdd2dabb6bc8f5321a2c0c972d4ef1497e42e` has a Higgs Audio v3
  two-stage pipeline: Stage 0 text to 8-codebook codec rows, Stage 1 codec rows
  to 24 kHz PCM, with sync and async-chunk handoff modes.

Practical conclusion:

- The first metadata-level MLX proof succeeded. The next proof is a heavier
  weight-loading and one-sentence generation run through `mlx-audio`'s Python
  Higgs v3 path.
- A Swift port is no longer pure architecture discovery. It has a concrete MLX
  Python reference implementation to mirror if the Python probe succeeds.
- Streaming remains a separate question: the `mlx-audio` implementation yields
  one final `GenerationResult`, while the vLLM-Omni server path has explicit
  async chunking and overlap/holdback logic.

## MLX Path

Higgs should start as an MLX probe because SpeakSwiftly already depends on
`mlx-swift`, `mlx-audio-swift`, and the MLX-backed Qwen3 TTS path.

Why it fits SpeakSwiftly's current shape:

- `SpeechBackend` already maps public backend identifiers to resident model
  repositories.
- `ModelFactory.loadResidentModels(for:)` already has the right high-level hook
  for resident MLX models.
- The existing benchmark and E2E lanes can compare latency, memory, chunking,
  and audio quality against Qwen3 once a Higgs generation adapter exists.

What is not known yet:

- Whether the third-party MLX-labeled Higgs artifact is loadable by the current
  Swift MLX/MLXLM stack without Python-only custom code.
- Whether the model's custom `higgs_multimodal_qwen3` architecture is implemented
  in a form that can be reused or ported cleanly in Swift.
- Whether Higgs' 8-codebook / 25 fps audio-token path can stream chunks in the
  shape SpeakSwiftly expects.
- Whether 4-bit quality is acceptable for Gale's local speech use.

Recommended MLX probe:

1. Set up a temporary Python environment with `mlx-audio` and its MLX
   dependencies outside the repository.
2. Run the `mlx-audio` Higgs v3 loader against the upstream model metadata
   without committing any downloaded artifacts.
3. If the loader reaches weight resolution cleanly, download the minimum model
   files into the Hugging Face cache and generate one short sentence to a temp
   WAV file.
4. Record time to first audio, total generation time, peak process memory, MLX
   memory, sample rate, and audible notes.
5. If Python MLX succeeds, start a Swift port plan from the concrete
   `mlx_audio/tts/models/higgs_audio_v3` config, prompt, generation, and model
   files.

## Core AI Path

Core AI is now the Apple custom-model path to evaluate after MLX.

Local Xcode 27 beta evidence:

- Xcode documentation search exposes `/documentation/CoreAI`.
- `CoreAI.framework` is present in the macOS 27 SDK.
- `coreai-build compile --help` is available through the Xcode beta toolchain.
- `coreai-build` accepts `.aimodel` inputs and emits `.aimodelc` compiled assets.
- The compile tool supports platform, minimum deployment version, preferred
  compute (`gpu`, `neural-engine`, or `none`), architecture selection, and an
  `--expect-frequent-reshapes` hint.

Why Core AI matters here:

- It is designed for newer neural network architectures and inference
  techniques on Apple silicon.
- It has a Swift runtime API around `AIModel`, `InferenceFunction`, `NDArray`,
  specialization, and caches.
- Its tooling is explicitly built around CPU, GPU, and Neural Engine profiling.
- It has a PyTorch-oriented model-preparation story that may fit a first-party
  Higgs conversion better than older Core ML graph-splitting work.

What remains unknown:

- Whether Higgs' custom multimodal Qwen3 architecture can be converted to
  `.aimodel` without unsupported operations or custom Python-only runtime pieces.
- Whether dynamic shapes, autoregressive state, codebook delay patterns, and
  audio decoder stages map cleanly to Core AI functions.
- Whether Neural Engine specialization helps the actual Higgs stages, rather
  than only looking promising from the framework surface.

Recommended Core AI probe, after MLX earns it:

1. Locate or build the smallest PyTorch/Higgs forward path for one fixed prompt.
2. Identify explicit graph boundaries for tokenizer, prompt assembly, decoder,
   codebook handling, and waveform decode.
3. Convert one narrow function to `.aimodel`.
4. Use Core AI Debugger for structure and numeric comparison.
5. Use `coreai-build` for ahead-of-time compilation experiments.
6. Use the Core AI instrument to verify actual CPU, GPU, and Neural Engine
   dispatch.

## SpeakSwiftly Integration Shape If Higgs Advances

Treat Higgs as a separate experimental backend family, not as a Qwen3 model
repo swap.

Likely backend names:

- `higgs_audio_v3_experimental`
- `higgs_audio_v3_4bit_mlx_experimental`

Likely source layout if a probe earns integration:

- `Sources/SpeakSwiftly/Generation/HiggsAudio/`
- `Tests/SpeakSwiftlyTests/Generation/HiggsAudio/`
- optional E2E tests under `Tests/SpeakSwiftlyTests/E2E/HiggsAudio/`

Do not wire Higgs into default backend selection until local evidence proves it
beats or complements the current Qwen3 variants for a concrete use case.

Do not wire Higgs into profile creation until its reference-audio, voice-clone,
and control-token semantics are understood well enough to preserve
SpeakSwiftly's stable profile model.

## Risks

- Higgs' non-commercial license may block production or revenue-generating
  SpeakSwiftly uses without a commercial license.
- Higgs' custom Transformers architecture may require a real Swift/MLX model
  implementation, not just weight conversion.
- A 4.65B model may be too heavy for always-resident local speech on 24 GB
  machines unless the 4-bit path is both high quality and memory stable.
- Core AI is beta-surface work in the Xcode 27 toolchain and may change before
  stable release.
- Core AI could still lose to MLX because of conversion effort, graph split
  overhead, unsupported operations, or poor dispatch for the actual model stages.

## Recommended Next Slice

Start with the MLX candidate.

The first slice should be read-only plus one smallest possible local probe:

1. Inspect `Reza2kn/Higgs-Audio-v3-TTS-4bit-MLX` metadata and small config files.
2. Check whether its architecture and tokenizer files match standard MLX
   loading conventions or require custom Python.
3. Set up a temporary Python `mlx-audio` environment and run its Higgs v3 loader
   as the first executable proof.
4. If it looks loadable, run one disk-space check before downloading weights.
5. Download the minimum required model files to the Hugging Face cache, not the
   repository.
6. Generate one short English sentence to a local temp WAV file.
7. Compare against the current Qwen3 0.6B and 1.7B benchmark shape before any
   runtime integration.

Only start a Core AI Higgs branch after the MLX probe proves the model is worth
keeping in the candidate set.

## Sources

- Higgs Audio v3 TTS model card:
  https://huggingface.co/bosonai/higgs-audio-v3-tts-4b
- Higgs Audio v3 4-bit MLX candidate:
  https://huggingface.co/Reza2kn/Higgs-Audio-v3-TTS-4bit-MLX
- MLX Swift:
  https://github.com/ml-explore/mlx-swift
- MLX documentation:
  https://ml-explore.github.io/mlx/build/html/index.html
- MLX Audio:
  https://github.com/Blaizzy/mlx-audio
- SGLang-Omni:
  https://github.com/sgl-project/sglang-omni
- vLLM-Omni:
  https://github.com/vllm-project/vllm-omni
- Core AI local docs:
  `/documentation/CoreAI`
- Core AI integration local docs:
  `/documentation/CoreAI/integrating-on-device-ai-models-in-your-app-with-core-ai`
- Core AI compile local docs:
  `/documentation/CoreAI/compiling-core-ai-models-ahead-of-time`
- Core AI profiling local docs:
  `/documentation/CoreAI/inspecting-debugging-and-profiling-core-ai-models`
