# Core ML Qwen3-TTS Evaluation Notes

Date: 2026-05-31

## Question

Evaluate FluidInference's Core ML Qwen3-TTS port as a possible experimental
SpeakSwiftly backend alongside the current MLX-backed Qwen, Marvis, and
Chatterbox backends.

The specific questions are:

- Does the port perform better than the current MLX Qwen path?
- Does it use the Neural Engine meaningfully?
- Did the conversion split work across devices appropriately?
- What would it take to add this as a backend without muddying the existing
  runtime ownership model?

## Research Summary

The current answer is: do not treat the FluidInference Qwen3-TTS Core ML port as
a ready replacement for the existing MLX Qwen backend. It is useful as an
experimental comparison target, but the available evidence points to a prototype
that is still missing a built-in tokenizer, has a large model footprint, and is
not currently ANE-optimized.

FluidInference's public model card says the Qwen3-TTS Core ML model is a
five-model pipeline totaling about 5.9 GB:

- `qwen3_tts_lm_prefill_v9`: about 2.8 GB
- `qwen3_tts_lm_decode_v10`: about 1.8 GB
- `qwen3_tts_cp_prefill`: about 432 MB
- `qwen3_tts_cp_decode`: about 420 MB
- `qwen3_tts_decoder_10s`: about 436 MB
- `speaker_embedding_official.npy`: about 4 KB

The model card also says synthesis is limited to 125 codec frames, roughly 10 s
of audio, and requires pre-tokenized Qwen3 token IDs.

FluidAudio's current `main` documentation lists Qwen3-TTS under "Evaluated
Models (Not Supported)" with the note that it is now 1.1 GB but too slow and
needs further testing. That size note conflicts with the current Hugging Face
model card's 5.9 GB total, so any local evaluation should measure the actual
downloaded artifact size and runtime memory rather than relying on either value
alone.

The closed FluidAudio PR for the Swift backend is especially important. It says
the backend was beta, required hardcoded token IDs for test sentences, and did
not include a built-in tokenizer. The PR was closed, not merged. Its model store
loads most stages with `.cpuAndGPU`, and pins `MultiCodeDecoder` to `.cpuOnly`
because all other compute-unit choices produced NaN output. That is strong
evidence that this port does not currently take advantage of the Neural Engine
in the way we would want for a production-quality backend.

Apple's Core ML guidance also supports evaluating this empirically rather than
inferring it from `MLModelConfiguration.computeUnits`. Core ML can choose and
split execution across CPU, GPU, and Neural Engine according to the selected
compute-unit preference, and Xcode's Core ML performance report plus Instruments
can show which operations actually run where.

## Existing SpeakSwiftly Fit

SpeakSwiftly's existing backend model is MLX-centered:

- `SpeechBackend` is the public backend identifier surface.
- `ModelFactory.loadResidentModels(for:)` resolves a backend to resident model
  ownership.
- `ResidentSpeechModels` carries loaded resident model variants.
- `AnySpeechModel` wraps the common generation behavior.
- Qwen-specific voice-profile conditioning is an MLX `Qwen3TTSModel`
  capability, including prepared reference conditioning artifacts.
- Live playback expects an async audio-chunk stream and sets the playback sample
  rate from the resident model.

That shape is good, but a Core ML Qwen backend should not be forced through the
current MLX-specific Qwen conditioning path. The Core ML port is not just a
different repo URL; it is a different inference engine, different model artifact
layout, and currently a weaker feature surface.

## Backend Classification

Treat a Core ML Qwen3-TTS backend as a durable backend-extension investigation,
not as a local implementation detail.

It would unlock these near-term uses:

- Direct A/B measurement against MLX Qwen on Gale's Apple silicon hardware.
- Instruments validation of CPU, GPU, and Neural Engine dispatch.
- A clearer answer about whether Core ML is worth keeping in the speech backend
  matrix for LLM-style TTS.

It would remove this existing uncertainty:

- Today, "Core ML might use the Neural Engine better" is a hypothesis. The
  FluidInference code suggests the opposite for this model, but only local
  measurement can settle performance, memory, startup time, and audio quality
  for SpeakSwiftly's workflow.

The simpler extension path considered first is adding only another MLX
`SpeechBackend` case with a different model repo. That does not fit here because
the model source is Core ML `.mlmodelc` artifacts and Swift-side inference code,
not an `MLXAudioTTS` model loaded through `TTS.loadModel`.

## Suggested Integration Shape

Do not add FluidAudio as a broad package dependency first. Start with a small
local experimental backend surface in `Sources/SpeakSwiftly/Generation/CoreMLQwen`
or an equivalent feature directory if we choose to prototype.

The minimum integration should be:

- `SpeechBackend.qwen3_coreml_experimental`, or a similarly explicit raw value.
- A Core ML-specific model store that loads the downloaded FluidInference model
  directory and records the compute-unit assignment per stage.
- A Core ML-specific synthesis adapter that exposes the same high-level output
  shape SpeakSwiftly needs: sample rate, file generation samples, and eventually
  live chunks.
- A tokenizer boundary that is explicit. Until a Swift tokenizer is implemented,
  the backend should fail with a clear operator-facing error unless token IDs are
  supplied through a deliberate experimental path.
- A validation command or probe that can run one short sentence and emit timing,
  artifact size, process memory, and Core ML compute-unit configuration.

Do not wire this into profile creation, default backend selection, or normal
live playback until the tokenizer and performance story are credible.

## Evaluation Plan

1. Download only the model metadata first and record actual artifact sizes.
2. Build a standalone probe that loads the Core ML model store without touching
   the worker runtime.
3. Run the probe on Gale's MacBook Pro and capture:
   - cold compile or first-load time
   - warm load time
   - prefill time
   - per-frame decode speed
   - total wall-clock time
   - audio duration
   - real-time factor
   - peak process footprint
4. Profile the probe with the Core ML Instrument, GPU Instrument, and Neural
   Engine Instrument to verify actual dispatch.
5. Compare against the existing SpeakSwiftly Qwen E2E benchmark lane using the
   same short text, same target voice strategy where possible, and the same
   reporting fields.
6. Only after that, decide whether to integrate it as:
   - a hidden experimental backend,
   - a probe-only comparison tool,
   - or no backend at all.

## Initial Risk Assessment

High risk for production use:

- The Swift backend PR is closed and not merged.
- The backend has no built-in tokenizer.
- The model card reports a very large total artifact size.
- The available Swift code pins the core generation stages away from the Neural
  Engine, with one stage pinned to CPU only.
- The available FluidAudio docs explicitly list Qwen3-TTS as evaluated but not
  supported.

Useful for research:

- The conversion split is understandable enough to probe.
- The pipeline maps to SpeakSwiftly's existing synthesis needs at the final
  audio-sample level.
- The model is Apache-2.0 according to the model cards, matching the upstream
  Qwen model license.

## Sources

- FluidInference Qwen3-TTS Core ML model card:
  https://huggingface.co/FluidInference/qwen3-tts-coreml
- Qwen3-TTS upstream model card:
  https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base
- Qwen3-TTS upstream repository:
  https://github.com/QwenLM/Qwen3-TTS
- FluidAudio Qwen3-TTS PR:
  https://github.com/FluidInference/FluidAudio/pull/290
- FluidInference conversion PR:
  https://github.com/FluidInference/mobius/pull/20
- Apple MLComputeUnits documentation:
  https://developer.apple.com/documentation/coreml/mlcomputeunits
- Apple Core ML performance guidance:
  https://developer.apple.com/videos/play/wwdc2022/10027/
- Apple Neural Engine transformer guidance:
  https://machinelearning.apple.com/research/neural-engine-transformers
