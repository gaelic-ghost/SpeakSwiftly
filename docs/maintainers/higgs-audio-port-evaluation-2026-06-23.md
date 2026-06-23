# Higgs Audio V3 Port Evaluation

Date: 2026-06-23
Branch: `research/higgs-demodokos-audio-ports`

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

1. Inspect the third-party MLX artifact file layout without downloading weights.
2. Confirm whether it contains standard MLX weights/config or still depends on
   Transformers custom Python model code.
3. Build a standalone Swift probe target or script that attempts model config
   loading only.
4. If config loading is clean, run one short sentence through silent file output.
5. Record time to first audio, total generation time, peak process memory, MLX
   memory, sample rate, emitted chunk cadence, and audible notes.

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
3. If it looks loadable, run one disk-space check before downloading weights.
4. Download the minimum required model files to the Hugging Face cache, not the
   repository.
5. Generate one short English sentence to a local temp WAV file.
6. Compare against the current Qwen3 0.6B and 1.7B benchmark shape before any
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
- Core AI local docs:
  `/documentation/CoreAI`
- Core AI integration local docs:
  `/documentation/CoreAI/integrating-on-device-ai-models-in-your-app-with-core-ai`
- Core AI compile local docs:
  `/documentation/CoreAI/compiling-core-ai-models-ahead-of-time`
- Core AI profiling local docs:
  `/documentation/CoreAI/inspecting-debugging-and-profiling-core-ai-models`
