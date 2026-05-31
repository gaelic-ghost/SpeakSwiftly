# First-Party Core ML Qwen3-TTS Port Plan

Date: 2026-05-31

## Purpose

This note tracks the first-party Core ML Qwen3-TTS investigation. The goal is
not to adopt the existing FluidInference Core ML artifact blindly. The goal is
to decide whether SpeakSwiftly can produce a better Apple-silicon port by
owning the tokenizer boundary, graph split points, cache layout, precision, and
per-stage compute-unit policy.

This is a backend-extension investigation. It only becomes a package runtime
backend if the probe proves it can meet a real SpeakSwiftly use case better than
the existing MLX Qwen path or with a valuable Apple-platform deployment tradeoff.

## Starting Hypothesis

A first-party port might outperform the current external Core ML artifact if it
avoids the two problems visible in the FluidAudio prototype:

- large numbers of tiny Core ML prediction calls around autoregressive decode
- stage placement that falls back to CPU or CPU+GPU instead of using the Neural
  Engine for the stages where ANE actually helps

The investigation should try to prove or disprove that hypothesis with measured
evidence. Do not claim Neural Engine benefit from `MLModelConfiguration` alone.

## Practical Classification

This is a durable building-block investigation.

Near-term use cases it unlocks:

- direct A/B measurement of Core ML Qwen3-TTS against the current MLX Qwen path
- an Apple-silicon-specific answer for whether Qwen3-TTS can be shaped for ANE,
  GPU, or mixed execution better than the public conversion
- a possible future engine for mobile work if a Core ML path is materially more
  deployable than the MLX worker path

Existing pain or uncertainty it removes:

- the current external Core ML artifact is too opaque for SpeakSwiftly's runtime
  decisions
- FluidAudio's Swift path was closed before merge and lacks tokenizer ownership
- the repository does not yet have a repeatable way to compare MLX and Core ML
  Qwen on the same text, voice strategy, and hardware

Simpler extension path considered first:

- adding another `SpeechBackend` case that points at a different MLX model repo

Why that is insufficient:

- the port changes inference engine, model artifact layout, tokenizer handling,
  cache ownership, and profiling tools
- Core ML dispatch must be verified with Apple tooling, not through the existing
  MLX model wrapper

## Investigation Rules

- Keep the base `SpeakSwiftly` runtime untouched until a standalone probe has
  useful evidence.
- Keep external conversion scripts, downloaded models, compiled artifacts, and
  large intermediate tensors out of Git unless a tiny fixture is explicitly
  useful and safe.
- Prefer small, reproducible probes over broad dependency adoption.
- Record exact model source, commit, Core ML Tools version, deployment target,
  input shapes, output shapes, precision, and compute-unit setting for every
  converted stage.
- Treat tokenizer parity as a first-class requirement. A Core ML backend that
  needs hidden Python tokenization is not ready for runtime integration.
- Treat audible quality as evidence, but pair it with timing, token, codec-frame,
  memory, and device-dispatch data.

## Upstream Inventory Targets

Inventory these surfaces from upstream Qwen3-TTS before converting anything:

- text tokenizer source and vocabulary files
- speech tokenizer or codec model source
- prompt assembly for Base, CustomVoice, and VoiceDesign paths
- language and control token IDs
- reference-audio conditioning path
- reference transcript handling
- LM prefill inputs and outputs
- LM decode inputs, outputs, KV cache shape, cache update rule, and stop tokens
- code predictor inputs, outputs, cache shape, sampling rule, and codebook order
- audio decoder inputs, outputs, sample rate, frame size, padding behavior, and
  maximum audio duration

## Golden Path

The first golden path should be deliberately small:

- one English sentence
- one fixed language setting
- one fixed voice or speaker embedding strategy
- one deterministic sampling configuration when upstream allows it
- saved token IDs
- saved prefill tensor shapes
- saved first few decode token IDs
- saved codec-frame count
- saved final audio sample count and sample rate

Only after that path is stable should the investigation add a clone/reference
audio path.

## Candidate Graph Boundaries

The first conversion pass should evaluate these boundaries separately:

- Swift-side tokenizer and prompt assembly
- optional Swift-side sampling and logit processing
- Core ML text/code embedding stage
- Core ML LM prefill stage
- Core ML LM decode step with explicit KV cache input/output
- Core ML code predictor stage
- Core ML audio decoder stage

Avoid a monolithic all-in-one graph at the start. Separate graphs make stage
parity, precision failures, and device-placement decisions easier to isolate.

If a stage is dominated by small scalar work, cache mutation, or sampling, keep
it Swift-side until measurement proves Core ML helps.

## Compute-Unit Questions

For each converted stage, measure at least these configurations where the model
is numerically stable:

- `.cpuAndGPU`
- `.cpuAndNeuralEngine`
- `.all`
- `.cpuOnly`

Record:

- cold compile or first-load time
- warm load time
- per-call latency
- total synthesis latency
- real-time factor
- peak process footprint
- whether the stage produces finite output
- whether output parity remains acceptable
- actual dispatch evidence from Instruments or Core ML performance reports

## Parallelism Questions

The useful performance questions are not only "does ANE run it?"

Also answer:

- Can prefill run as a larger stable graph instead of token-by-token calls?
- Can decode use fixed buckets that reduce cache reshaping and model recompiles?
- Can multiple text lines or batch items share warm loaded stages?
- Can audio decoding overlap with later codec generation?
- Can reference-conditioning preparation be cached per profile in a Core ML-safe
  shape?
- Is generation limited by Core ML dispatch overhead, memory bandwidth, cache
  copies, sampling, or actual matrix work?

## SpeakSwiftly Integration Boundary

If the probe earns runtime integration, the first backend should be explicitly
experimental:

- raw backend value: `qwen3_coreml_experimental` or a similarly clear name
- feature directory: `Sources/SpeakSwiftly/Generation/CoreMLQwen`
- no default-backend promotion
- no profile-creation integration until reference conditioning is understood
- no live playback integration until the probe can produce chunkable audio or a
  clear file-only limitation is accepted

The adapter should expose the same practical output shape SpeakSwiftly already
needs:

- sample rate
- generated samples
- timing metadata
- model/source identifier
- stage timing and compute-unit settings for diagnostics

## Investigation Log

### 2026-05-31 Initial Planning

- Created `research/coreml-qwen3tts` as an isolated worktree.
- Reviewed the existing FluidInference Qwen3-TTS Core ML artifact and the closed
  FluidAudio Swift backend PR.
- Recorded that the external artifact is useful evidence but not a production
  target for SpeakSwiftly.
- Added Milestone 32 to `ROADMAP.md` so this work is visible alongside the other
  backend and release-hardening tracks.
- Next working slice: inventory upstream Qwen3-TTS source and identify the
  smallest reproducible Python golden path.

### 2026-05-31 Upstream Source Inventory, Pass 1

Upstream source snapshot:

- repository: `https://github.com/QwenLM/Qwen3-TTS.git`
- commit inspected: `022e286b98fbec7e1e916cb940cdf532cd9f488e`
- local inspection path: `/private/tmp/Qwen3-TTS-upstream`

Important upstream files:

- `qwen_tts/inference/qwen3_tts_model.py`
- `qwen_tts/inference/qwen3_tts_tokenizer.py`
- `qwen_tts/core/models/modeling_qwen3_tts.py`
- `qwen_tts/core/models/processing_qwen3_tts.py`
- `qwen_tts/core/models/configuration_qwen3_tts.py`
- `qwen_tts/core/tokenizer_12hz/modeling_qwen3_tts_tokenizer_v2.py`
- `examples/test_model_12hz_base.py`
- `examples/test_tokenizer_12hz.py`

Initial architecture findings:

- Text tokenization is handled by `Qwen3TTSProcessor`, which wraps
  `Qwen2Tokenizer` / `Qwen2TokenizerFast` through Hugging Face `ProcessorMixin`.
- Speech tokenization is separate from text tokenization. The 12 Hz speech
  tokenizer is loaded through `Qwen3TTSTokenizer.from_pretrained(...)`, registers
  `qwen3_tts_tokenizer_12hz`, and exposes `encode(...)` plus `decode(...)`.
- For 12 Hz, `Qwen3TTSTokenizer.encode(...)` returns `audio_codes` shaped per
  item as `(codes_len, num_quantizers)`.
- For Base voice cloning, `Qwen3TTSModel.create_voice_clone_prompt(...)` uses the
  speech tokenizer to encode reference audio and separately extracts a speaker
  embedding. If `x_vector_only_mode` is false, `ref_text` is required because the
  generation path uses ICL reference text plus reference speech codes.
- Text prompts are chat wrapped by small helper methods:
  - target text: `<|im_start|>assistant\n{text}<|im_end|>\n<|im_start|>assistant\n`
  - reference text: `<|im_start|>assistant\n{text}<|im_end|>\n`
  - instruction text: `<|im_start|>user\n{instruct}<|im_end|>\n`
- Default generation settings in the wrapper match the earlier external-port
  findings: `top_k=50`, `top_p=1.0`, `temperature=0.9`,
  `repetition_penalty=1.05`, subtalker sampling enabled with matching top-k,
  top-p, and temperature, and `min_new_tokens=2` inside the model generate call.
- The main generation call suppresses the upper 1024 codec-vocabulary tokens
  except the codec EOS token.

Initial graph-boundary findings:

- The main talker has two embedding sources: text embeddings projected through
  `text_projection`, and codec embeddings from talker input embeddings.
- The prompt-building path constructs prefill embeddings by summing text-side
  and codec-side embeddings in specific positions. This is a strong candidate
  for Swift-side prompt assembly plus small Core ML embedding/projector stages,
  but it may be cheaper to keep some embedding lookup work outside Core ML
  during the first parity probe.
- The main talker `forward(...)` has a prefill mode when `inputs_embeds` has
  sequence length greater than one, and a generate mode where the previous CB0
  token drives code-predictor generation for the other codebooks.
- The code predictor is a smaller transformer that predicts codebooks 1 through
  15 from the current hidden state and previous codebook IDs. Its config defaults
  show 5 hidden layers, hidden size 1024, 16 attention heads, 8 KV heads, and
  32 code groups in config, while runtime generation uses the model's
  `num_code_groups - 1` continuation.
- The main talker returns logits, updated cache, hidden states, `past_hidden`,
  generation step, trailing text hidden state, and the TTS pad embedding.
- The final waveform is produced by `model.speech_tokenizer.decode(...)`, not by
  the talker directly. For Base ICL mode, reference codes are prepended before
  decode and then the reference-audio portion is cut from the decoded waveform.

Immediate implications:

- The first golden path should target the Base model with `x_vector_only_mode`
  enabled or use a fixed upstream test fixture before attempting full ICL clone
  parity. Full ICL clone parity requires text tokenization, speech-tokenizer
  reference encoding, speaker embedding extraction, generation, speech-tokenizer
  decode, and reference-audio trimming.
- Tokenizer work splits into two tracks:
  - Qwen2 text tokenizer parity for prompt token IDs.
  - 12 Hz speech tokenizer encode/decode parity for reference codes and final
    waveform decode.
- A first Core ML probe can reduce scope by accepting saved text token IDs and a
  saved speaker embedding or reference-code fixture, but that should be marked
  probe-only. Runtime integration requires native tokenizer ownership.
- A custom port should likely convert the talker and speech-tokenizer decode
  separately rather than treating Qwen3-TTS as one monolithic model.

### 2026-05-31 Text Token Fixture Script, Pass 1

Added a maintained tokenizer fixture script:

- `scripts/repo-maintenance/coreml-qwen3tts/generate-text-token-fixture.py`

Added a tiny checked-in first fixture:

- `docs/maintainers/coreml-qwen3tts/text-token-fixture-0.6b-base.json`

The script deliberately does not load model weights. It uses the Hugging Face
tokenizer files from `Qwen/Qwen3-TTS-12Hz-0.6B-Base`, applies the upstream prompt
wrappers recorded above, and emits a small JSON fixture with:

- source model id, upstream source commit, tokenizer class, vocab size, and
  model max length
- wrapped target, reference, and instruction prompts
- input IDs, attention masks, token strings, and prompt lengths
- upstream generation defaults that matter for later parity work

Validation notes:

- The public 0.6B Base tokenizer loads as `Qwen2Tokenizer`.
- Hugging Face `transformers` warns that PyTorch is absent, which is acceptable
  for this script because it only needs tokenizer and file utilities.
- Hugging Face also warns that a `qwen3_tts` model type is being used through the
  generic tokenizer path. The script still resolves the tokenizer files and
  produces deterministic text token IDs, but this warning should remain visible
  in future validation notes until native Swift tokenizer parity replaces the
  Python fixture.
- With the default target text plus one reference transcript and one instruction,
  the generated prompt lengths were:
  - target: 23 tokens
  - reference: 12 tokens
  - instruction: 14 tokens

Immediate implications:

- This gives Swift-side work a stable first target: reproduce the exact wrapped
  prompt strings and token IDs before converting the talker graph.
- The checked-in fixture uses a stable `created_at_utc` value so future diffs
  only change when the tokenizer inputs or output schema change.
- The script is a temporary probe tool, not a runtime dependency. A production
  Core ML backend still needs native tokenizer ownership or a clearly vendored
  tokenizer artifact with reproducible provenance.
- The next useful slice is to write Swift-side prompt wrapper tests against the
  checked-in fixture, then decide whether native tokenizer parity should be a
  direct Swift port, a generated tokenizer asset, or a vendored tokenizer
  library.

### 2026-05-31 Swift Text Fixture Tests, Pass 1

Added SwiftPM tests for the checked-in text-token fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSTextTokenFixtureTests.swift`

The tests intentionally stay test-only. They do not add a production Core ML
backend, source module, runtime enum case, or tokenizer implementation yet.

Covered behavior:

- fixture provenance is pinned to the upstream Qwen3-TTS repository, inspected
  source commit, and public 0.6B Base model id
- the Swift prompt-wrapper helpers reproduce the upstream target, reference, and
  instruction wrapped strings stored in the fixture
- the first checked-in token IDs and attention masks remain stable

Validation:

- `swift test --filter qwen3` passed after the first fresh-worktree dependency
  build completed.

Implementation note:

- Swift's `.convertFromSnakeCase` decodes `created_at_utc` as `createdAtUtc` and
  `model_id` as `modelId`, so the fixture model avoids all-caps acronym
  properties in test-only `Decodable` structs.

### 2026-05-31 Speech Tokenizer Config Probe, Pass 1

Added a config-only speech-tokenizer inspection script:

- `scripts/repo-maintenance/coreml-qwen3tts/inspect-speech-tokenizer-config.py`

Added a checked-in metadata fixture:

- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-config-12hz.json`

Added SwiftPM tests for the fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerConfigTests.swift`

This probe downloads only small Hugging Face metadata files from
`Qwen/Qwen3-TTS-Tokenizer-12Hz`. It does not download model weights and does not
run encode/decode yet.

Captured metadata:

- Hugging Face resolved revision:
  `7dd38ad4e9bad454aae9cd937d0cd577604fe229`
- model type: `qwen3_tts_tokenizer_12hz`
- input sample rate: 24000 Hz
- output sample rate: 24000 Hz
- encode downsample rate: 1920 samples per code step
- decode upsample rate: 1920 samples per code step
- valid quantizers used by the encoder output: 16
- encoder codebook size: 2048
- decoder transformer hidden size: 512
- decoder transformer layers: 8
- decoder attention heads: 16
- decoder key-value heads: 16
- decoder latent dimension: 1024
- decoder dimension: 1536
- decoder upsample rates: `[8, 5, 4, 3]`
- decoder pre-upsampling ratios: `[2, 2]`

Core ML implications:

- The 12 Hz speech tokenizer should be treated as at least two graph candidates:
  encoder and decoder. It should not be hidden inside the first talker graph.
- The first decode graph can accept padded integer codes shaped
  `batch x codes_length x num_quantizers`.
- Upstream pads missing code steps as `-1`, computes valid length from CB0,
  clamps codes to zero before decode, and trims decoded audio by
  `valid_code_steps * 1920`.
- The decoder has enough transformer and convolutional/upsampling work that it
  deserves its own compute-unit measurement instead of inheriting the talker
  compute policy.

Validation:

- `uv run --with ruff ruff check` passed for both Core ML Qwen maintainer
  scripts.
- `jq empty` passed for the speech-tokenizer config fixture.
- `swift test --filter qwen3` passed with the text-token and speech-tokenizer
  config tests.

### 2026-05-31 Speech Tokenizer Runtime Preflight, Pass 1

Added an opt-in runtime fixture generator:

- `scripts/repo-maintenance/coreml-qwen3tts/generate-speech-tokenizer-fixture.py`

Added a checked-in preflight fixture:

- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-runtime-preflight-12hz.json`

Added SwiftPM tests for the preflight fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerPreflightTests.swift`
- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSFixtureSupport.swift`

This script is shaped so preflight mode stays light and runtime mode is
explicit. Runtime mode requires both `--no-preflight-only` and
`--allow-model-download`; the generated preflight fixture records the exact
heavier `uv run --with ...` command needed for the real encode/decode pass.

Preflight findings:

- The 12 Hz speech tokenizer repository currently has 6 files.
- Total Hugging Face file inventory size is 682300739 bytes.
- The dominant file is `model.safetensors` at 682293092 bytes.
- The planned synthetic probe is 0.64 seconds at 24000 Hz, or 15360 samples.
- At 1920 samples per code step, that should produce 8 code steps before any
  model-specific padding or trimming behavior.

Implementation note:

- The first draft of the runtime fixture script put runtime packages such as
  Torch and Transformers in the inline script dependencies. That made preflight
  install heavy packages unnecessarily. The script now keeps inline dependencies
  to Hugging Face metadata only and imports runtime packages lazily after the
  explicit model-download gate.

Validation:

- Preflight generation succeeded without loading model weights.
- `jq empty` passed for the runtime preflight fixture.
- `uv run --with ruff ruff check` passed for all three Core ML Qwen maintainer
  scripts.
- `swift test --filter qwen3` passed with 8 tests covering the text fixture,
  speech-tokenizer config fixture, and runtime preflight fixture.

## Open Decisions

- Which upstream checkpoint should be the first target: 0.6B Base, 1.7B Base, or
  a smaller tokenizer-only path first?
- Should the first full model probe graduate from the maintained script path
  into a package executable target, or stay outside the package until conversion
  evidence exists?
- Should the tokenizer ultimately be ported directly to Swift, shared through a
  generated vocabulary artifact, or vendored from a proven tokenizer library?
- What is the minimum evidence needed before adding a public
  `SpeechBackend` case?

## Sources

- Qwen3-TTS upstream repository:
  https://github.com/QwenLM/Qwen3-TTS
- Qwen3-TTS upstream model card:
  https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base
- FluidInference Qwen3-TTS Core ML model card:
  https://huggingface.co/FluidInference/qwen3-tts-coreml
- Core ML Tools conversion guide:
  https://apple.github.io/coremltools/docs-guides/source/convert-to-ml-program.html
- Core ML Tools typed execution guide:
  https://apple.github.io/coremltools/docs-guides/source/typed-execution.html
- Apple MLComputeUnits documentation:
  https://developer.apple.com/documentation/coreml/mlcomputeunits
- Apple Neural Engine transformer guidance:
  https://machinelearning.apple.com/research/neural-engine-transformers
