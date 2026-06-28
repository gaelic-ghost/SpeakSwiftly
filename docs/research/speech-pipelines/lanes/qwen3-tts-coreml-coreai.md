# Qwen3-TTS Core ML and Core AI Research Lane

This lane indexes the existing first-party Qwen3-TTS Apple-runtime research.
The detailed archive currently lives in
[`../../../maintainers/coreml-qwen3tts/`](../../../maintainers/coreml-qwen3tts/)
because it predates this research workspace and contains many checked-in probe
reports.

## Current Direction

- Keep Qwen3-TTS Core ML and Core AI as evidence-driven runtime-route research.
- Preserve the distinction between probe evidence and production backend code.
- Prefer first-party Swift-owned Apple-platform pipelines when evidence shows
  they can meet parity, latency, memory, and quality requirements.
- Keep generated local model packages and large artifacts out of the public
  repository.

## Migration Plan

Move this archive incrementally when a future branch can review the larger
rename cleanly:

1. Add a lane README beside the existing reports.
2. Group high-signal summaries under this research workspace.
3. Leave historical JSON report filenames intact.
4. Update tests, roadmap links, and scripts in the same commit as any path move.

## Existing Surfaces

- Maintainer archive:
  [`../../../maintainers/coreml-qwen3tts/`](../../../maintainers/coreml-qwen3tts/)
- Probe scripts:
  [`../../../../scripts/repo-maintenance/coreml-qwen3tts/`](../../../../scripts/repo-maintenance/coreml-qwen3tts/)
- Swift tests:
  [`../../../../Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/`](../../../../Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/)
