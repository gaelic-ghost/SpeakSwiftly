# Runtime Constants

Use this file for cross-lane runtime constants that are likely to matter to
future Socket skills, knowledge-base extraction, and first-party Apple speech
pipeline implementation.

## Higgs Audio v3

The Higgs Audio v3 lane has pinned these checked-in constants:

- text tokenizer model max length: `131072`
- audio codebooks: `8`
- real audio codes per codebook: `1024`
- audio codebook vocabulary size: `1026`
- beginning-of-codebook marker: `1024`
- end-of-codebook marker: `1025`
- delay pattern: `[0, 1, 2, 3, 4, 5, 6, 7]`
- codec checkpoint prefix: `tied.embedding.modality_embeddings.0.model.`
- bundled codec/vocoder weight entries under that prefix: `528`
- audio sample rate: `24000`
- default streaming codec chunk frames: `25`
- default streaming codec left context frames: `25`
- default streaming right holdback in the current fixture plan: `4`
- default initial streaming codec chunk frames: `1`

See these source fixtures:

- [`../lanes/higgs-audio-v3/tokenizer-parity-fixture-2026-06-26.json`](../lanes/higgs-audio-v3/tokenizer-parity-fixture-2026-06-26.json)
- [`../lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json`](../lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json)
- [`../lanes/higgs-audio-v3/codec-vocoder-boundary-fixture-2026-06-28.json`](../lanes/higgs-audio-v3/codec-vocoder-boundary-fixture-2026-06-28.json)
