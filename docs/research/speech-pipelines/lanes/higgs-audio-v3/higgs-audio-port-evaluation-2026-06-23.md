# Higgs Audio V3 Port Evaluation

Date: 2026-06-23
Branch: `research/higgs-audio-mlx-port`

## Purpose

Evaluate whether Higgs Audio v3 TTS should become a candidate SpeakSwiftly
generation backend through a first-party Apple-platform port of the official
Boson/Hugging Face model and pipeline. Community MLX ports are useful evidence,
but they are no longer the implementation path to trust or inherit.

This is a backend-extension research note. It does not add a runtime backend,
does not download model weights into the repository, and does not change the
current Qwen3 resident backend defaults.

## Summary

Higgs Audio v3 is a credible future SpeakSwiftly research lane. It is a
Qwen3-derived multimodal autoregressive TTS model with clear architecture
metadata, controllable speech tags, multilingual scope, and an official Boson
model card that documents the intended architecture and usage shape.

The next useful step is no longer to depend on `mlx-audio` or
`mlx-audio-swift`. The primary plan is to inspect the official Boson/Hugging
Face assets and pipeline surface, then design a Swift-native runtime that uses
Core AI where model graph execution fits, Accelerate where small numeric
support kernels are better kept in-process, and CoreMedia/CoreAudio/AVFoundation
for audio buffers, timing, file output, and playback integration.

Core AI is the relevant Apple custom-model deployment path for the first-party
port. Local Xcode 27 beta documentation and tools describe Core AI as a
framework for `.aimodel` and `.aimodelc` assets, with specialization, caching,
PyTorch-extension conversion, `coreai-build`, Xcode model inspection, the Core
AI Debugger, a debug gauge, and an Instruments template for CPU, GPU, and Neural
Engine profiling.

## Candidate Ranking

1. Higgs Audio v3 through a first-party Swift/Core AI pipeline: primary path.
2. Higgs Audio v3 through Swift plus Accelerate and Apple audio frameworks:
   support path for tokenizer, sampler, codec glue, post-processing, buffers,
   playback, and file output around Core AI graph execution.
3. Higgs Audio v3 through Core ML: legacy/reference comparison only if Core AI
   tooling proves blocked for a required graph.
4. Higgs Audio v3 through community MLX ports: evidence and comparison only,
   not a trusted implementation dependency.

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

## Local MLX Weight-Load Probe

The 4-bit candidate weight was downloaded into temporary storage for a local
load probe. It was not copied into the repository.

Candidate artifact finding:

- Hugging Face dry-run reported one safetensors file:
  `quantized.safetensors`, about 2.0 GB.
- The candidate `model.safetensors.index.json` maps all weights to
  `model.safetensors`, not `quantized.safetensors`.
- For the local temp probe only, `model.safetensors` was symlinked to
  `quantized.safetensors` so `mlx-audio` could attempt the load path.

Live-service safety:

- The running SpeakSwiftly service was asked to unload resident models before
  the 4B-class load probe.
- After the probe, the service was asked to reload resident models and reported
  `resident_model_ready` on `qwen3_big_8bit`.

Load results:

- `mlx_audio.tts.load(local_path, lazy=True, strict=False)` failed before weight
  loading because local-path loading used `config.json`'s
  `higgs_multimodal_qwen3` model type directly and did not apply the
  `MODEL_REMAPPING` entry.
- `mlx_audio.tts.load(local_path, lazy=True, strict=False,
  model_type="higgs_audio_v3")` reached the Higgs v3 post-load hook.
- The post-load hook failed while constructing the Higgs audio codec because the
  safetensors file did not contain expected codec/vocoder tensors, beginning
  with
  `tied.embedding.modality_embeddings.0.model.acoustic_decoder.block.0.conv_t1.bias`.

Practical conclusion:

- `Reza2kn/Higgs-Audio-v3-TTS-4bit-MLX` is not a self-contained generation
  artifact for the inspected `mlx-audio` runtime.
- The 4-bit artifact can still be useful for transformer-body port work, but it
  needs either the original codec/vocoder tensors, an `audio_tokenizer/`
  directory in the expected layout, or a loader change that obtains the codec
  from the upstream/base model separately.
- Do not spend time trying one-sentence generation from this candidate alone
  until the codec/vocoder source is resolved.

## Revised First-Party Apple Port Direction

Decision on 2026-06-24:

- Do not treat `mlx-audio` or `mlx-audio-swift` as trusted porting work.
- Treat community MLX implementations as reference material only: useful for
  identifying likely tensor names, graph boundaries, sampler behavior, and
  failure modes, but not as an implementation to inherit.
- Port from the official Boson/Hugging Face model and official runtime surface
  first.
- Prefer Swift-owned orchestration over Python-owned runtime behavior.

Target runtime shape:

- Core AI owns the heavy model graph candidates that can be compiled,
  specialized, cached, debugged, and profiled with Apple tooling.
- Swift owns prompt construction, input validation, request lifecycle, sampling
  policy, graph boundary orchestration, streaming policy, and SpeakSwiftly
  backend integration.
- Accelerate owns small local numeric work only when it is simpler and more
  transparent than forcing that work into a model graph, such as vector
  post-processing, softmax/top-k helpers if needed, fades, resampling-adjacent
  utilities, or validation probes.
- CoreMedia owns timestamped sample buffers and format descriptions when the
  port reaches streamed audio chunks.
- CoreAudio owns low-level audio format, PCM buffer, and device-facing
  interoperability where SpeakSwiftly needs direct audio control.
- AVFoundation owns higher-level file output, asset inspection, and playback
  integration where it is already the right Apple abstraction.

First-party component map to recover from official sources:

- Official config and tokenizer files from `bosonai/higgs-audio-v3-tts-4b`.
- Official Hugging Face or Boson pipeline code path for
  `HiggsMultimodalQwen3ForConditionalGeneration`.
- Text/chat template and Higgs control-token semantics.
- Prompt/reference-audio assembly rules.
- Qwen3-derived decoder graph, including cache shape and prefill/decode
  boundaries.
- Fused multi-codebook audio embedding and output head.
- Eight-codebook delayed audio-token sampler and stop/wind-down semantics.
- Higgs audio tokenizer, codec, vocoder, or equivalent waveform decoder source.
- Reference-audio encode path for voice cloning.
- Waveform decode, post-processing, and sample-rate expectations.

Practical consequence:

- The first successful proof should be a tiny official-pipeline parity harness,
  not a community-port generation demo.
- The Core AI exploration should begin as graph-boundary discovery from the
  official model, then move one narrow function at a time into `.aimodel`.
- Swift-side tests should compare tokenizer IDs, prompt embeddings or prompt
  token layout, delayed code rows, and short waveform metadata against official
  reference outputs before any SpeakSwiftly backend is exposed.

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
  loader-composition proof that pairs the 4-bit transformer body with the
  codec/vocoder assets expected by `mlx-audio`.
- A Swift port is no longer pure architecture discovery. It has a concrete MLX
  Python reference implementation to mirror if the Python probe succeeds.
- Streaming remains a separate question: the `mlx-audio` implementation yields
  one final `GenerationResult`, while the vLLM-Omni server path has explicit
  async chunking and overlap/holdback logic.

## Community MLX Reference Path

Community MLX ports are reference material only. They can help identify tensor
layout, graph boundaries, expected sampler behavior, and possible failure
modes, but they should not define the trusted implementation surface.

Why this evidence is still useful:

- It shows one plausible decomposition of Higgs into config parsing, Qwen3
  decoder execution, fused multi-codebook audio embeddings, delay-pattern
  sampling, prompt/reference handling, and codec decode.
- It gives concrete names and shapes to compare against the official Boson/HF
  assets.
- It provides negative evidence: the inspected 4-bit artifact was not
  self-contained for waveform generation through the inspected Python MLX
  loader.

What not to do:

- Do not start the Apple port by porting `mlx-audio` source file-for-file.
- Do not add a Higgs case to `mlx-audio-swift` as the first implementation
  strategy.
- Do not treat successful community MLX loading as proof that the official
  Boson/HF pipeline has been understood.
- Do not spend more time on the 4-bit MLX artifact until the official codec and
  waveform decode path is mapped.

### Swift Dependency Surface Check

`SpeakSwiftly` now pins `gaelic-ghost/mlx-audio-swift` to
`0.101.0-gaelic.1`, which resolves to commit
`3f6b0553188a921f635df54b5e20442001037336`.

Useful surfaces in the resolved Swift package:

- `MLXAudioTTS/Models/Qwen3/` already has a Qwen3 decoder stack with cache
  support, RoPE config, tied-embedding handling, and a `SpeechGenerationModel`
  shape.
- `MLXAudioTTS/Models/MossTTS/` already has public delay/de-delay helpers for
  multi-codebook audio token rows and a tokenizer-adapter pattern for
  audio-placeholder prompts.
- `MLXAudioTTS/Models/Qwen3TTS/` already has a Qwen3-family speech generation
  model and speech-tokenizer implementation.
- `MLXAudioCodecs/` includes several codec implementations, including
  FishS1DAC, Mimi, SNAC, DACVAE, Encodec, Vocos, and Descript.

Not present in the resolved Swift package:

- No `Higgs` or `higgs_multimodal_qwen3` model implementation.
- No direct Swift equivalent of the Python `mlx_audio/tts/models/higgs_audio_v3`
  config, prompt builder, fused multi-codebook embedding/head, sampler, or
  Higgs codec loader.

Practical conclusion:

- The dependency bump does not make Higgs a drop-in backend.
- The resolved Swift package is useful as comparative Apple/MLX code, especially
  for Qwen3-like cache handling and multi-codebook helper patterns.
- The trusted path remains a first-party Swift/Core AI port from official
  Boson/HF sources.

Optional community-reference probe:

1. Use community MLX only to cross-check tensor names and sampler behavior after
   the official Boson/HF source path has been mapped.
2. Keep all downloaded community artifacts outside the repository.
3. Record mismatches as questions against the official pipeline instead of
   changing the Swift design to match the community port.

## Core AI Path

Core AI is now the primary Apple custom-model path to evaluate for the
first-party Higgs port.

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

Recommended Core AI probe:

1. Locate the official Boson/HF runtime source for one fixed prompt and one
   reference-free TTS request.
2. Identify explicit graph boundaries for tokenizer, prompt assembly, decoder
   prefill, decoder step, codebook handling, codec/vocoder decode, and waveform
   post-processing.
3. Build a Swift-owned parity fixture from official output metadata before
   converting any graph.
4. Convert one narrow function to `.aimodel`.
5. Use Core AI Debugger for structure and numeric comparison.
6. Use `coreai-build` for ahead-of-time compilation experiments.
7. Use the Core AI instrument to verify actual CPU, GPU, and Neural Engine
   dispatch.

## SpeakSwiftly Integration Shape If Higgs Advances

Treat Higgs as a separate experimental backend family, not as a Qwen3 model
repo swap.

Likely backend names:

- `higgs_audio_v3_experimental`
- `higgs_audio_v3_coreai_experimental`
- `higgs_audio_v3_apple_experimental`

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
- Higgs' custom Transformers architecture may require a real first-party Swift
  runtime and Core AI graph decomposition, not just weight conversion.
- A 4.65B model may be too heavy for always-resident local speech on 24 GB
  machines unless a compressed or staged runtime is both high quality and memory
  stable.
- Core AI is beta-surface work in the Xcode 27 toolchain and may change before
  stable release.
- Core AI could still lose to a simpler GPU runtime because of conversion
  effort, graph split overhead, unsupported operations, or poor dispatch for the
  actual model stages.
- Official Hugging Face pipeline metadata may not be enough to reproduce Boson's
  serving behavior without additional upstream source inspection.
- The codec/vocoder path is the highest-risk missing map item. A port that only
  reproduces text-to-codebook generation is not a useful SpeakSwiftly backend.

## Recommended Next Slice

Start with the official Boson/Hugging Face pipeline.

The first slice should be read-only plus one smallest possible local probe:

1. Inventory official Boson/HF model files, config, tokenizer, chat template,
   prompt docs, and any official source package or serving code that owns
   `HiggsMultimodalQwen3ForConditionalGeneration`.
2. Identify the official reference path for plain text-to-speech without voice
   cloning first.
3. Map the minimum component boundaries: tokenizer, prompt builder, decoder
   prefill, decoder step, eight-codebook sampler, codec/vocoder decode, waveform
   post-processing, and output container.
4. Build a small local parity fixture outside the repository or under reviewed
   maintainer docs: input text, token IDs, config summary, expected codebook
   shape, sample rate, and output metadata.
5. Decide which boundary is the first Core AI conversion candidate and which
   pieces should stay in Swift, Accelerate, CoreMedia, CoreAudio, or
   AVFoundation.
6. Only after that map exists, decide whether a community MLX artifact is useful
   as a comparison or compression input.

## Sources

- Higgs Audio v3 TTS model card:
  https://huggingface.co/bosonai/higgs-audio-v3-tts-4b
- Higgs Audio v3 4-bit MLX candidate:
  https://huggingface.co/Reza2kn/Higgs-Audio-v3-TTS-4bit-MLX
- Hugging Face Transformers:
  https://github.com/huggingface/transformers
- MLX Swift:
  https://github.com/ml-explore/mlx-swift
- MLX documentation:
  https://ml-explore.github.io/mlx/build/html/index.html
- MLX Audio:
  https://github.com/Blaizzy/mlx-audio
- MLX Audio Swift fork:
  https://github.com/gaelic-ghost/mlx-audio-swift
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
