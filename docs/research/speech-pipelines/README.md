# Speech Pipeline Research

This workspace is the handoff surface for in-progress speech model research,
official-source inventories, parity fixtures, and future first-party Apple
pipeline work.

Keep research here when it is useful to preserve on `main`, but is not yet
ready to become runtime code under `Sources/SpeakSwiftly`. The goal is to make
model-porting work restartable across branches and easy to mine later for
Socket skills, future knowledge-base entries, maintainer runbooks, and runtime
implementation plans.

## Layout

- `lanes/` stores one investigation per model family or runtime route.
- `findings/` stores cross-lane facts that should survive beyond one model.
- `process/` stores repeatable workflows for inventory, fixture generation,
  validation, and future skill extraction.

Executable probes stay under `scripts/repo-maintenance/<lane>/`. Swift tests
that protect checked-in fixtures stay under `Tests/SpeakSwiftlyTests/` beside
the feature area they protect.

## Lane Rules

Each lane should name:

- the official sources used as ground truth
- runtime constants that have been observed and pinned
- checked-in fixtures and the scripts that generated them
- current blockers before runtime integration
- promotion evidence required before adding production code

Do not move model weights, generated model packages, local cache paths, or
private-source artifacts into this workspace. Checked-in research artifacts
should be small, reproducible, and safe for the public repository.

## Active Lanes

- [`higgs-audio-v3/`](lanes/higgs-audio-v3/) tracks the official Boson/Hugging
  Face Higgs Audio v3 TTS pipeline inventory and no-weight parity fixtures.
- [`qwen3-tts-coreml-coreai.md`](lanes/qwen3-tts-coreml-coreai.md) indexes the
  existing first-party Qwen3-TTS Core ML and Core AI research archive.
