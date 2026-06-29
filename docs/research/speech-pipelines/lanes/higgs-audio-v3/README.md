# Higgs Audio v3 Research Lane

This lane tracks public, official-source Higgs Audio v3 work for a future
first-party Apple speech pipeline in SpeakSwiftly.

## Ground Rules

- Treat official Boson/Hugging Face, vLLM-Omni, and SGLang-Omni sources as the
  ground-truth map.
- Treat community MLX ports as comparison evidence only unless Gale explicitly
  approves adopting or porting them.
- Keep runtime constants and parity fixtures checked in here when they are
  small, no-weight, and reproducible.
- Keep executable probes in
  [`../../../../../scripts/repo-maintenance/higgs-audio-v3/`](../../../../../scripts/repo-maintenance/higgs-audio-v3/).
- Keep Swift fixture tests in
  [`../../../../../Tests/SpeakSwiftlyTests/Generation/HiggsAudio/`](../../../../../Tests/SpeakSwiftlyTests/Generation/HiggsAudio/).

## Current Artifacts

- [`higgs-audio-port-evaluation-2026-06-23.md`](higgs-audio-port-evaluation-2026-06-23.md)
  records the first public-lane route decision: official-source, first-party
  Apple pipeline research instead of inheriting a community MLX port.
- [`official-pipeline-inventory-2026-06-24.md`](official-pipeline-inventory-2026-06-24.md)
  maps tokenizer, prompt builder, decoder, sampler, codec/vocoder, waveform,
  and output-container surfaces from official sources.
- [`official-pipeline-map-2026-06-24.json`](official-pipeline-map-2026-06-24.json)
  stores the structured inventory emitted by the official-source probe.
- [`parity-fixture-plan-2026-06-24.md`](parity-fixture-plan-2026-06-24.md)
  records the staged fixture plan.
- [`tokenizer-parity-fixture-2026-06-26.json`](tokenizer-parity-fixture-2026-06-26.json)
  pins tokenizer, special-token, and prompt-builder constants.
- [`codebook-delay-fixture-2026-06-26.json`](codebook-delay-fixture-2026-06-26.json)
  pins the synthetic eight-codebook delay-pattern fixture.
- [`codec-vocoder-boundary-fixture-2026-06-28.json`](codec-vocoder-boundary-fixture-2026-06-28.json)
  pins the no-weight codec/vocoder weight-prefix boundary, codebook decode
  boundary, streaming chunk defaults, and remaining waveform metadata gates.
- [`official-serving-comparison-fixture-2026-06-29.json`](official-serving-comparison-fixture-2026-06-29.json)
  starts the no-weight official-serving comparison for the plain prompt,
  preserving the PCM streaming signal, unresolved WAV/base64 wording conflict,
  and remaining decoded waveform metadata gates.

## Promotion Rule

This lane should not add runtime code until the lane has pinned official-source
constants, tokenizer and prompt parity, codebook-delay reversal, decoder
prefill/decode shape expectations, sampler behavior, codec/vocoder decode
expectations, waveform post-processing, and output-container behavior.

The first runtime code should be a standalone probe or hidden experimental
backend only after fixture-backed parity makes the implementation boundary
clear.
