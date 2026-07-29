# Higgs Audio v3 Parity Fixture Plan

Date: 2026-06-24
Branch: `research/apple-speech-pipeline`

## Purpose

Define the first official-pipeline parity fixture for Higgs Audio v3 before
choosing any Swift, Core AI, Core ML, Accelerate, CoreMedia, CoreAudio, or
AVFoundation implementation boundary.

The fixture should prove that SpeakSwiftly understands the official tokenizer,
prompt layout, codebook constants, codec/vocoder expectations, and output
metadata before running large weights or exposing a backend.

## Fixture 1: Plain English TTS

Status: token-layout fixture captured in
[`tokenizer-parity-fixture-2026-06-26.json`](tokenizer-parity-fixture-2026-06-26.json).

### Input

- Text:
  `Welcome to SpeakSwiftly. This is the first official Higgs Audio v3 parity fixture.`
- Voice mode: reference-free plain TTS
- Control tags: none
- Target behavior: one complete audio result, no voice clone, no streaming

### Expected Prompt Shape

Plain TTS prompt:

```text
<|tts|> <|text|> target text tokens <|audio|>
```

Required token ids:

| Token | Id |
| --- | ---: |
| `<|tts|>` | `151667` |
| `<|text|>` | `151672` |
| `<|audio|>` | `151670` |
| `<|audio_end|>` | `151671` |

The fixture should record:

- Raw text.
- Normalized text if the tokenizer or official pipeline changes it.
- Prompt section boundaries.
- Full prompt token ids.
- Special-token ids used.
- Whether `chat_template.jinja` participates in this path. Current official
  serving sources build the TTS prompt directly instead of using the generic
  Qwen chat template.

### Decoder Boundary Expectations

The first decoder fixture should record shapes and metadata only:

- Input token count.
- Hidden size: `2560`.
- Text vocabulary size: `151936`.
- Codebook count: `8`.
- Codebook vocabulary size: `1026`.
- Audio placeholder id: `-100`.
- BOC id: `1024`.
- EOC id: `1025`.
- Audio end token id: `151671`.
- KV-cache layout if official serving output exposes it clearly.
- First decode-step output shape before sampling.
- Sampled code row shape: `[8]`.
- Delayed code row count when enough output exists.

Do not convert a Core AI graph until this metadata can be compared against at
least one official serving path.

### Sampler Expectations

Status: synthetic delay-pattern fixture captured in
[`codebook-delay-fixture-2026-06-26.json`](codebook-delay-fixture-2026-06-26.json).

Record sampler policy explicitly:

- Top-k value and whether it defaults to full vocabulary/no-op.
- Top-p value.
- Temperature.
- Seed and deterministic behavior if used.
- Stop behavior when codebooks emit EOC.
- Delay-pattern ramp-in and wind-down state.
- Whether audio feedback uses the fused multi-codebook embedding on each
  generated row.

If official sources disagree, keep the fixture source-specific. Do not average
the policies into a pretend common default.

### Codec/Vocoder Expectations

Status: no-weight boundary fixture captured in
[`codec-vocoder-boundary-fixture-2026-06-28.json`](codec-vocoder-boundary-fixture-2026-06-28.json).

The first codec fixture does not need to include waveform samples yet, but it
must record the expected boundary:

- Raw code rows before delay reversal.
- Code rows after delay reversal.
- BOC/EOC filtering rule.
- Codebook axis order.
- Sample rate: `24000`.
- Codec checkpoint source:
  `tied.embedding.modality_embeddings.0.model.`
- Output sample count when an official path provides it.
- Output dtype and channel count when an official path provides it.

The codec/vocoder fixture is mandatory before declaring any graph-only text to
codebook proof useful for SpeakSwiftly.

The current fixture intentionally records decoded sample count, decoded dtype,
and decoded channel count as unknown until an official serving comparison
captures them for the same prompt fixture.

### Output Container Expectations

Status: no-weight official-serving comparison started in
[`official-serving-comparison-fixture-2026-06-29.json`](official-serving-comparison-fixture-2026-06-29.json).

Record output separately for non-streaming and streaming:

- Non-streaming expected container.
- Streaming expected container.
- Chunk frame defaults if using the vLLM async chunk path:
  - `codec_chunk_frames = 25`
  - `codec_left_context_frames = 25`
  - `codec_right_holdback_frames = 4`
  - `initial_codec_chunk_frames = 1`
- Whether the source describes PCM bytes, WAV bytes, or base64-encoded payloads.

Current source conflict to preserve:

- Boson and SGLang current serving docs emphasize `pcm` for streaming.
- Some model-card wording describes streamed base64 WAV chunks.

The current comparison fixture records the vLLM deploy YAML raw-PCM streaming
signal and keeps non-streaming container, decoded sample count, decoded dtype,
and decoded channel count blocked until an official serving request is executed.

## Fixture 2: Control Tags

Status: token-layout fixture captured in
[`tokenizer-parity-fixture-2026-06-26.json`](tokenizer-parity-fixture-2026-06-26.json).

After plain TTS parity, add one control-tag input:

```text
<|emotion:elation|>Welcome aboard. Hello there <|prosody:pause|> and thanks for listening.
```

Record the same prompt and token layout fields as Fixture 1, plus:

- Sentence-level emotion tag id.
- Inline pause tag id.
- Whether the official pipeline preserves tag order exactly.
- Whether any tokenizer normalization changes surrounding whitespace.

## Fixture 3: Reference Audio

Only after plain TTS and control-tag prompt parity are stable, add a reference
audio fixture.

Record:

- Reference waveform source.
- Reference sample rate before conversion.
- Official 24 kHz conversion behavior.
- Encoded reference code row shape.
- Delay-pattern encoded row shape.
- Prompt placeholder count.
- Reference-text behavior when transcript is present versus omitted.

Do not start with this fixture. Reference audio adds tokenizer, codec encoder,
delay pattern, prompt assembly, and cache behavior at once.

## First Probe Implementation

Add a small no-weight tokenizer fixture generator that:

1. Downloads only `tokenizer.json`, `tokenizer_config.json`, and
   `chat_template.jinja` from the official Hugging Face repo.
2. Uses a local tokenizer implementation or a temporary Python environment only
   if the standard-library inventory cannot produce token ids.
3. Emits JSON under `docs/research/speech-pipelines/lanes/higgs-audio-v3/`.
4. Does not download safetensors weights.
5. Fails with a specific error if required TTS special tokens are missing.

Status: implemented by
[`../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-tokenizer-parity-fixture.py`](../../../../../scripts/repo-maintenance/higgs-audio-v3/generate-tokenizer-parity-fixture.py).
The first checked-in output is
[`tokenizer-parity-fixture-2026-06-26.json`](tokenizer-parity-fixture-2026-06-26.json).

## First Core AI Candidate

The first Core AI candidate is not the whole pipeline. It should be one narrow
decoder-side graph after the prompt/token fixture proves the input layout.

Candidate order:

1. Frozen-shape decoder prefill or one decode step with fixed cache inputs.
2. Fused multi-codebook head if it can be isolated cleanly.
3. Codec decoder only after codebook-row and waveform metadata parity exist.

Swift should own tokenizer, prompt assembly, sampler policy, request lifecycle,
streaming policy, output buffers, and file/playback integration until a measured
graph boundary proves those pieces should move.

## Stop Conditions

Stop and record a blocker if:

- Official tokenizer ids differ from the generated inventory.
- Official serving sources disagree on prompt order for the same request shape.
- The codec/vocoder tensor source cannot be paired with the text-to-codebook
  stage.
- A graph conversion only proves text-to-codebook output without any credible
  path to 24 kHz waveform decode.
- Streaming container behavior remains ambiguous enough that SpeakSwiftly could
  expose the wrong public output contract.
