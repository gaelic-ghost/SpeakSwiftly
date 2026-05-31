# Qwen-Only Output Modularization for SpeakSwiftly vNext

This branch is a major-version cleanup. SpeakSwiftly will keep Qwen3 as the only
speech generation family, remove Marvis and Chatterbox, and split generated audio
output into small self-contained package modules.

## Decisions

- Do not keep compatibility shims, backend aliases, transitional wrappers, or
  duplicate codepaths for removed backends.
- Treat persisted configuration or worker requests that name removed backends as
  invalid input and report a clear unsupported-backend error.
- Keep the initial modularization in this package rather than creating another
  repository.
- Leave the CoreML and Metal Flash Attention Qwen port as a future generation
  implementation swap unless that work is explicitly brought into this branch.
- Treat `SpeakSwiftlyServer` adoption and real two-Mac LAN testing as follow-up
  integration work after this package exposes stable output modules.

## Target Shape

- `SpeakSwiftlyCore` owns shared request identifiers, names, generated-audio
  chunk metadata, output errors, and observation primitives.
- `SpeakSwiftlyQwenGeneration` owns Qwen generation and emits typed async
  generated-audio chunks.
- `SpeakSwiftlyPlayback` owns local AVAudioEngine playback and consumes generated
  audio chunks.
- `SpeakSwiftlyHTTPAudioOutput` owns HTTP-friendly generated-audio chunk framing.
- `SpeakSwiftlyNetworkAudioOutput` owns Network.framework LAN audio stream
  encoding and transport primitives.
- `SpeakSwiftly` remains the composition and runtime facade that wires
  generation, queues, storage, and selected output destinations together.

## Validation Shape

- Prefer targeted Swift tests after each coherent slice.
- Run `swift package dump-package`, `swift build`, and `swift test` before
  checkpoints that change public API or the package graph.
- Do not run live worker E2E by default during the structural pass.
