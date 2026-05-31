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

### 2026-05-31 Speech Tokenizer Runtime Fixture, Pass 1

Ran the real 12 Hz speech-tokenizer encode/decode probe against a deterministic
synthetic waveform.

Added a checked-in runtime fixture:

- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json`

Added SwiftPM tests for the runtime fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerRuntimeFixtureTests.swift`

Runtime command shape:

- The script requires `--no-preflight-only` and `--allow-model-download`.
- Runtime dependencies needed by the upstream package were:
  `numpy`, `torch`, `transformers`, `librosa`, `soundfile`, `sox`,
  `onnxruntime`, `einops`, and `torchaudio`.
- The local upstream source checkout used for the run was the previously
  inspected Qwen3-TTS commit
  `022e286b98fbec7e1e916cb940cdf532cd9f488e`.
- The committed fixture records that source commit, not the machine-local source
  path.

Runtime findings:

- Upstream package import pulls the 25 Hz tokenizer path during package
  initialization, so the runtime environment needs 25 Hz support dependencies
  even for a 12 Hz-only fixture.
- Missing dependencies encountered and fixed in the runtime command:
  `sox`, then `onnxruntime`, then `torchaudio`.
- `flash-attn` was not installed. Upstream warned that it would use the manual
  PyTorch implementation. This is acceptable for the CPU fixture, but should be
  recorded separately from any future performance result.
- The 0.64 second synthetic waveform encoded to audio codes shaped `[8, 16]`
  with `int64` dtype.
- The decoded waveform returned 15360 samples at 24000 Hz, matching the input
  duration and the preflight code-step expectation.
- The first CB0 code prefix was:
  `[1221, 215, 1521, 1095, 1985, 1985, 1985, 687]`.

Core ML implications:

- We now have a tiny, deterministic decoder input shape for the first
  decoder-only Core ML conversion probe: one batch item, 8 code steps, and 16
  quantizers.
- The decoder-only conversion probe can start from the checked-in code prefix
  and output-shape expectations before attempting full speech-tokenizer encoder
  conversion.
- This fixture is not an audible-quality test. It proves mechanical encode,
  decode, shape, trimming, and dependency behavior for a synthetic signal.

Validation:

- Runtime encode/decode fixture generation succeeded after the 12 Hz tokenizer
  weights were available locally.
- `uv run --with ruff ruff check` passed for all three Core ML Qwen maintainer
  scripts.
- `jq empty` passed for the preflight and runtime speech-tokenizer fixtures.
- A path hygiene scan found no `/private`, `/Users`, or `~/` strings in the
  checked-in Core ML Qwen fixtures, scripts, or Swift tests.
- `swift test --filter qwen3` passed with 10 tests covering text tokenization,
  speech-tokenizer config, runtime preflight, and runtime fixture expectations.

### 2026-05-31 Speech Tokenizer Decoder Core ML Probe, Pass 1

Added a decoder-only Core ML conversion probe:

- `scripts/repo-maintenance/coreml-qwen3tts/convert-speech-tokenizer-decoder-coreml.py`

Added checked-in conversion fixtures:

- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-preflight-12hz.json`
- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-12hz.json`
- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-torch27-12hz.json`
- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-fixed16q-12hz.json`
- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-export-fixed16q-12hz.json`
- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-export-strict-fixed16q-12hz.json`
- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json`

Added SwiftPM tests for the conversion fixtures:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLProbeTests.swift`

Conversion target:

- stage: `speech_tokenizer_decoder`
- Core ML Tools target: ML Program
- minimum deployment target: macOS 15
- input name: `audio_codes`
- input shape: `[1, 8, 16]`
- input dtype: `int64`
- expected output shape: `[1, 15360]`
- expected output sample rate: 24000 Hz
- compute precision attempted: float32

Runtime findings:

- The script executes the PyTorch decoder wrapper successfully before tracing.
- PyTorch output shape is `[1, 15360]`.
- PyTorch output RMS is `0.032971180975437164`, matching the earlier
  speech-tokenizer runtime fixture.
- The first conversion attempt used Python 3.14. Core ML Tools 9.0 installed,
  but native pieces such as `libcoremlpython` and `libmilstoragepython` failed
  to load. That attempt is not a useful Core ML conversion result.
- The second conversion attempt pinned Python 3.12. Core ML Tools native import
  warnings disappeared, but Torch 2.12.0 remains newer than the latest
  Core ML Tools-tested Torch version reported by the tool, Torch 2.7.0.
- Torch tracing failed before Core ML conversion started:
  `RuntimeError: unordered_map::at: key not found`
- A third conversion attempt pinned Python 3.12, Torch 2.7.0, and Torchaudio
  2.7.0. It produced the same trace failure:
  `RuntimeError: unordered_map::at: key not found`
- A fixed-shape wrapper then removed the split residual quantizer's tensor
  iteration and shape checks for the `[1, 8, 16]` probe. It matched upstream
  PyTorch output exactly with `upstream_max_abs_diff: 0.0`, but TorchScript
  tracing still failed with the same `unordered_map::at: key not found` error.
- A non-strict `torch.export` capture attempt against the fixed wrapper failed
  before Core ML conversion with:
  `RuntimeError: NYI: querying is_contiguous inside of vmap for memory_format other than torch.contiguous_format`
- A strict `torch.export` capture attempt failed in the decoder transformer
  masking path. The actionable part of the error is that PyTorch export hit a
  vmap path that calls `.item()` on a Tensor inside the causal mask helper.
- A fixed-shape static-mask wrapper then bypassed the Transformers causal-mask
  helper while preserving the same upstream weights and output. This wrapper
  matched upstream PyTorch output exactly with `upstream_max_abs_diff: 0.0`.
- TorchScript tracing with the static-mask wrapper succeeded, but Core ML Tools
  conversion failed on an `int` op around the causal convolution path.
- Non-strict `torch.export` with the static-mask wrapper succeeded. Core ML
  Tools first rejected the raw exported program because it was still in the
  PyTorch training dialect and requested `run_decompositions({})`.
- After `run_decompositions({})`, Core ML Tools converted the fixed-shape
  decoder to an ML Program and saved an `.mlpackage`.
- CPU-only Core ML prediction against the converted decoder returned shape
  `[1, 15360]` and matched the PyTorch wrapper with max absolute difference
  `0.00003900937736034393`.

Trace warnings before the failure:

- The decoder checks `codes.shape[1]` against the configured quantizer count,
  which becomes a trace-time constant.
- The split residual quantizer iterates over codebook tensors, which also
  becomes shape-specialized.
- Causal convolution length math and Transformers masking utilities also emit
  shape-specialization warnings.

Immediate implications:

- The first decoder-only Core ML package now exists for the tiny synthetic
  `[1, 8, 16]` fixture.
- The Core ML Tools-tested Torch line did not fix the trace failure.
- Removing the quantizer iteration was useful because it eliminated several
  trace warnings without changing output, but it was not sufficient.
- Replacing the transformer causal-mask helper with a fixed-shape static mask
  was the step that moved the probe from PyTorch-capture failure to Core ML
  conversion success.
- This is still a fixed-shape proof, not a runtime backend. The next slice
  should inspect the generated `.mlpackage`, measure CPU/GPU/ANE compute-unit
  behavior, and decide whether the static-mask strategy can become a small set
  of bucketed decoder graphs rather than one hardcoded test shape.

Validation:

- Conversion preflight generation succeeded.
- Runtime conversion probes produced structured failure and success reports.
- `jq empty` passed for the Core ML preflight, conversion, and runtime
  speech-tokenizer fixtures.
- A path hygiene scan found no `/private`, `/Users`, or `~/` strings in the
  checked-in Core ML conversion fixtures or script.
- `uv run --with ruff ruff check` passed for all four Core ML Qwen maintainer
  scripts.
- `swift test --filter qwen3` passed with 16 tests covering text tokenization,
  speech-tokenizer config, runtime fixtures, and the decoder Core ML conversion
  probe.

### 2026-05-31 Speech Tokenizer Decoder Core ML Benchmark, Pass 1

Added a decoder Core ML benchmark script:

- `scripts/repo-maintenance/coreml-qwen3tts/benchmark-speech-tokenizer-decoder-coreml.py`

Added a checked-in benchmark fixture:

- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-benchmark-static-mask-12hz.json`

Added SwiftPM tests for the benchmark fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLBenchmarkTests.swift`

Benchmark setup:

- hardware: Apple M4 Pro, 14 logical CPUs, 24 GiB memory
- local package: `Qwen3TTSSpeechTokenizerDecoder-static-mask-export-decomposed.mlpackage`
- local package size: about 436 MB
- input shape: `[1, 8, 16]`
- warmup runs per compute-unit setting: 3
- measured runs per compute-unit setting: 10

Measured median prediction times:

- `cpuOnly`: about 32.37 ms
- `cpuAndGPU`: about 23.71 ms
- `cpuAndNeuralEngine`: about 32.70 ms
- `all`: about 23.90 ms

Output parity:

- all compute-unit settings loaded and predicted successfully
- `cpuAndGPU`, `cpuAndNeuralEngine`, and `all` stayed within `0.000001` max
  absolute difference from the CPU-only baseline

Immediate implications:

- For this fixed 8-frame decoder graph, `.cpuAndGPU` and `.all` were faster
  than `.cpuOnly`.
- `.cpuAndNeuralEngine` was similar to `.cpuOnly`, not faster. That does not
  prove the Neural Engine was unused, but it means the NE-preferred setting is
  not an obvious win for this decoder-only graph.
- The next profiling slice needs real dispatch evidence from Instruments or
  Core ML performance diagnostics before we make any claim about ANE use.
- Benchmarking longer code-step buckets is important before drawing conclusions
  about final synthesis latency. This 8-frame fixture is intentionally tiny.

Validation:

- Benchmark generation succeeded for all four compute-unit settings.
- `jq empty` passed for the benchmark fixture.
- A path hygiene scan found no `/private`, `/Users`, or `~/` strings in the
  checked-in Core ML Qwen fixtures, scripts, or Swift tests.
- `uv run --with ruff ruff check` passed for all five Core ML Qwen maintainer
  scripts.
- `swift test --filter qwen3` passed with 18 tests covering text tokenization,
  speech-tokenizer config, runtime fixtures, decoder Core ML conversion, and
  decoder Core ML benchmarking.

### 2026-05-31 Speech Tokenizer Decoder Core ML Instruments Trace, Pass 1

Added an Instruments capture script:

- `scripts/repo-maintenance/coreml-qwen3tts/profile-speech-tokenizer-decoder-coreml-xctrace.py`

Added a checked-in trace summary fixture:

- `docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-xctrace-static-mask-12hz.json`

Added SwiftPM tests for the trace summary:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLXctraceTests.swift`

Trace setup:

- Instruments template: `Core ML`
- local trace artifacts: `.local/coreml-qwen3tts/traces`
- hardware: Apple M4 Pro, macOS 26.5
- warmup runs per compute-unit setting: 2
- measured runs per compute-unit setting: 20
- exported tables:
  - `coreml-os-signpost`
  - `ane-hw-intervals-internal`
  - `mps-hw-intervals`
  - `metal-gpu-intervals`
  - `metal-application-command-buffer-submissions`

Trace findings:

- All four compute-unit settings ran successfully under Instruments.
- `cpuOnly` recorded no `mps-hw-intervals` rows and no
  `ane-hw-intervals-internal` rows.
- `cpuAndNeuralEngine` recorded no `mps-hw-intervals` rows and no
  `ane-hw-intervals-internal` rows.
- `cpuAndGPU` recorded 22 `mps-hw-intervals` rows labeled `MPSGraph` and no
  ANE interval rows.
- `all` recorded 22 `mps-hw-intervals` rows labeled `MPSGraph` and no ANE
  interval rows.

Immediate implications:

- The timing difference from the benchmark is now backed by Instruments trace
  evidence: the faster `cpuAndGPU` and `all` settings exercised the MPSGraph /
  Metal path for this fixed decoder graph.
- The `cpuAndNeuralEngine` run produced no recorded ANE intervals and behaved
  like the CPU-only run for this fixed decoder graph.
- This does not mean Qwen3-TTS cannot use ANE anywhere. It means this current
  float32, fixed-shape speech-tokenizer decoder package is not naturally landing
  on ANE with the `cpuAndNeuralEngine` preference.
- The next ANE-relevant work should be compression and quantization probing,
  especially W8A8 where Core ML Tools documents newer A17 Pro and M4 hardware
  as having optimized int8 Neural Engine compute paths.

Quantization and compression notes:

- Core ML Tools supports weight quantization to 8-bit and 4-bit forms.
- Weight-only Core ML quantization compresses stored weights, but runtime
  computation still uses float precision for the consuming operations.
- Activation quantization is 8-bit and is the part that can pair with 8-bit
  weights for W8A8 execution.
- Core ML Tools documents W8A8 as a mode that can use newer Neural Engine
  int8-int8 compute paths on A17 Pro and M4-class hardware.
- Palettization can reduce model storage with 1, 2, 3, 4, 6, or 8 bit lookup
  tables. Starting at macOS 15, grouped-channel palettization and 8-bit LUT
  storage become relevant options.

Validation:

- Instruments `Core ML` capture succeeded for all four compute-unit settings.
- `xcrun xctrace export --toc` confirmed the local template exposes ANE, MPS,
  Metal, and Core ML tables.
- `jq empty` passed for the trace summary fixture.
- `uv run --with ruff ruff check` passed for all six Core ML Qwen maintainer
  scripts.
- `swift test --filter qwen3` passed with 21 tests covering text tokenization,
  speech-tokenizer config, runtime fixtures, decoder Core ML conversion,
  decoder Core ML benchmarking, and decoder Instruments trace summaries.

### 2026-05-31 Calibration Dataset Inventory, Pass 1

Added a Hugging Face Dataset Viewer inventory script:

- `scripts/repo-maintenance/coreml-qwen3tts/inspect-calibration-datasets.py`

Added a checked-in calibration dataset inventory fixture:

- `docs/maintainers/coreml-qwen3tts/calibration-dataset-inventory-2026-05-31.json`

Added SwiftPM tests for the inventory fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSCalibrationDatasetInventoryTests.swift`

Scope clarification:

- Current converted graph: 12 Hz speech-tokenizer decoder only.
- Current input: `audio_codes` shaped `batch x code_steps x 16 codebooks`.
- Current graph does not include text tokenization, the main autoregressive
  talker, the code predictor, speaker embedding, reference conditioning, or the
  speech-tokenizer encoder.

Dataset candidates:

- Primary decoder-calibration candidate:
  `mythicinfinity/libritts_r`, config `clean`, split `train.clean.100`.
- Filtered decoder-calibration candidate:
  `parler-tts/libritts_r_filtered`, config `clean`, split `train.clean.100`.
- Secondary decoder-calibration comparison:
  `mythicinfinity/libritts`, config `clean`, split `train.clean.100`.
- Broad read-speech control:
  `openslr/librispeech_asr`, config `clean`, split `train.100`.
- Accent and speaker-diversity control:
  `fixie-ai/common_voice_17_0`, config `en`, split `train`.

Immediate implications:

- LibriTTS-R is the best first calibration source for the current decoder graph:
  it is open, English, TTS-oriented, 24 kHz, transcripted, and includes speaker
  ids.
- For decoder-only W8A8 calibration, we can encode sampled audio through the
  Qwen3 12 Hz speech tokenizer and calibrate the Core ML decoder on the
  resulting code tensors.
- For full-stack W8A8 calibration, audio-only data is not enough. We will also
  need representative prompts, generation histories, KV-cache states, code
  predictor states, speaker/reference-conditioning examples, and generated code
  trajectories.
- The Qwen3-TTS paper describes very large-scale training data, but the public
  release appears to provide model/tokenizer artifacts and examples, not the
  full training corpus. Calibration should therefore use open substitutes and
  locally generated Qwen3 trajectories rather than assuming training-data
  availability.

Validation:

- Hugging Face Dataset Viewer inspection succeeded for all five candidates.
- `jq empty` passed for the calibration dataset inventory fixture.
- A path hygiene scan found no `/private`, `/Users`, or `~/` strings in the
  checked-in Core ML Qwen fixtures, scripts, or Swift tests.
- `uv run --with ruff ruff check` passed for all seven Core ML Qwen maintainer
  scripts.
- `swift test --filter qwen3` passed with 24 tests covering text tokenization,
  speech-tokenizer config, runtime fixtures, decoder Core ML conversion,
  decoder benchmarking, decoder Instruments trace summaries, and calibration
  dataset inventory.

### 2026-05-31 Calibration Code Fixture, Pass 1

Added a LibriTTS-R calibration-code fixture generator:

- `scripts/repo-maintenance/coreml-qwen3tts/generate-calibration-code-fixture.py`

Added a checked-in calibration-code fixture:

- `docs/maintainers/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json`

Added SwiftPM tests for the fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSCalibrationCodeFixtureTests.swift`

Fixture source:

- dataset: `mythicinfinity/libritts_r`
- config: `clean`
- split: `train.clean.100`
- row offset: `0`
- sample count: `3`
- model: `Qwen/Qwen3-TTS-Tokenizer-12Hz`
- Qwen3-TTS source commit:
  `022e286b98fbec7e1e916cb940cdf532cd9f488e`

Runtime findings:

- The first three LibriTTS-R rows encoded successfully through the Qwen3 12 Hz
  speech tokenizer.
- All source audio decoded at 24000 Hz, matching the tokenizer's configured
  sample rate.
- The three sampled utterances total 14.68 seconds of audio.
- The resulting decoder calibration fixture contains 185 total code steps across
  16 quantizers.
- Per-sample code shapes were `[37, 16]`, `[83, 16]`, and `[65, 16]`.
- The first pass suggests decoder bucket sizes `[40, 72, 88]` if we bucket by
  8-step multiples.
- The fixture stores full integer `audio_codes` for the small sample set, plus
  prefixes and audio/code statistics for quick review.

Safety and provenance notes:

- The generator uses Hugging Face Dataset Viewer rows for deterministic row
  offsets.
- Dataset Viewer signed audio URLs are treated as transient runtime inputs and
  are not written to the committed fixture.
- The committed fixture omits dataset-internal file paths and machine-local
  Qwen source paths.
- The fixture is useful for decoder W8A8 calibration probing, but it is not
  enough for full-stack Qwen3-TTS calibration because it does not exercise text
  prompts, autoregressive talker states, code-predictor states, speaker
  embeddings, or reference conditioning.

Immediate implications:

- The decoder quantization lane now has representative real-speech code tensors,
  not only the synthetic 8-frame fixture.
- The next Core ML compression slice can try Core ML Tools activation
  calibration against these real code tensors and compare CPU/GPU/ANE dispatch
  after W8A8 conversion.
- Longer and speaker-diverse calibration samples should be selected before any
  quality-sensitive compression decision. This pass intentionally proves the
  extraction path first.

### 2026-05-31 Metal Flash Attention Survey, Pass 1

Reviewed the Swift/Metal FlashAttention port:

- repository: `https://github.com/philipturner/metal-flash-attention`
- current `main` commit inspected:
  `8671cddc38f19a6eadb804dee6a3ca2954b8bf32`
- latest tag observed: `v1.0.1`
- license: MIT
- package product: `FlashAttention`
- declared platforms: iOS 17, macOS 14, tvOS 17, visionOS 1

Package shape:

- The package exposes a Swift `AttentionDescriptor` plus generated Metal
  attention kernels.
- It is a Swift Package Manager library, not a Core ML or MLX layer.
- The implementation focuses on single-headed attention kernels and uses
  runtime Metal shader generation.
- It has separate forward, backward-query, and backward-key-value kernel types.
- The README recommends `swift build -Xswiftc -Ounchecked` and
  `swift test -Xswiftc -Ounchecked` for the intended workflow.

Qwen3-TTS shape fit:

- `Qwen/Qwen3-TTS-12Hz-0.6B-Base` talker config has hidden size 1024,
  16 attention heads, 8 key-value heads, head dimension 128, and 28 hidden
  layers.
- Its code predictor config has hidden size 1024, 16 attention heads, 8
  key-value heads, head dimension 128, and 5 hidden layers.
- The 12 Hz speech-tokenizer decoder config has hidden size 512, 16 attention
  heads, 16 key-value heads, and 8 hidden layers.
- The head dimension and Apple GPU target make this relevant to a custom
  Swift/Metal talker or decoder path, but the current package is not already a
  multi-head, grouped-query, causal, KV-cache-aware Qwen attention replacement.

Local validation:

- Environment: Apple M4 Pro, macOS 26.5, Xcode 26.5.
- `swift test -Xswiftc -Ounchecked --filter SquareAttentionTest.testCorrectness`
  built the package successfully.
- The test failed when the package tried to compile generated Metal source at
  runtime.
- The Metal compiler rejected inline assembly strings such as
  `air.simdgroup_async_copy_1d.p3i8.p1i8` and reported missing
  `__metal_simdgroup_async_copy_1d`, `__metal_simdgroup_async_copy_2d`, and
  `__metal_wait_simdgroup_events` symbols.

Compatibility notes:

- This failure matches current public notes around macOS 15+ restricting
  `__asm` in runtime-compiled Metal shaders.
- A Python package named `mps-flash-attn` documents a fork-like adaptation that
  adds an `xcrun metal` fallback for macOS 15+ and causal masking support.
- That package is useful evidence, but it is not a Swift dependency decision for
  SpeakSwiftly. It should be inspected separately before trusting its forked
  kernel path.

Immediate implications:

- Metal FlashAttention is not useful for the current decoder-only Core ML path.
  Core ML owns its own graph execution and cannot call this Swift package inside
  an ML Program.
- It could be useful if the first-party Qwen3-TTS effort grows a separate
  Swift/Metal backend or a custom MLX-adjacent attention stage.
- The likely target would be the autoregressive talker and code predictor, not
  the speech-tokenizer decoder-only fixture we are currently quantizing.
- Before any dependency adoption, the next research slice should build a tiny
  standalone causal forward-attention probe with Qwen-like dimensions
  `(heads: 16, kv_heads: 8, head_dim: 128)`, verify current macOS/Xcode
  compilation behavior, and compare it against MLX/Core ML attention timing.
- If we pursue it, treat the work as a durable custom GPU-kernel building block,
  not a local Core ML implementation detail. It would require explicit buffer
  layout, causal masking, grouped-query attention, KV-cache ownership, and
  Instruments verification.

## Open Decisions

- Which upstream checkpoint should be the first target: 0.6B Base, 1.7B Base, or
  a smaller tokenizer-only path first?
- Should the first full model probe graduate from the maintained script path
  into a package executable target, or stay outside the package until conversion
  evidence exists?
- Should the tokenizer ultimately be ported directly to Swift, shared through a
  generated vocabulary artifact, or vendored from a proven tokenizer library?
- Should Metal FlashAttention stay as a separate custom-GPU-kernel research
  lane, or should it become part of the Qwen3-TTS backend story only if Core ML
  cannot handle autoregressive attention efficiently?
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
- Core ML Tools optimization overview:
  https://apple.github.io/coremltools/docs-guides/source/opt-overview.html
- Core ML Tools quantization overview:
  https://apple.github.io/coremltools/docs-guides/source/opt-quantization-overview.html
- Core ML Tools linear quantization guide:
  https://apple.github.io/coremltools/docs-guides/source/opt-quantization.html
- Core ML Tools palettization overview:
  https://apple.github.io/coremltools/docs-guides/source/opt-palettization-overview.html
- Apple MLComputeUnits documentation:
  https://developer.apple.com/documentation/coreml/mlcomputeunits
- Apple Neural Engine transformer guidance:
  https://machinelearning.apple.com/research/neural-engine-transformers
- Metal FlashAttention Swift package:
  https://github.com/philipturner/metal-flash-attention
- mps-flash-attn package notes:
  https://pypi.org/project/mps-flash-attn/
