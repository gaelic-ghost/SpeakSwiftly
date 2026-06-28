# Qwen3-TTS Core ML and Core AI Research Lane

This lane tracks first-party Qwen3-TTS Apple-runtime research for SpeakSwiftly.
It preserves probe evidence and restart instructions without implying that the
runtime backend has already moved away from the current MLX-backed path.

## Ground Rules

- Keep Qwen3-TTS Core ML and Core AI as evidence-driven runtime-route research.
- Preserve the distinction between probe evidence and production backend code.
- Prefer first-party Swift-owned Apple-platform pipelines when evidence shows
  they can meet parity, latency, memory, and quality requirements.
- Keep generated local model packages, traces, WAV files, and large artifacts
  out of the public repository.
- Keep executable probes in
  [`../../../../../scripts/repo-maintenance/coreml-qwen3tts/`](../../../../../scripts/repo-maintenance/coreml-qwen3tts/).
- Keep Swift fixture tests in
  [`../../../../../Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/`](../../../../../Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/).

## Current Artifacts

- [`coreml-qwen3tts-port-plan-2026-05-31.md`](coreml-qwen3tts-port-plan-2026-05-31.md)
  records the first-party Core ML/Core AI port plan.
- [`coreml-qwen3tts-evaluation-2026-05-31.md`](coreml-qwen3tts-evaluation-2026-05-31.md)
  preserves the external-artifact evaluation that shaped this lane.
- [`archive/`](archive/) stores checked-in JSON reports, fixtures, inventories,
  conversion summaries, quantization probes, resident-probe summaries, xctrace
  summaries, Core AI boundary captures, and closeout manifests.

## Archive Groups

- Fixtures and inventories:
  `text-token-fixture-*`, `speech-tokenizer-*`, `calibration-*`,
  `external-coreml-qwen3tts-*`, and `talker-code-*`.
- Conversion and bucket planning:
  `speech-tokenizer-decoder-coreml-conversion-*`,
  `speech-tokenizer-decoder-coreml-bucket-plan-*`, and
  `decoder-alignment-*`.
- Quantization and audio inspection:
  `speech-tokenizer-decoder-coreml-quantization-*` and
  `speech-tokenizer-decoder-coreml-audio-inspection-*`.
- Resident and profiling evidence:
  `speech-tokenizer-decoder-coreml-resident-*`,
  `speech-tokenizer-decoder-coreml-benchmark-*`, and
  `speech-tokenizer-decoder-coreml-xctrace-*`.
- Core AI boundary evidence:
  `coreai-*`.
- Closeout evidence:
  `decoder-closeout-*`.

## Promotion Rule

Do not add production backend code from this lane until the branch has current
parity, memory, latency, dispatch, and audio-quality evidence for the selected
Apple runtime path. Any future backend should start as a standalone probe or
hidden experimental backend before becoming a public generation option.
