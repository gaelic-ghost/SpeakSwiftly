# Parity Fixture Workflow

Use this workflow for small, public, no-weight fixtures that pin official speech
pipeline behavior before runtime code is added.

## Steps

1. Map the official source first.
2. Extract only small metadata, tokenizer assets, or synthetic examples.
3. Emit deterministic JSON under the lane directory.
4. Add Swift tests that read the checked-in fixture and assert the runtime
   constants or shape expectations that future code must preserve.
5. Link the fixture from the lane README and roadmap milestone.

## Boundaries

- Do not check in model weights, generated model packages, private artifacts, or
  machine-local cache paths.
- Do not port community implementation files directly into SpeakSwiftly.
- Do not promote a fixture into runtime code until the fixture protects a clear
  implementation boundary.

## Current Higgs Fixtures

- tokenizer and prompt-builder parity:
  [`../lanes/higgs-audio-v3/tokenizer-parity-fixture-2026-06-26.json`](../lanes/higgs-audio-v3/tokenizer-parity-fixture-2026-06-26.json)
- eight-codebook delay pattern:
  [`../lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json`](../lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json)
