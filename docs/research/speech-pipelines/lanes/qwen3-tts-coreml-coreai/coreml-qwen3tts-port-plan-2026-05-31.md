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

As of 2026-06-23, Apple's newer Core AI stack and `coreai-torch` package are
also part of this investigation. Core AI may become the better Apple-native
runtime path if it can preserve and lower the Qwen talker/code-predictor graph
more cleanly than the hand-rolled Core ML Tools path. Treat that as an evidence
question, not a rename: the current Core ML decoder residency and quality data
remain useful until a Core AI probe produces matched Qwen3-TTS outputs.

Foundation Models is not a Qwen3-TTS acoustic-generation replacement. It may
matter later for app-level intelligence, guided prompt orchestration, tool
calling, evaluations, or product features, but it does not replace first-party
Qwen3-TTS speech generation unless Apple exposes relevant speech or audio
generation primitives.

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
- a runtime-choice decision between hand-rolled Core ML, Core AI through
  `coreai-torch`, ExecuTorch MLX, and ExecuTorch Core ML before any public
  backend surface is added

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
- For Core AI probes, record the `coreai-torch` version, PyTorch version,
  `torch.export` shape assumptions, preserved composite ops, custom lowerings,
  externalized submodules, generated Core AI IR shape, and any runtime compile
  or dispatch evidence.
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

## Runtime Choice Matrix

Use this matrix before widening the branch into another runtime dependency.

| Route | Best first use | What would make it win | Main risk | Current status |
| --- | --- | --- | --- | --- |
| Hand-rolled Core ML Tools | Decoder residency, bucket routing, ANE/Core ML dispatch proof | Gives explicit stage control, stable parity, and better Apple-platform deployment than MLX | Talker/code-predictor graph may fragment into too many tiny calls or unsupported cache shapes | Decoder probe is mature; public backend remains gated |
| Core AI through `coreai-torch` | Talker/code-predictor export and Core AI IR feasibility | Preserves attention, RoPE, RMSNorm, cache, and codebook boundaries more cleanly than Core ML Tools, with compiler-visible composite ops | New stack may still require custom lowerings or Metal kernels before Qwen3-TTS works end to end | New candidate lane; start with design plus tiny export probe |
| ExecuTorch MLX delegate | Apple-Silicon GPU comparison for autoregressive Qwen stages | Runs Qwen-like PyTorch graphs with less bespoke Swift/Metal/Core ML glue and useful LLM runtime infrastructure | Delegate is experimental and may add runtime/package complexity without better quality or latency | Exploration candidate after Core AI export feasibility is understood |
| ExecuTorch Core ML delegate | Runtime/package comparison against hand-rolled Core ML | Provides a maintained edge runtime and Core ML partitioning path with iOS/macOS packaging | May obscure the exact stage placement and residency controls this branch is trying to measure | Comparison candidate, not the first implementation route |
| Existing MLX Qwen path | Baseline production-quality reference | Remains simpler, better quality, or faster than Apple-native alternatives | Does not answer mobile/Core AI/Core ML deployment questions by itself | Current baseline for quality and latency comparison |

## Core AI / CoreAI-Torch First Slice

Start with a small design-and-export slice before any runtime integration:

1. Add a short decision memo or subsection recording current Core AI,
   `coreai-torch`, ExecuTorch MLX, and ExecuTorch Core ML evidence and the
   acceptance criteria for each route.
2. Identify the smallest Qwen3-TTS talker/code-predictor subgraph that exercises
   the hard parts: attention or SDPA, RoPE, RMSNorm, KV/cache input-output shape,
   codebook ordering, and the first codec-token output.
3. Attempt a local `torch.export` plus `coreai-torch` conversion for that
   subgraph only, with fixed shapes and tiny fixture inputs.
4. Record whether conversion preserves useful composite boundaries, requires
   custom lowerings, needs inline Metal kernels, or loses too much semantic
   structure to be a better route than the existing Core ML Tools probes.

Do not begin with the full Qwen3-TTS model, full audible generation, or a public
`SpeechBackend`. The first useful answer is whether Core AI can represent the
talker boundary more cleanly than the current Core ML route.

The pinned preflight fixture is
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json`. It is
generated by:

```bash
uv run --script scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py \
  --created-at-utc 2026-06-23T00:00:00Z \
  --report docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json
```

The opt-in command is the same script with `--mode export-smoke
--allow-runtime-imports`. Keep that mode explicit because it imports Python ML
packages, but do not add those packages as project dependencies unless the route
graduates beyond a probe.

The current local export-smoke report is
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-export-smoke-12hz.json`.
It confirms Xcode beta's Core AI developer tools are visible when
`DEVELOPER_DIR` points at the beta Xcode install: `coreai-build` resolves and
`xctrace` lists the `Core AI` Instruments template. A first opt-in run with
`torch` 2.11.0 and `coreai-torch` 0.4.0 converted the tiny Qwen-shaped talker
boundary to Core AI IR. The exported graph preserved visible calls for
`scaled_dot_product_attention`, `rsqrt`, `cos`, and `sin`.

This is only a toy-boundary proof that the route is locally runnable. It does
not prove real Qwen3-TTS conversion, first-token parity, compile latency,
runtime quality, or audio quality. The next slice should try the real
talker/code-predictor boundary, or write down the exact fixture needed before
that conversion is meaningful.

The pinned real-boundary design fixture is
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-plan-12hz.json`. It is
generated by:

```bash
uv run --script scripts/repo-maintenance/coreml-qwen3tts/probe-coreai-talker-boundary.py \
  --mode real-boundary-plan \
  --created-at-utc 2026-06-23T00:00:00Z \
  --report docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-plan-12hz.json
```

That fixture narrows the first real Core AI target to one main-talker decode
step after upstream PyTorch has built prompt embeddings and prefilled the cache.
It includes the previous first-codebook token, prefilled main-talker KV cache,
cache position or generation step, RoPE/RMSNorm/attention, and first-codebook
logits. It identifies code-predictor continuation inputs for codebooks 1 through
15 but keeps them out of the first Core AI conversion so first-token parity can
be checked before the scope widens.

The runtime capture report is
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-capture-12hz.json`. It was
captured from the cached `Qwen/Qwen3-TTS-12Hz-0.6B-Base` snapshot with the
live-service headroom wrapper, CPU `bfloat16`, deterministic decoding, and no
speech-tokenizer decode or audible playback. `coreai-torch` 0.4.0 currently
selects a Torch 2.8 through 2.11 range, so the probe uses Torch and Torchaudio
2.11.0 rather than the older Torch 2.7-era Qwen script pin.

The capture records one prefill call, two decode calls, and two code-predictor
generate calls. The first decode step starts from previous first-codebook token
1221, produces first-codebook logits with shape `[1, 3072]` and SHA-256
`ed7457868ab0c6c0fafc41e2a0667401a9fe7e1246492de94b8958a8839a8eb2`, and ranks
token 1342 first. The output main-talker cache has sequence length 10 across 28
layers. The paired code-predictor call receives `[1, 2, 1024]` embeddings and
returns 15 continuation codebooks, yielding a captured two-frame talker code
prefix of `[1221, 1342]` for codebook 0.

The next meaningful Core AI slice is no longer planning-only. Build a real
export wrapper around captured Qwen tensors, starting with the code-predictor
or post-code-predictor main-talker decode boundary, and compare exported Core AI
logits or codebook outputs against this PyTorch capture. Keep runtime capture
explicit, use the live-service headroom wrapper, require `--allow-model-load`,
and commit only compact metadata such as tensor names, shapes, deterministic
hashes, and top candidate token IDs. Large tensors stay under `.local/`.

The first real export report is
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-code-predictor-export-smoke-12hz.json`.
It captures the first code-predictor embeddings from the same non-audible
generation path, then exports the real code-predictor prefill boundary. Strict
`torch.export` succeeds, the exported program reproduces the PyTorch logits with
max absolute difference `0.0`, and `coreai-torch` emits Core AI IR. The captured
input shape is `[1, 2, 1024]` with SHA-256
`28c0a98f004e851b6c6a97442a7828d69b227ea462ddf64d70db9d8ee562f652`; the
reference logits shape is `[1, 2, 2048]` with SHA-256
`e66ed386c2eb6f1b6d14001d8d820059e99ad701ae58b9df4a803ada86173d08`.

This is a stronger Core AI signal than the toy boundary: it proves that at
least one real Qwen3-TTS autoregressive submodel can move from live PyTorch
inputs through `torch.export` into Core AI IR while preserving exact
exported-program parity. It still does not prove the main-talker cache boundary,
Core AI runtime latency, ANE/GPU placement, end-to-end audio quality, or public
backend suitability. The next hard probe should flatten the main-talker decode
step into explicit cache tensors and test Core AI conversion against the
captured first-codebook logits.

The main-talker frozen-cache export reports are
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-main-talker-export-smoke-12hz.json`
and
`docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-main-talker-export-smoke-fp32-12hz.json`.
They capture the real first decode-step inputs, clone the 28-layer KV cache,
replay the main-talker decode math with explicit frozen cache tensors, and
compare the replay and exported program against the captured first-codebook
logits. The BF16 replay and strict `torch.export` both match the PyTorch logits
exactly. Initial `coreai-torch` conversion failed with `dtype f32 vs bf16`
because the exported graph contained a redundant zero additive attention mask;
omitting that all-zero decode mask preserves exact parity and lets BF16 convert
to Core AI IR. The same probe in float32 also reaches Core AI IR with exact
replay and exported-program parity.

That makes the Core AI route materially more plausible than it was at the
start of the branch, but the route is still not backend-ready. The real
code-predictor boundary converts to Core AI IR, and the real main-talker decode
graph exports and converts with exact parity; however, the current main-talker
probe uses frozen cache buffers rather than mutable Core AI state or explicit
runtime cache inputs. The next implementation slice should map the cloned KV
cache into Core AI mutable state or explicit cache inputs and re-run parity
before any latency or quality claims.

## Runtime Route Comparison After Core AI Probes

As of the 2026-06-23 Core AI probe pass, Core AI is the strongest next
Apple-native route to keep testing, but it is not a backend integration decision
yet.

| Route | Current evidence | What it is best for next | Do not use it for yet |
| --- | --- | --- | --- |
| Core AI through `coreai-torch` | Toy boundary converts; real code predictor converts to Core AI IR; real main-talker frozen-cache decode exports and converts with exact BF16 and float32 parity | Mutable-state/cache modeling, Core AI Debugger/Instruments profiling | Public `SpeechBackend`, end-to-end quality claims, or resident-latency claims |
| Hand-rolled Core ML Tools | Decoder buckets have fp16 and scoped W8A8 parity, dispatch, resident-catalog, and listening evidence | Keep decoder as the stable measured baseline and compare package size/residency against Core AI outputs | Talker/code-predictor integration until graph boundaries are understood |
| ExecuTorch MLX delegate | Official tree exposes an experimental MLX backend with C++ runtime, FlatBuffer bytecode, LLM KV-cache and attention infrastructure | A comparison lane if Core AI mutable state becomes the bottleneck | First Apple-native route while Core AI is already producing matched local Qwen exports |
| ExecuTorch Core ML backend | Official Apple runtime packaging includes Core ML and MPS backends for iOS/macOS Swift/Objective-C/C++ apps | Packaging/runtime comparison if Core AI graph export works but app integration looks worse than ExecuTorch | Replacing the hand-rolled Core ML decoder evidence without a placement/residency comparison |
| Foundation Models / Core AI app intelligence | Apple positions Foundation Models for Apple Intelligence capabilities, guided generation, and tool calling | Prompt orchestration, app-level features, or product intelligence outside acoustic generation | Qwen3-TTS acoustic generation unless Apple exposes relevant speech/audio generation primitives |

The practical recommendation is to stay on the Core AI branch for one more
serious technical slice, not pivot immediately to ExecuTorch. The next slice
should answer whether the frozen KV cache can become Core AI mutable state or
explicit runtime inputs. If that blocks, ExecuTorch MLX becomes the next
comparison because its LLM-specific cache and attention infrastructure maps
directly onto the remaining Qwen problem. ExecuTorch Core ML remains a
packaging/backend comparison, not the first route to resolve Qwen graph shape.

## Core AI ANE and Compression Route

As of 2026-06-24, the Core AI compression route is clearer than the initial
`coreai-torch` question. `coreai-torch` is the bridge from PyTorch
`ExportedProgram` to Core AI IR. Compression is a separate PyTorch-side
workflow: Apple's `coreai-opt` package documents quantization, palettization,
pruning, mixed-precision recipes, activation quantization, and Core AI
integration before conversion.

That means Core AI ANE work should not assume that the Core ML Tools W8A8
decoder recipe transfers directly. The next route is:

1. Start from a PyTorch boundary wrapper that already has parity.
2. Apply `coreai-opt` compression to the PyTorch model or selected submodules.
3. Validate compressed PyTorch parity before conversion.
4. Convert with `coreai-torch` to a `.aimodel`.
5. Compile with `coreai-build compile --preferred-compute neural-engine`.
6. Inspect with `coreai-build inspect --json` for storage, operation, and
   compute evidence.
7. Profile with Core AI Runtime or Instruments before claiming ANE benefit.

Local Xcode 27 beta tooling supports this probe shape. `coreai-build` exposes
`compile`, `package`, `inspect`, and `metadata`. The `compile` subcommand
accepts `--preferred-compute gpu`, `--preferred-compute neural-engine`, or
`--preferred-compute none`; `inspect` can emit JSON with IO, metadata, storage,
compute, and operation distribution. A separate `coreai-inspect` or
`coreai-perf` binary was not found through `xcrun`; use `coreai-build inspect`
and the Core AI Runtime/debugging surface instead.

The first compression probe should target the code predictor, not the main
talker. The code predictor already has exact exported-program parity and Core AI
IR conversion, while the main talker still has the mutable-cache/state blocker.
Begin with weight-only W8 on code-predictor linear layers because it is
data-free and fast enough to prove the plumbing. Then try W8A8 activation
quantization on linear/matmul-heavy code-predictor or main-talker projections
only after the W8 path converts, compiles, and inspects cleanly. Palettization
is a size and memory-pressure candidate, not an assumed hot-latency win.

Pinned plan artifact:

- `docs/maintainers/coreml-qwen3tts/coreai-ane-compression-plan-12hz.json`

Important guardrail: `--preferred-compute neural-engine` is only a compile
preference. It is not dispatch proof. Treat Core AI `inspect` output and
Instruments/Core AI Runtime profiling as the evidence gates, just as the Core
ML decoder lane required Instruments rows before claiming Neural Engine
execution.

Authoritative docs checked for this comparison:

- CoreAI-Torch conversion workflows:
  <https://apple.github.io/coreai-torch/main/guides/conversion-workflows.html>
- Core AI Optimization:
  <https://apple.github.io/coreai-optimization/>
- ExecuTorch iOS/macOS integration and Apple backends:
  <https://docs.pytorch.org/executorch/stable/using-executorch-ios.html>
- ExecuTorch MLX delegate README:
  <https://github.com/pytorch/executorch/blob/main/backends/mlx/README.md>
- ExecuTorch Core ML backend README:
  <https://github.com/pytorch/executorch/blob/main/backends/apple/coreml/README.md>

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/text-token-fixture-0.6b-base.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-config-12hz.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-runtime-preflight-12hz.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-preflight-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-torch27-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-fixed16q-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-export-fixed16q-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-export-strict-fixed16q-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-benchmark-static-mask-12hz.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-xctrace-static-mask-12hz.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-dataset-inventory-2026-05-31.json`

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

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json`

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

### 2026-05-31 Decoder Quantization Preflight, Pass 1

Added a decoder Core ML quantization preflight script:

- `scripts/repo-maintenance/coreml-qwen3tts/quantize-speech-tokenizer-decoder-coreml.py`

Added a checked-in quantization preflight fixture:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-quantization-preflight-12hz.json`

Added SwiftPM tests for the fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightTests.swift`

Core ML Tools API findings:

- Local Core ML Tools version: `9.0`.
- `coremltools.optimize.coreml.linear_quantize_weights` is available.
- `coremltools.optimize.coreml.experimental.linear_quantize_activations` is
  available.
- Apple's Core ML Tools docs distinguish weight-only quantization from W8A8.
  Weight-only quantization compresses stored weights, but consuming ops still
  compute in float precision. W8A8 requires activation calibration sample data
  and then int8 weight quantization of the activation-quantized model.

Calibration-shape findings:

- Current converted decoder package input shape: `[1, 8, 16]`.
- The synthetic runtime fixture has `audio_codes` shape `[8, 16]` and matches
  the current fixed graph.
- The real LibriTTS-R calibration fixture has code shapes `[37, 16]`,
  `[83, 16]`, and `[65, 16]`.
- None of the real-speech calibration samples match the current 8-step graph.

Immediate implications:

- The current local decoder package can support a synthetic W8A8 smoke probe,
  which is useful for API compatibility and model-load testing.
- It cannot support representative real-speech W8A8 activation calibration
  without either truncating data or converting longer fixed-shape decoder
  packages. Truncating the samples would be misleading for quality and dispatch
  decisions.
- Representative decoder W8A8 now needs bucketed decoder conversions for
  `[1, 40, 16]`, `[1, 72, 16]`, and `[1, 88, 16]`, matching the first
  calibration fixture's suggested buckets.
- After those packages exist, the same quantization script can run activation
  calibration with real code tensors and feed the benchmark plus Instruments
  trace scripts.

Validation:

- Quantization preflight generation succeeded with Python 3.12 and Core ML
  Tools 9.0.
- A local uncommitted synthetic quantization runtime smoke was also run against
  the 8-step decoder package under `.local/coreml-qwen3tts`.
- Weight-only int8 quantization succeeded in about 5.2 seconds and produced a
  local package of 115025901 bytes, down from the original package's roughly
  436 MB local disk footprint.
- The W8A8 synthetic smoke completed activation calibration but failed while
  saving the quantized model:
  `ValueError: In op, of type quantize, named quantize_0, the named input
  scale must have the same data type as the named input input. However, scale
  has dtype fp32 whereas input has dtype int32.`
- Interpretation: global activation quantization is likely trying to insert a
  quantize/dequantize pair on the integer `audio_codes` input path. That does
  not prove the decoder cannot use W8A8. It means the next W8A8 slice should
  scope activation quantization to float-producing decoder ops, or split the
  integer code lookup from the float decoder graph before treating W8A8 as
  blocked.
- `jq empty` passed for the quantization preflight fixture.
- A path hygiene scan found no `/private`, `/Users`, or `~/` strings in the
  new script or fixture.

### 2026-05-31 Decoder Bucket Planning, Pass 1

Added fixed-shape bucket support to the decoder conversion probe:

- `scripts/repo-maintenance/coreml-qwen3tts/convert-speech-tokenizer-decoder-coreml.py`

Added a decoder bucket planner:

- `scripts/repo-maintenance/coreml-qwen3tts/plan-speech-tokenizer-decoder-buckets.py`

Added a checked-in bucket plan fixture:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-bucket-plan-12hz.json`

Added SwiftPM tests for the bucket plan:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLBucketPlanTests.swift`

Implementation notes:

- The conversion script now accepts `--pad-code-steps`.
- Padding uses `-1`, matching the upstream decoder convention for missing code
  steps. The decoder wrapper clamps negative codes to zero before lookup, and
  the report records both valid and padded output sample counts so later runtime
  code can trim deliberately.
- The existing 8-step preflight fixture now records padding metadata even though
  it does not need padding.

Bucket plan:

- Bucket 40 accepts the `[37, 16]` LibriTTS-R sample and pads 3 code steps.
- Bucket 72 accepts the `[65, 16]` LibriTTS-R sample and pads 7 code steps.
- Bucket 88 accepts the `[83, 16]` LibriTTS-R sample and pads 5 code steps.
- Required static decoder input shapes are `[1, 40, 16]`, `[1, 72, 16]`, and
  `[1, 88, 16]`.

Immediate implications:

- The next heavy runtime step is no longer ambiguous: run the three generated
  conversion commands, starting with bucket 40 as the smallest real-speech
  calibration bucket.
- Bucketed conversion packages can still be created from the synthetic fixture
  padded to each shape. Representative W8A8 calibration should then use the
  real LibriTTS-R codes assigned to each bucket.
- W8A8 remains blocked on activation-quantization scoping around integer
  `audio_codes`, but it is no longer blocked on deciding bucket shapes.

Validation:

- The bucket planner generated the checked fixture successfully.
- Bucket-40 conversion preflight generated a local uncommitted preflight report
  with input shape `[1, 40, 16]`, output shape `[1, 76800]`, and 32 padded
  synthetic code steps.
- Bucket-40 runtime conversion also succeeded with the existing static-mask
  export path.
- Bucket-40 CPU-only Core ML prediction returned output shape `[1, 76800]`
  with max absolute difference `0.00019849836826324463` from the PyTorch
  wrapper output.
- Bucket-72 runtime conversion also succeeded with CPU-only Core ML output shape
  `[1, 138240]` and max absolute difference `0.00019851326942443848` from the
  PyTorch wrapper output.
- Bucket-88 runtime conversion also succeeded with CPU-only Core ML output shape
  `[1, 168960]` and max absolute difference `0.00019818544387817383` from the
  PyTorch wrapper output.
- The bucket-40 local `.mlpackage` disk footprint is about 436 MB, matching the
  original 8-step package closely enough to confirm weights dominate package
  size for these fixed decoder shapes. Bucket 72 and bucket 88 had the same
  approximate 436 MB local disk footprint.
- Added checked-in bucket-40 conversion report:
  `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-bucket-40-12hz.json`.
- Added checked-in bucket-72 and bucket-88 conversion reports:
  `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-bucket-72-12hz.json`
  and
  `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-bucket-88-12hz.json`.
- The first representative decoder shape set is now complete. The next W8A8
  step can load bucket-specific packages and build calibration sample data from
  the real LibriTTS-R code tensors assigned to each bucket.

### 2026-05-31 Decoder Scoped W8A8 Smoke, Pass 1

Extended the decoder quantization probe so activation quantization can be
scoped by graph role:

- `scripts/repo-maintenance/coreml-qwen3tts/quantize-speech-tokenizer-decoder-coreml.py`

Added checked-in reports for the fp16 decoder base and scoped W8A8 smoke:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-fp16-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-quantization-fp16-compute-only-12hz.json`

Added SwiftPM fixture coverage:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLProbeTests.swift`
- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightTests.swift`

Graph and Core ML Tools findings:

- The converted decoder MIL graph starts with integer `audio_codes` handling:
  casts, clipping, transposes, slices, and `gather` embedding lookups before the
  float convolution and transformer work.
- Core ML Tools `OptimizationConfig` can scope compression globally, by op type,
  or by op name. That gives us a way to avoid activation quantization on the
  integer lookup path without splitting the graph yet.
- Global activation quantization still fails on the integer path with an
  `int32` input versus `fp32` scale mismatch.
- Compute-only activation quantization on the fp32 decoder avoids the integer
  path, but fails later with an `fp32` input versus `fp16` scale mismatch.
- The successful first W8A8 smoke path is an fp16 base package plus activation
  quantization scoped to `conv`, `linear`, `matmul`, and `conv_transpose`, then
  int8 weight quantization of that activation-quantized model.

Validation:

- The fp16 decoder conversion succeeded for the 8-step fixture, producing a
  local package of about 218 MB.
- CPU-only Core ML prediction from the fp16 package returned output shape
  `[1, 15360]` with max absolute difference `0.0017573237419128418` from the
  PyTorch wrapper output.
- The scoped W8A8 smoke succeeded against that fp16 package in about 114 seconds
  and produced a local package of 114795122 bytes, roughly 109 MB.
- CPU-only prediction from the scoped W8A8 package returned output shape
  `[1, 15360]` with max absolute difference `0.008880615234375` and mean
  absolute difference `0.0021852878853678703` versus the fp16 package output.
- Core ML Tools emitted divide-by-zero and invalid-value runtime warnings during
  compression. The package still saved, reloaded, and predicted successfully, so
  the warning is a follow-up inspection item rather than a conversion blocker.

Immediate implications:

- W8A8 is no longer blocked at the "can Core ML Tools produce a decoder package"
  level for the 8-step speech-tokenizer decoder smoke.
- This pass still does not prove audio quality, representative calibration, or
  Neural Engine dispatch. It only proves a scoped conversion route and a
  CPU-loadable/predictable artifact.
- The next W8A8 slice should use the bucketed decoder packages with the real
  LibriTTS-R calibration code tensors, then profile fp16 and W8A8 packages with
  Instruments before deciding whether this decoder shape is actually useful for
  an Apple-silicon backend.

### 2026-05-31 Decoder Representative W8A8, Bucket 40, Pass 1

Extended the decoder quantization probe to build runtime calibration sample data
from bucketed real-speech code tensors:

- `scripts/repo-maintenance/coreml-qwen3tts/quantize-speech-tokenizer-decoder-coreml.py`

Added checked-in bucket-40 fp16 and representative W8A8 reports:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-bucket-40-fp16-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-quantization-bucket-40-fp16-representative-12hz.json`

Added SwiftPM fixture coverage:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLProbeTests.swift`
- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightTests.swift`

Implementation notes:

- Representative calibration now uses the bucket plan to find samples assigned
  to the fixed decoder input shape.
- For bucket 40, sample `730_358_000003_000002` has real `audio_codes` shape
  `[37, 16]`, is padded to `[1, 40, 16]` with `-1`, and records both valid and
  padded output sample counts.
- The W8A8 report now distinguishes synthetic and representative smoke modes
  and records valid-output and padded-tail prediction deltas separately when a
  bucketed sample has a known valid output length.

Validation:

- Bucket-40 fp16 conversion succeeded with CPU-only Core ML output shape
  `[1, 76800]`.
- The bucket-40 fp16 package's mean absolute difference from the PyTorch wrapper
  was `0.0004596624639816582`. Its max absolute difference was
  `0.058486729860305786`, which is much larger than the 8-step fp16 smoke and
  should be inspected before treating bucketed fp16 as quality-equivalent.
- Representative bucket-40 scoped W8A8 succeeded in about 104.5 seconds and
  produced a local package of 114801996 bytes.
- CPU-only prediction from the representative W8A8 package returned output
  shape `[1, 76800]` with max absolute difference `0.286285400390625` and mean
  absolute difference `0.012680189684033394` versus the bucket-40 fp16 package.
- The valid output region, not just the padded tail, has the same max absolute
  difference: valid-region max `0.286285400390625`, valid-region mean
  `0.012970197945833206`.

Immediate implications:

- The scoped W8A8 path survives representative bucketed activation calibration
  at the tool and model-loading level.
- The representative output drift is large enough that W8A8 should not advance
  directly to backend integration. The next pass should inspect audio output,
  try a broader calibration set, and compare alternative activation scopes or
  quantizer settings before spending much time on dispatch profiling.
- Bucket 72 and bucket 88 should wait until bucket-40 quality behavior is
  understood, unless the next goal is only to characterize whether drift scales
  with output length.

### 2026-05-31 Decoder Audio Inspection, Bucket 40 W8A8, Pass 1

Added a guarded Core ML maintenance wrapper:

- `scripts/repo-maintenance/coreml-qwen3tts/run-with-live-service-headroom.sh`

The wrapper does three jobs for local Core ML/Qwen maintenance commands:

- unload live `SpeakSwiftlyServer` resident models before the command starts;
- optionally clear stale artifacts under `.local/coreml-qwen3tts`;
- reload live resident models on exit, including after a failed inner command.

Added a decoder audio inspection probe:

- `scripts/repo-maintenance/coreml-qwen3tts/inspect-speech-tokenizer-decoder-audio.py`

Added a checked-in audio inspection report:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-audio-inspection-bucket-40-w8a8-12hz.json`

The local WAV artifacts are intentionally not checked in:

- `.local/coreml-qwen3tts/audio-inspection/bucket-40-representative-w8a8/baseline-fp16.wav`
- `.local/coreml-qwen3tts/audio-inspection/bucket-40-representative-w8a8/candidate-w8a8.wav`
- `.local/coreml-qwen3tts/audio-inspection/bucket-40-representative-w8a8/candidate-minus-baseline.wav`
- `.local/coreml-qwen3tts/audio-inspection/bucket-40-representative-w8a8/baseline-fp16-valid.wav`
- `.local/coreml-qwen3tts/audio-inspection/bucket-40-representative-w8a8/candidate-w8a8-valid.wav`

Validation:

- The first guarded run successfully unloaded live resident models, but the
  inner `uv` command hit a sandbox permission error while opening the existing
  `uv` cache. The wrapper still reloaded live resident models afterward.
- The guarded command was rerun with elevated filesystem access for the `uv`
  cache. It unloaded live resident models, ran the audio inspection, and
  reloaded live resident models after completion.
- The audio inspection used CPU-only Core ML predictions for both the fp16
  bucket-40 decoder and the representative W8A8 bucket-40 decoder.
- The valid decoded region has max absolute difference `0.1773681640625`, mean
  absolute difference `0.012432368472218513`, and RMS difference
  `0.018015170469880104`.
- The padded tail has max absolute difference `0.26751708984375`, mean absolute
  difference `0.008735979907214642`, and RMS difference
  `0.020247511565685272`.
- In the valid decoded region, 8 of 12 quarter-second windows exceed mean
  absolute difference `0.01`. The top mean-diff windows start at 1.25 seconds,
  2.5 seconds, 2.0 seconds, 0.0 seconds, and 1.5 seconds.

Immediate implications:

- The representative W8A8 drift is not isolated to padding. The valid audio
  region has broad drift across most of the utterance.
- A wider calibration set is still worth testing, but this result raises the
  bar: we need audible review and alternative quantization settings before
  spending much more time on Neural Engine dispatch for this decoder.
- Talker-generated Qwen3 code histories should be added as a separate
  calibration/evaluation source. Current LibriTTS-R codes are real human speech
  encoded through Qwen3-TTS's tokenizer, not codes from another TTS model, but
  they may still differ from the code distribution produced by the Qwen3 talker.

### Later Decoder Windowing Experiment

Record this as a later experiment, not the next W8A8 fix:

- Take complete generated code sequences with known full-sequence decoder output.
- Decode fixed-size windows of code steps with left and right overlap.
- Keep only the stable center region from each decoded window.
- Crossfade or otherwise smooth joins between retained center regions.
- Decode the final remainder with padding.
- Compare the reconstructed stream-like output against full-sequence decode
  numerically and by listening before considering any streaming-style decoder
  path.

This is a conscious approximation because the Qwen3-TTS speech tokenizer decoder
is a full-sequence decoder, not a proven causal streaming decoder.

### Calibration Clarification

Core ML Tools activation quantization calibration is input-only. The API takes
`sample_data` dictionaries in the same shape as `MLModel.predict(...)`, runs
those inputs through the original float model, records intermediate activation
ranges, and inserts quantize/dequantize pairs from those observed ranges. It
does not take target output waveforms, compare candidate outputs to reference
audio, or optimize quantization parameters against an output loss.

For the current decoder W8A8 work, that means:

- Our calibration samples are only `audio_codes` inputs.
- Output audio is used for evaluation after conversion, not for calibration.
- Better calibration can improve observed activation ranges if the inputs are
  more representative, but it will not directly teach the quantizer which audio
  errors matter.
- A true input-output calibration or tuning lane would be a separate post-training
  quantization or distillation-style project, not the current Core ML Tools
  activation-calibration API.

### Decoder-First Calibration And Tuning Slice

The current implementation keeps three lanes separate:

- Calibration inputs: `generate-calibration-code-fixture.py` now defaults to a
  24-sample LibriTTS-R preflight plan and records stratification targets for
  short, medium, long, speaker-diverse, silence/energy-varied, and bucket-edge
  samples.
- Talker-code inputs: `generate-talker-code-fixture.py` plans and can capture
  Qwen3 talker-generated `audio_codes` by wrapping `speech_tokenizer.decode`,
  recording the exact decode input, and then calling the original decode.
- Output-aware tuning: `probe-decoder-alignment-tuning.py` is separate from Core
  ML calibration. It uses the fp16 PyTorch decoder as a teacher and trains a
  selected decoder-tail student with waveform L1 plus multi-resolution STFT loss
  before any later Core ML reconversion.

Checked-in preflight reports:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-code-fixture-plan-libritts-r-24-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/talker-code-fixture-plan-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/decoder-alignment-plan-12hz.json`

The quantization probe can now label W8A8 candidates and run the first
`calibration_op_group_size` matrix (`1`, `8`, `16`, `32`) for comparable
candidate reports. Output WAVs remain evaluation artifacts unless the supervised
alignment script is explicitly running.

Likely next calibration/evaluation variants:

- Increase LibriTTS-R sample count and speaker/text diversity.
- Add longer utterances and near-boundary bucket examples.
- Add Qwen3 talker-generated code histories as a separate calibration/eval
  source because generated codes may occupy a different distribution than human
  audio re-encoded through the tokenizer.
- Compare per-tensor versus any available scoped/per-op quantization variants,
  and consider disabling activation quantization for numerically sensitive
  decoder regions if audio drift localizes to specific op families.

### Upstream Chunked Decode Baseline

The upstream 12 Hz speech-tokenizer decoder already exposes
`chunked_decode(codes, chunk_size=300, left_context_size=25)`. The later decoder
windowing experiment should reproduce that behavior first, then compare smaller
fixed-bucket overlap and crossfade variants against both upstream chunked decode
and full-sequence decode.

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

### 2026-05-31 Metal Flash Attention Blocker Triage, Pass 1

Documented Apple/Metal behavior relied on in this triage:

- `MTLDevice.supportsFamily(...)` is the public feature-family check. The local
  M4 Pro reports support for Apple family 9, Metal 3, and Metal 4.
- `MTLDevice.makeLibrary(source:options:)` is the public runtime source
  compilation entry point.
- `MTLDevice.makeLibrary(data:)` is the public entry point for loading compiled
  Metal library data.
- Apple guidance still favors compiling `.metallib` artifacts ahead of time
  when practical because runtime source compilation adds latency and runtime
  compiler exposure.

Original Swift package blocker:

- Package inspected: `philipturner/metal-flash-attention`
- Command:
  `swift test -Xswiftc -Ounchecked --filter SquareAttentionTest.testCorrectness`
- Result: Swift package build succeeded, but runtime Metal source compilation
  failed before kernel execution.
- Failure mode: the Metal compiler rejected inline assembly strings such as
  `air.simdgroup_async_copy_1d.p3i8.p1i8`, and reported missing
  `__metal_simdgroup_async_copy_1d`, `__metal_simdgroup_async_copy_2d`, and
  `__metal_wait_simdgroup_events`.
- Practical interpretation: this path is blocked on current macOS/Xcode because
  it relies on private AIR/simdgroup async-copy compiler hooks that the public
  runtime Metal source compiler does not accept.

`mpsops/mps-flash-attention` triage:

- Repository inspected: `https://github.com/mpsops/mps-flash-attention`
- Current commit inspected:
  `39c2ba51cd009d02c0aa8c9b46ac7db2d1385e77`
- Submodule inspected:
  `https://github.com/imperatormk/metal-flash-attention`
- Submodule commit inspected:
  `077f1b3db785a8a9f3ccf56300a4142f249fb3fe`
- MetalASM dependency pinned in the Swift bridge:
  `https://github.com/mpsops/MetalASM.git` at version `0.1.2`.

Findings:

- `mpsops/mps-flash-attention` is not just the original Swift package wrapped
  in Python. It carries a forked Metal FlashAttention submodule that emits
  LLVM IR and assembles it through MetalASM into metallib data, then calls
  `MTLDevice.makeLibrary(data:)`.
- That fork adds features relevant to transformer inference: causal masking,
  external masks, sliding-window masking, attention bias, quantized KV support,
  batched dispatch, and a `kvRepeatFactor` path in the batched parameter buffer.
- The Swift bridge builds locally with:
  `swift build -Xswiftc -Ounchecked`
- A temporary Swift probe that called `mfa_create_kernel_v7(...)` for a small
  causal attention kernel still failed during Metal pipeline creation.
- Failure mode:
  `AGXMetalG16X Code=2`, `Compilation failed due to an interrupted connection:
  XPC_ERROR_CONNECTION_INTERRUPTED. This error occurred after multiple retries.`
- The same failure occurred when running the published `mps-flash-attn` wheel
  through a Qwen-like MPS tensor probe.

Practical interpretation:

- MetalASM avoids the original public Metal source parser failure, so it is a
  real workaround for the private `__asm` syntax problem.
- It does not currently clear the local M4 Pro / macOS 26.5 / Xcode 26.5 path,
  because the assembled metallib still causes the AGX pipeline compiler service
  to abort.
- Before adopting or forking this lane, the next useful work would be to reduce
  the generated IR to the smallest reproducer that still crashes
  `makeComputePipelineState(function:)`, then compare that with the package's
  supported macOS/Xcode matrix.

`alliprice/metal-flash-sdpa` triage:

- Repository inspected: `https://github.com/alliprice/metal-flash-sdpa`
- Current commit inspected:
  `28506caae17d638d5af077d2b945b769f21d7441`
- Implementation family: ccv Metal Flash Attention v2 through a Python/PyTorch
  C++ bridge.
- This path is separate from the Swift `metal-flash-attention` package and does
  not use the same Swift API surface.

Local probe results:

- Non-causal forward tests passed locally:
  `pytest -q tests/test_forward.py` reported `10 passed`.
- A Qwen-like non-causal probe with shape `[1, 8, 256, 64]` matched native MPS
  SDPA with max absolute difference `0.000244140625`.
- Causal attention ran and produced finite output, but parity was poor.
- A Qwen-like causal probe with shape `[1, 8, 256, 64]` produced max absolute
  difference `3.236328125` and mean absolute difference `0.10986328125` versus
  native SDPA.
- The repository's own causal test file failed locally:
  `pytest -q tests/test_causal.py` reported `4 failed, 4 passed`.
- Representative causal failures had max differences around `3.15` to `3.91`
  for forward and around `2.91` for `dQ`.

Practical interpretation:

- The ccv-backed package is not blocked by the same MetalASM/AGX pipeline crash.
- It may be useful evidence for non-causal attention or for understanding
  ccv/Draw Things kernel design.
- It is not safe for autoregressive Qwen3-TTS attention in its current local
  behavior because causal correctness is exactly the requirement we need.

Current decision:

- Do not add any Metal FlashAttention dependency to SpeakSwiftly yet.
- Do not spend Qwen3-TTS Core ML decoder time on Metal FlashAttention; it cannot
  accelerate the current Core ML ML Program.
- Keep the lane open only as a custom Swift/Metal talker/code-predictor research
  path.
- The next concrete slice, if we pursue this lane, should be a tiny independent
  Metal attention harness with:
  - Qwen-like shapes: 16 Q heads, 8 KV heads, head dimension 128
  - explicit causal masking
  - explicit GQA expansion or native grouped-query support
  - parity against native PyTorch/MLX SDPA
  - Instruments timing and dispatch evidence
  - no dependency adoption until both compile and causal parity are proven

### 2026-05-31 Metal Flash Attention Blocker Probe, Pass 2

Added a bounded blocker probe:

- `scripts/repo-maintenance/coreml-qwen3tts/probe-flash-attention-blockers.py`

Added a checked-in probe report:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/flash-attention-blocker-probe-2026-05-31.json`

Probe scope:

- The script does not add package dependencies to SpeakSwiftly.
- It invokes third-party probes through `uv` child processes and records
  structured JSON, return codes, and stderr.
- The report redacts the local `metal-flash-sdpa` checkout path and stores no
  downloaded repositories, model artifacts, wheel caches, or machine-local
  absolute paths.
- Qwen-like parity uses expanded KV heads for the current probe shape:
  16 query heads, 16 effective KV heads after expansion, sequence length 256,
  and head dimension 128. Native grouped-query support remains unproven.

`mpsops/mps-flash-attention` minimization result:

- The published `mps-flash-attn` package still aborts in AGX pipeline creation
  before the probe can reach larger Qwen-like cases.
- The crash reproduces on the first tiny non-causal shape:
  `[batch: 1, heads: 1, sequence: 16, head_dim: 32]`.
- Exit code was `133`.
- The recorded failure remains:
  `AGXMetalG16X Code=2`, `XPC_ERROR_CONNECTION_INTERRUPTED`.

Practical interpretation:

- This is smaller than the earlier Qwen-like wheel probe. The failure is not
  caused by Qwen-sized tensors, causal masking, or grouped-query shape pressure.
- MetalASM still avoids the runtime Metal source parser blocker, but the
  assembled library is not locally accepted by the AGX pipeline compiler even
  for a tiny forward kernel.
- Continuing this lane usefully would mean reducing the assembled AIR/metallib
  itself and taking that minimized compiler crash upstream. It is not ready to
  be forked into SpeakSwiftly.

`alliprice/metal-flash-sdpa` causal correctness result:

- The direct ccv-backed kernel is causal-correct for `float32`.
- `float32` causal shape `[1, 8, 256, 64]` matched the CPU causal reference with
  max absolute difference about `0.00000066`.
- `float16` causal shape `[1, 8, 256, 64]` failed causal parity with max
  absolute difference about `3.7609` and mean absolute difference about
  `0.1104`.
- The same `float16` causal output matched the non-causal reference with max
  absolute difference about `0.000232`.
- `bfloat16` showed the same pattern: poor causal-reference parity and close
  non-causal-reference parity.
- The Qwen-like expanded-KV `float16` causal shape `[1, 16, 256, 128]` also
  matched the non-causal reference, not the causal reference.
- The patched `scaled_dot_product_attention` wrapper dispatched exactly once
  and matched the direct kernel output, so the mismatch is not introduced by
  the Python dispatch wrapper.

Practical interpretation:

- The failure is not a simple mask-orientation mismatch. The `float32` causal
  path uses the expected upper-triangular causal reference correctly.
- The failure is not scale handling. The same scale and reference path pass in
  `float32`, while lower-precision causal outputs track the non-causal result.
- The current evidence points to the lower-precision causal path ignoring or
  losing causal masking inside the kernel.
- This blocks Qwen3-TTS talker and code-predictor use because the useful
  autoregressive path would need causal attention at `float16` or `bfloat16`,
  16 query heads, 8 KV heads, and head dimension 128.

Current recommendation:

- Pause FlashAttention dependency adoption for SpeakSwiftly.
- Continue the first-party Core ML decoder and quantization work independently;
  FlashAttention cannot accelerate the current Core ML ML Program.
- Reopen this lane only if:
  - `mpsops/mps-flash-attention` can produce a minimized AGX compiler report and
    an upstream fix or supported macOS/Xcode matrix, or
  - `metal-flash-sdpa` fixes lower-precision causal masking and demonstrates
    Qwen-like grouped-query parity.

### 2026-05-31 LibriTTS-R Calibration Expansion, Pass 2

The first 24-sample LibriTTS-R runtime fixture was mechanically valid but
calibration-poor: it selected a contiguous row block that all belonged to
speaker `730`. That proved the expanded fixture machinery worked, but it did
not satisfy the speaker-diversity goal.

The calibration-code fixture generator now supports explicit Dataset Viewer row
offsets through `--row-offsets`. The checked-in 24-row preflight now uses these
offsets:

- `0`
- `100`
- `250`
- `500`
- `750`
- `1000`
- `1500`
- `2000`
- `3000`
- `4000`
- `5000`
- `6000`
- `7000`
- `8000`
- `9000`
- `10000`
- `12000`
- `14000`
- `16000`
- `18000`
- `20000`
- `22000`
- `24000`
- `26000`

The real local runtime fixture generated from those offsets covered 24 unique
speakers. It produced 1777 total code steps, a minimum of 16 code steps, a
maximum of 296 code steps, and a median of 58 code steps. The bucket plan
assigned samples across buckets:

- `16`
- `24`
- `32`
- `40`
- `48`
- `56`
- `64`
- `80`
- `88`
- `96`
- `104`
- `112`
- `120`
- `176`
- `296`

Only bucket 40 was rerun in this pass because it already had a checked fp16
Core ML package available after artifact cleanup. Bucket 40 had four calibration
samples: 37, 39, 33, and 35 code steps, padded to 40 with `-1` metadata.

The full group-size matrix was attempted first, but the group-size-1 candidate
hit a Core ML/BNNS cache copy failure with no disk space available in the local
Core ML cache path. Old generated `.mlpackage` artifacts and the local e5rt
bundle cache were cleared, preserving the bucket-40 fp16 package. The narrowed
group-size-16 run then succeeded through the live-service headroom wrapper.

Bucket 40 group-size-16 W8A8 results with the diverse four-sample calibration:

- package size: `114801996` bytes
- whole-output max absolute diff versus fp16 Core ML: `0.263427734375`
- whole-output mean absolute diff versus fp16 Core ML:
  `0.012348680756986141`
- valid-region max absolute diff on `730_358_000003_000002`:
  `0.263427734375`
- valid-region mean absolute diff on `730_358_000003_000002`:
  `0.012741940096020699`
- padded-tail mean absolute diff on the same sample:
  `0.007498471066355705`
- valid-region alert windows: 8 of 12
- top mean-diff window: 1.5-1.75 seconds

Interpretation:

- The broader calibration input set helped the whole padded output slightly and
  reduced the padded-tail mean diff on the original sample.
- It did not improve the valid audible region on the original sample. The
  valid-region mean diff is slightly worse than the earlier one-sample
  representative run, and the number of alert windows stayed the same.
- This is evidence that broader input-only Core ML activation calibration is not
  enough by itself to clear decoder W8A8 drift.

Next decision pressure:

- Capture Qwen talker-generated code fixtures, because those codes may exercise
  a different decoder input distribution from LibriTTS-R speech-tokenizer
  encodes.
- Try per-op or narrower activation scopes only if the drift pattern suggests a
  specific sensitive op family.
- Start the supervised decoder-alignment lane if talker-generated codes and
  broader LibriTTS-R inputs still leave valid-region drift around the same
  magnitude.

### 2026-05-31 Talker-Code Capture, Pass 1

The talker-code fixture generator now writes the full code tensor fixture to
`.local` and can also write a compact summary report for Git. The compact report
keeps text, generation settings, code shapes, code prefixes, bucket assignment,
and generated WAV metadata while leaving full `audio_codes` arrays and WAVs in
local artifacts.

The first runtime capture used:

- model id: `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`
- resolved revision: `85e237c12c027371202489a0ec509ded67b5e4b5`
- voice: `Ryan`
- language: `English`
- seed: `20260531`
- prompts: three short English calibration prompts
- live-service protection: `run-with-live-service-headroom.sh`

The script monkeypatched `model.model.speech_tokenizer.decode` at runtime,
recorded the exact `audio_codes` argument, and then called the original decode
so the generated WAVs still came from the normal Qwen path.

Captured code lengths:

- `prompt-000`: 72 steps, bucket 72, no padding
- `prompt-001`: 67 steps, bucket 72, 5 padded steps
- `prompt-002`: 84 steps, bucket 88, 4 padded steps

Practical interpretation:

- Even short Qwen talker outputs landed in buckets 72 and 88, not bucket 40.
- This supports keeping bucketed decoder packages around the production talker
  distribution instead of judging W8A8 only from short LibriTTS-R encoded clips.
- The generated audio sample counts matched `code_steps * 1920`, so the captured
  codes and output WAV metadata agree with the 12 Hz decoder contract.

Bucket 72 fp16 conversion was rebuilt after earlier artifact cleanup:

- package size: about 218 MB
- input shape: `[1, 72, 16]`
- output shape: `[1, 138240]`
- mean absolute diff versus PyTorch wrapper: `0.000435686728451401`
- max absolute diff versus PyTorch wrapper: `0.048760250210762024`

That fp16 max diff is looser than the earlier bucket-40 fp16 package, but the
mean diff remains much smaller than the W8A8 drift being investigated.

Bucket 72 group-size-16 W8A8 using the two talker-generated bucket-72 samples:

- package size: `114813284` bytes
- whole-output max absolute diff versus bucket-72 fp16 Core ML:
  `0.29174041748046875`
- whole-output mean absolute diff versus bucket-72 fp16 Core ML:
  `0.01180611178278923`
- sample source: `talker_code_fixture`
- calibration sample count: 2

Interpretation:

- Talker-generated codes are a better production-shaped calibration source than
  LibriTTS-R re-encodes, but they did not clear the W8A8 decoder drift.
- The mean diff is slightly below the bucket-40 LibriTTS-R valid-region number,
  but it remains in the same audible-risk range.
- The next useful evidence is not timing or Instruments yet. It should be either
  an audio inspection report for bucket 72 talker samples, narrower per-op
  activation scopes, or the supervised decoder-alignment probe.

### 2026-05-31 Talker-Code Audio Inspection, Pass 1

The decoder audio inspection script now supports `--sample-source talker`, which
loads captured talker-code fixtures directly instead of going through the
LibriTTS-R calibration fixture and bucket plan. It still writes only local WAV
artifacts and a compact JSON report for Git.

The first talker audio inspection compared:

- baseline: bucket-72 fp16 Core ML decoder package
- candidate: bucket-72 group-size-16 W8A8 package calibrated with talker codes
- sample: `prompt-000`
- input code shape: `[72, 16]`
- valid output samples: `138240`
- padding: none

Numeric result:

- valid-region max absolute diff: `0.3759765625`
- valid-region mean absolute diff: `0.012348570860922337`
- valid-region RMS diff: `0.02168286219239235`
- alert windows: 15 of 24 quarter-second windows
- worst mean-diff window: 1.0-1.25 seconds, mean diff
  `0.028064705431461334`
- largest spike window: 4.0-4.25 seconds, max diff `0.3759765625`

Interpretation:

- The drift is broad for production-shaped generated codes, not only for
  LibriTTS-R re-encoded speech codes.
- The mean-diff scale is almost identical to the earlier bucket-40 LibriTTS-R
  audio inspection, even though the prompt and bucket differ.
- This strengthens the case for either narrower activation scopes or supervised
  decoder alignment before any Instruments dispatch work.

### 2026-05-31 Per-Op Activation Scope Probe, Pass 1

The quantization probe now accepts `--activation-op-types` for compute-only W8A8
runs. This keeps the integer `audio_codes` path unquantized while allowing
narrow op-family candidates inside the decoder.

All candidates below used:

- bucket: 72
- sample source: Qwen talker-code fixture
- calibration samples: `prompt-000` and `prompt-001`
- group size: 16
- baseline: bucket-72 fp16 Core ML package

Results:

| Candidate | Activation ops | Mean diff | Max diff | Package size |
| --- | --- | ---: | ---: | ---: |
| broad compute | `conv`, `linear`, `matmul`, `conv_transpose` | `0.01180611178278923` | `0.29174041748046875` | `114813284` |
| transformer-ish | `linear`, `matmul` | `0.006306670140475035` | `0.2249908447265625` | `114769327` |
| convolutional | `conv`, `conv_transpose` | `0.011072450317442417` | `0.22833251953125` | `114742359` |
| no transposed conv | `conv`, `linear`, `matmul` | `0.011485190130770206` | `0.3626708984375` | `114813284` |

Interpretation:

- The best current W8A8 scope is `linear` + `matmul`, which cuts mean absolute
  diff roughly in half versus the broad compute scope.
- Convolutional activation quantization remains near the broader drift level.
  This points at the decoder convolution/upsampling path as the fragile region
  to leave in fp16 for now.
- Excluding only `conv_transpose` did not help, so ordinary `conv` activation
  quantization is also suspect.
- The `linear` + `matmul` candidate still needs audio inspection and listening
  before it can be treated as acceptable.

Operational note:

- Repeated Core ML package compile/predict runs grew the local e5rt cache to
  about 20 GB and one candidate emitted a BNNS cache "No space left on device"
  warning even though the report saved prediction metrics. Clear the e5rt cache
  before more Core ML candidate batches.

## 2026-05-31 Linear Matmul Audio Inspection And Bucket 88 Follow-Up

The `linear` + `matmul` activation scope was carried into audio inspection and
the next talker bucket.

Bucket 72 prompt-000 audio inspection:

| Candidate | Valid mean abs diff | Valid max abs diff | Alert windows |
| --- | ---: | ---: | ---: |
| broad compute-only W8A8 | `0.012348570860922337` | `0.3759765625` | 15 / 24 |
| `linear` + `matmul` W8A8 | `0.006237064488232136` | `0.24884033203125` | 5 / 24 |

Bucket 72 prompt-001 held-out audio inspection:

| Candidate | Valid mean abs diff | Valid max abs diff | Padded-tail mean abs diff | Alert windows |
| --- | ---: | ---: | ---: | ---: |
| broad compute-only W8A8 | `0.006542564835399389` | `0.17669677734375` | `0.005281392019242048` | 3 / 22 |
| `linear` + `matmul` W8A8 | `0.00341379689052701` | `0.109619140625` | `0.0026827759575098753` | 0 / 22 |

Bucket 88 prompt-002 `linear` + `matmul` follow-up:

| Stage | Mean abs diff | Max abs diff | Notes |
| --- | ---: | ---: | --- |
| fp16 Core ML conversion vs PyTorch wrapper | `0.00041774153942242265` | `0.04213841259479523` | CPU-only verification, bucket 88 fp16 package regenerated locally |
| W8A8 quantization, full padded output | `0.004930480383336544` | `0.3194580078125` | one talker calibration sample |
| W8A8 quantization, valid output only | `0.004826558753848076` | `0.3194580078125` | 84 valid code steps, 4 padded steps |
| W8A8 audio inspection windows | `0.004826558753848076` | `0.3194580078125` | 2 alert windows out of 27 |

Artifacts:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-audio-inspection-bucket-72-talker-qwen3-linear-matmul-group-16-prompt-000-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-audio-inspection-bucket-72-talker-qwen3-group-16-prompt-001-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-audio-inspection-bucket-72-talker-qwen3-linear-matmul-group-16-prompt-001-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-bucket-88-fp16-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-quantization-bucket-88-fp16-talker-qwen3-linear-matmul-group-16-12hz.json`
- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-audio-inspection-bucket-88-talker-qwen3-linear-matmul-group-16-prompt-002-12hz.json`

Interpretation:

- `linear` + `matmul` activation quantization is no longer just the best numeric
  candidate; it also materially reduces valid-region audio drift on the
  bucket-72 talker sample.
- Bucket 88 does not show a new obvious failure mode from the longer fixed
  shape. The padded tail is noisier than the valid region, so backend evaluation
  must continue trimming to valid output before comparing or playing audio.
- The remaining max-diff spikes are still large enough that this should not move
  directly to backend integration. Next checks should widen held-out talker and
  LibriTTS-R samples for `linear` + `matmul`, then compare listening artifacts
  before Instruments dispatch profiling.

## 2026-06-01 W8A8 Linear Matmul Dispatch Trace

The xctrace profiling scripts now accept a model package, conversion report,
sample source, and talker-code sample id so they can profile bucketed W8A8
packages instead of only the original static-mask decoder fixture.

Profiled package:

- `.local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-bucket-72-fp16-w8a8-talker-qwen3-linear-matmul-group-16.mlpackage`

Profiled sample:

- `prompt-001`, 67 code steps padded to bucket 72, valid output 128,640 samples

Trace report:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-xctrace-bucket-72-w8a8-linear-matmul-prompt-001-12hz.json`

Results:

| Compute units | Mean predict time | ANE rows | MPS rows | GPU interval rows | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| `cpuOnly` | `138.2119083980797 ms` | 0 | 0 | 919 | baseline for this trace |
| `cpuAndNeuralEngine` | `106.08462500094902 ms` | 74 | 0 | 35,858 | ANE intervals recorded, model load/compile about 54.3s |
| `all` | `84.25714159820927 ms` | 44 | 48 | 6,204 | fastest measured path, ANE plus MPS/GPU rows |

Interpretation:

- W8A8 `linear` + `matmul` is not only numerically promising; it can produce
  Instruments-visible Neural Engine activity on the local M4 Pro.
- `cpuAndNeuralEngine` is faster than `cpuOnly`, and `all` is faster than both
  for this bucket/sample. That suggests Core ML is splitting useful work across
  compute devices when allowed.
- Load/compile time is still a serious backend concern. The NE-preferred load
  took about 54 seconds in this trace, and `all` took about 21.5 seconds. Any
  backend experiment must treat model residency, cache warmup, and artifact
  cleanup as first-class behavior rather than measuring only hot prediction.
- This trace does not provide a complete per-op placement map. It proves ANE
  interval activity during the benchmark process and enough speedup to justify
  deeper dispatch work after more audio/listening coverage.

## 2026-06-01 Bucket 88 W8A8 Dispatch Trace

Bucket 88 was profiled with the same W8A8 `linear` + `matmul` scope to check
whether the ANE result survives the longer padded shape.

Profiled package:

- `.local/coreml-qwen3tts/Qwen3TTSSpeechTokenizerDecoder-bucket-88-fp16-w8a8-talker-qwen3-linear-matmul-group-16.mlpackage`

Profiled sample:

- `prompt-002`, 84 code steps padded to bucket 88, valid output 161,280 samples

Trace report:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-decoder-coreml-xctrace-bucket-88-w8a8-linear-matmul-prompt-002-12hz.json`

Results:

| Compute units | Mean predict time | ANE rows | MPS rows | GPU interval rows | Load/compile |
| --- | ---: | ---: | ---: | ---: | ---: |
| `cpuOnly` | `178.79936680110404 ms` | 0 | 0 | 11,034 | `1.75 s` |
| `cpuAndNeuralEngine` | `134.62576680176426 ms` | 78 | 0 | 85,127 | `84.39 s` |
| `all` | `110.43449199933093 ms` | 80 | 84 | 16,450 | `51.58 s` |

Interpretation:

- The longer bucket confirms the bucket-72 dispatch finding. W8A8
  `linear` + `matmul` records Neural Engine activity under NE-capable compute
  settings and improves hot prediction time versus CPU-only.
- `all` remains the fastest measured setting and uses both ANE and MPS/GPU
  surfaces, so the first backend experiment should prefer `.all` after parity
  and audio checks.
- Load/compile time gets worse with bucket 88. A practical backend must keep
  one or more decoder buckets resident, avoid cold loads in request handling,
  and expose explicit unload/reload behavior consistent with the existing
  resident-model control surface.

## Decoder Residency Prototype Shape

The next local implementation target should be a private decoder runner, not a
public backend case yet.

Near-term behavior:

- Load bucketed Core ML decoder packages once per selected compute-unit policy.
- Start with `.all` for W8A8 `linear` + `matmul` packages because current traces
  show the best hot prediction time there.
- Keep loaded `MLModel` instances resident across requests until explicit
  unload, memory pressure, or maintenance control asks them to leave memory.
- Accept captured or generated `audio_codes`, choose the smallest fixed bucket
  that can hold the code-step count, pad remaining steps with `-1`, and record
  valid output sample count.
- Run prediction, trim to valid output samples before playback/evaluation, and
  report timing split into model-load, warm prediction, measured prediction,
  padding, and trimming.
- Keep this runner under maintainer/probe tooling first. Do not expose a public
  `SpeechBackend` until the talker graph boundary and decoder listening quality
  are both clearer.

Why this matters:

- SpeakSwiftly's resident-model control is a real advantage over cold Core ML
  demos: the current W8A8 decoder has promising hot latency, but poor cold
  compile/load behavior.
- A private runner lets us test residency, bucket selection, valid-region
  trimming, and dispatch policy before taking on the harder Qwen talker graph.

First prototype result:

- Added `SpeakSwiftlyProbeTool coreml-qwen-decoder` as a private maintainer
  command. It accepts a bucketed Core ML decoder package, a talker-code fixture,
  a sample id, compute units, warmup/measured run counts, and an optional report
  path.
- The command compiles raw `.mlpackage` inputs when needed, loads one `MLModel`
  with the requested `MLComputeUnits`, pads captured Qwen talker codes to the
  fixture bucket with `-1`, runs repeated predictions against the resident model,
  trims valid output samples separately from the padded tail, and writes a compact
  JSON report.
- The first pinned report is
  `coreml-qwen3tts/speech-tokenizer-decoder-coreml-resident-probe-bucket-72-w8a8-linear-matmul-prompt-001-12hz.json`.
  It used the bucket-72 W8A8 `linear` + `matmul` package, Qwen talker
  `prompt-001`, and `.all` compute units.
- The sample had 67 valid code steps, padded to `[1, 72, 16]`, with 128,640
  valid output samples and a 9,600-sample padded tail.
- The first Swift run compiled the raw package in about `128 ms`, loaded the
  model in about `40.4 s`, warmed once in about `1.58 s`, and measured two hot
  resident predictions at about `83.4 ms`.
- A second pinned report is
  `coreml-qwen3tts/speech-tokenizer-decoder-coreml-resident-probe-bucket-88-w8a8-linear-matmul-prompt-002-12hz.json`.
  It used the bucket-88 W8A8 `linear` + `matmul` package, Qwen talker
  `prompt-002`, and `.all` compute units.
- The bucket-88 sample had 84 valid code steps, padded to `[1, 88, 16]`, with
  161,280 valid output samples and a 7,680-sample padded tail.
- The bucket-88 Swift run compiled the raw package in about `118 ms`, loaded the
  model in about `29.8 s`, warmed once in about `1.59 s`, and measured two hot
  resident predictions at about `124.6 ms`.
- The command now also has a resident bucket-catalog mode through repeatable
  `--bucket-model BUCKET=PATH` arguments and repeatable in-process catalog
  passes through `--catalog-passes COUNT`. The current pinned catalog report is
  `coreml-qwen3tts/speech-tokenizer-decoder-coreml-resident-catalog-buckets-72-88-w8a8-linear-matmul-prompts-001-002-12hz.json`.
  It loaded bucket 72 and bucket 88 once in one process, then routed
  `prompt-001` to bucket 72 and `prompt-002` to bucket 88 across two catalog
  passes.
- In the two-pass catalog run, bucket 72 compiled in about `144 ms` and loaded
  in about `36.3 s`, while bucket 88 compiled in about `114 ms` and loaded in
  about `31.6 s`. First pass warmups were about `1.74 s` for prompt-001 and
  `1.62 s` for prompt-002, while second pass warmups fell to about `100 ms` and
  `109 ms`. Pass-two measured means were about `84.6 ms` for prompt-001 and
  about `109.2 ms` for prompt-002.
- The refreshed report records process RSS snapshots around the resident-catalog
  work: about `22 MiB` at start, `235 MiB` after bucket 72 loads, `220 MiB`
  after bucket 88 loads, `513 MiB` after bucket 72 first predicts, and `616 MiB`
  after bucket 88 first predicts. The second pass stayed essentially flat around
  `616 MiB`, which supports treating first prediction per bucket as an explicit
  warm-residency step.
- The matching fp16 resident catalog is
  `coreml-qwen3tts/speech-tokenizer-decoder-coreml-resident-catalog-buckets-72-88-fp16-prompts-001-002-12hz.json`.
  It uses the same samples, compute policy, and two-pass shape. Bucket 72 loaded
  in about `15.9 s` and bucket 88 loaded in about `28.8 s`; first-use warmups
  were about `455 ms` and `240 ms`, while pass-two measured means were about
  `83.4 ms` and `111.0 ms`.
- The compact closeout comparison is
  `coreml-qwen3tts/decoder-closeout-fp16-vs-w8a8-resident-catalog-12hz.json`.
  W8A8 `linear` + `matmul` cuts each bucket package from about `229 MB` to about
  `115 MB`, but does not materially improve pass-two hot timing in the Swift
  resident catalog. Its first-use warmups are larger than fp16, so any
  backend-shaped use must explicitly warm each resident bucket before serving
  user-facing audio.
- Decoder closeout status: W8A8 `linear` + `matmul` remains the only current
  decoder W8A8 candidate; convolution and upsampling activations stay fp16; no
  public Core ML `SpeechBackend` should be added until the Qwen talker graph
  boundary is understood. MacBook Pro speaker listening at roughly 60% volume
  found W8A8 acceptable for continued performance work, but not fp16-equal:
  bucket 72 was very close with a tiny fp16 fullness advantage, while bucket 88
  sounded slightly muffled.
- The listening manifest is
  `coreml-qwen3tts/decoder-closeout-listening-manifest-12hz.json`. It verifies
  the existing local valid-region WAV pairs for bucket 72 `prompt-001` and
  bucket 88 `prompt-002`, and records the MacBook Pro speaker listening pass as
  acceptable for continued exploration with optional headphones follow-up.
- This confirms the backend-relevant shape is feasible at the probe level:
  declare bucket packages, load them once, route by code length, trim valid
  output, and keep public runtime surfaces unchanged while gathering evidence.
- Core ML attempted to create an execution cache under the macOS user cache
  directory for `SpeakSwiftlyProbeTool`; the first sandboxed run failed at that
  cache step, while the live-service wrapper still reloaded resident models
  afterward. The successful run used the same wrapper with permissions that let
  Core ML create its cache.

### 2026-06-04 External Core ML Artifact Inventory, Pass 1

Added a metadata-only Hugging Face inventory probe:

- `scripts/repo-maintenance/coreml-qwen3tts/inspect-coreml-qwen3tts-repos.py`

Added a checked-in inventory fixture:

- `docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/external-coreml-qwen3tts-repo-inventory-2026-06-04.json`

Added SwiftPM tests for the fixture:

- `Tests/SpeakSwiftlyTests/Generation/CoreMLQwen/Qwen3TTSExternalCoreMLRepoInventoryTests.swift`

The probe compares the older FluidInference Core ML artifact with the newer
`aufklarer/Qwen3-TTS-CoreML` repo without downloading large model bundles. It
uses Hugging Face model metadata plus small `config.json` downloads only.

Inventory findings:

- FluidInference resolved revision:
  `7bb6c4e5c425ddecc0aa2339f125398623d2da36`.
- `aufklarer/Qwen3-TTS-CoreML` resolved revision:
  `66ca03b95a684d45e020b1d2d5c3ab34a48356f9`.
- Both repos publish the same six compiled model names:
  `TextProjector`, `CodeEmbedder`, `MultiCodeEmbedder`, `CodeDecoder`,
  `MultiCodeDecoder`, and `SpeechDecoder`.
- FluidInference still has the better conversion-inspection surface because it
  publishes `.mlpackage` source packages and `cp_embeddings.npy`.
- `aufklarer/Qwen3-TTS-CoreML` has the stronger next-probe signal because it
  includes `vocab.json` and `merges.txt`, declares `W8A16` in config, names the
  `Qwen/Qwen3-TTS-12Hz-0.6B-Base` source model, and points at the open
  `speech-swift` `Qwen3TTSCoreML` module as a reference Swift integration.
- FluidInference's `config.json` is present on Hugging Face but does not parse
  as JSON through this probe. The script treats optional invalid config as
  absent instead of failing the whole inventory.

Decision:

- Add `aufklarer/Qwen3-TTS-CoreML` to the evaluation matrix as a metadata probe
  only.
- Do not add a public `SpeechBackend`, do not add `speech-swift` as a package
  dependency, and do not download the full Core ML repo in default validation.
- The next concrete comparison slice should live at the talker/code-generator
  boundary: download the minimum compiled subset needed to compare prompt
  wrapping, token IDs, first codec-token generation, codebook order, and stage
  timing against SpeakSwiftly's own Qwen fixture path.
- Audible-quality comparison should wait until that talker path can produce a
  matched waveform fixture.

### 2026-06-23 Core AI Runtime Route Added

Apple's current machine-learning guidance frames Core AI as the preferred
on-device generative-model stack and positions Core ML more as the traditional
model-integration path. The branch should therefore evaluate Core AI as a real
runtime route, not merely continue assuming Core ML Tools is the only
Apple-native conversion path.

`coreai-torch` is the first concrete Core AI route to test because it starts
from PyTorch `ExportedProgram`, supports composite op preservation for model
building blocks such as attention, RoPE, RMSNorm, and SDPA, and has extension
points for custom lowerings and inline Metal kernels. That makes it most
relevant to the Qwen talker/code-predictor boundary, not to replacing the
already-useful decoder residency evidence.

The next concrete slice is a read-first decision memo plus a tiny
talker/code-predictor export probe. Success means the probe produces inspectable
Core AI IR with useful preserved boundaries and a clear path to parity checks.
Failure means the route should be compared against ExecuTorch MLX and
ExecuTorch Core ML before any larger dependency adoption.

## Open Decisions

- Should this branch continue as "Core ML" research, broaden to an
  Apple-native Qwen runtime branch, or split Core AI into a dedicated follow-up
  branch after the first `coreai-torch` export feasibility probe?
- What is the minimum `coreai-torch` success signal: successful export only,
  preserved composite op boundaries, first-token parity, or a timed Core AI
  runtime pass?
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
- aufklarer Qwen3-TTS Core ML model card:
  https://huggingface.co/aufklarer/Qwen3-TTS-CoreML
- speech-swift repository:
  https://github.com/soniqo/speech-swift
- Apple AI and Machine Learning overview:
  https://developer.apple.com/machine-learning/
- Core AI documentation:
  https://developer.apple.com/documentation/coreai
- coreai-torch documentation:
  https://apple.github.io/coreai-torch/main/
- coreai-torch repository:
  https://github.com/apple/coreai-torch
- coreai-optimization documentation:
  https://apple.github.io/coreai-optimization/
- coreai-optimization repository:
  https://github.com/apple/coreai-optimization
- coreai-torch conversion workflows:
  https://apple.github.io/coreai-torch/main/guides/conversion-workflows.html
- coreai-torch externalization guide:
  https://apple.github.io/coreai-torch/main/guides/externalization.html
- ExecuTorch iOS and macOS integration documentation:
  https://docs.pytorch.org/executorch/stable/using-executorch-ios.html
- ExecuTorch MLX delegate:
  https://github.com/pytorch/executorch/blob/main/backends/mlx/README.md
- ExecuTorch Core ML delegate:
  https://github.com/pytorch/executorch/blob/main/backends/apple/coreml/README.md
- Core ML Tools conversion guide:
  https://apple.github.io/coremltools/docs-guides/source/convert-to-ml-program.html
- Core ML Tools typed execution guide:
  https://apple.github.io/coremltools/docs-guides/source/typed-execution.html
- Core ML Tools optimization overview:
  https://apple.github.io/coremltools/docs-guides/source/opt-overview.html
- Core ML Tools quantization overview:
  https://apple.github.io/coremltools/docs-guides/source/opt-quantization-overview.html
- Core ML Tools quantization algorithms:
  https://apple.github.io/coremltools/docs-guides/source/opt-quantization-algos.html
- Core ML Tools Core ML quantization API reference:
  https://apple.github.io/coremltools/source/coremltools.optimize.coreml.quantization.html
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
- mps-flash-attention package:
  https://github.com/mpsops/mps-flash-attention
- metal-flash-sdpa package:
  https://github.com/alliprice/metal-flash-sdpa
- mps-flash-attn package notes:
  https://pypi.org/project/mps-flash-attn/
- Apple `MTLDevice.supportsFamily(...)` documentation:
  https://developer.apple.com/documentation/metal/mtldevice/3143473-supportsfamily
- Apple `MTLDevice.makeLibrary(source:options:)` documentation:
  https://developer.apple.com/documentation/metal/mtldevice/makelibrary%28source%3Aoptions%3A%29
- Apple `MTLLibrary` documentation:
  https://developer.apple.com/documentation/metal/mtllibrary/
- Apple Metal tools guide:
  https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Dev-Technique/Dev-Technique.html
