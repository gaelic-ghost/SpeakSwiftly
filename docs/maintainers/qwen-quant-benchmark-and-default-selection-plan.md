# Qwen Quant Benchmark And Default Selection Plan

## Summary

This plan defines the next benchmark branch after the v11 Qwen-only output
modularization prerelease. The goal is to measure every supported Qwen3 TTS
backend variant on Gale's MacBook Pro and Mac mini, then use the evidence to
decide which variants stay supported and how SpeakSwiftly should choose a
hardware-sensitive default backend.

This is a fresh implementation plan. Older benchmark and Qwen volume-decay
branches are evidence sources only; do not merge them wholesale into v11.

## Devices

- MacBook Pro: M4 Pro, 24GB RAM.
- Mac mini: M4, 16GB RAM.

Both machines should run the same benchmark command shape from a clean checkout,
with the same package revision, same text fixtures, same voice profile inputs,
same prepared-conditioning state policy, and the same output-artifact layout.

## Backend Matrix

Benchmark the current public Qwen3 backend variants before pruning:

- `qwen3_smol`
- `qwen3_smol_4bit`
- `qwen3_smol_5bit`
- `qwen3_smol_6bit`
- `qwen3_smol_8bit`
- `qwen3_smol_bf16`
- `qwen3_big`
- `qwen3_big_4bit`
- `qwen3_big_5bit`
- `qwen3_big_6bit`
- `qwen3_big_8bit`
- `qwen3_big_bf16`

If a variant cannot load or complete on a device, record that as a result
instead of silently removing it from the run.

## Metrics

Capture at least:

- Device identity: model name, chip family, CPU core count, GPU core count when
  available, total memory, OS version, Xcode version, Swift version.
- Backend identity: public `SpeechBackend`, resolved model repository, quant
  family, model size family, and generation policy.
- Cold-load timing: process start to resident-ready, model load duration, first
  profile conditioning load or preparation duration.
- Live generation timing: request enqueue time, generation start time, first
  generated chunk time, first playable audio time, final chunk time, playback
  completion time.
- Chunk cadence: per-chunk generated sample count, generated duration, wall-clock
  interval between chunks, and cumulative realtime ratio.
- Memory pressure: baseline resident memory, peak resident memory, memory after
  unload, and any OS memory-pressure signals available from the benchmark host.
- Quality signals: generated-audio warning counts, clipping ratio, near-silence
  ratio, repeated-window similarity, boundary jumps, non-finite sample counts,
  and any human audible notes recorded after playback or generated-file review.
- Cache effects: first run with missing prepared conditioning, second run with
  prepared conditioning present, and rerun after resident model reload.

## Benchmark Slices

1. Add a benchmark command or script that runs one backend on one fixture and
   writes machine-readable JSONL or JSON output.
2. Add a matrix runner that executes the command for every backend variant and
   keeps per-device output under an ignored local benchmark artifact directory.
3. Add signposts or structured timing events around model load, conditioning,
   generation start, first chunk, final chunk, and playback completion.
4. Add a summarizer that compares variants by device and emits a concise Markdown
   report for review.
5. Run the matrix on the MacBook Pro and Mac mini, keeping raw artifacts local
   until the summary has been checked for machine-local paths and accidental
   private data.
6. Decide the retained backend set and default-selection rules from evidence,
   then land code changes separately from raw benchmark data.

## Initial Local Evidence

The first full local matrix ran after `v11.0.0-alpha.1` on:

- MacBook Pro: M4 Pro, 24GB RAM.
- Mac mini: M4, 16GB RAM.

Both runs completed every current Qwen3 backend variant with three recorded
scenarios and no failed or timed-out backend rows. Raw artifacts remain local
under `.local/benchmarks/qwen-quant/`.

This first pass is useful as structural evidence, not final default-selection
policy. It measured one normal local condition on each machine, using the shared
plain-prose playback fixture, prepared conditioning, default balanced text
normalization, local playback, and the current startup preroll behavior. It did
not vary macOS power mode, thermal state, battery state, unrelated CPU load,
unrelated GPU or MLX load, memory pressure, active live-service residency, or
long-form audible quality fixtures.

### Request-To-Audio Timing Snapshot

For the MacBook Pro live-playback path, `qwen3_big_8bit` and
`qwen3_smol_4bit` were closer than expected:

| Backend | Avg request to first audio | Avg first audio to playback finished | Avg total request to playback finished |
| --- | ---: | ---: | ---: |
| `qwen3_big_8bit` | 403 ms | 16.450 s | 16.853 s |
| `qwen3_smol_4bit` | 328 ms | 16.627 s | 16.955 s |

The small 4-bit path reached first audio about 75 ms sooner, but total playback
completion was effectively dominated by generated utterance duration and
playback drain. This does not prove the backends are equivalent; it only shows
that this short fixture and current playback buffering did not separate them
strongly by end-to-end latency.

### Generation-Cadence Snapshot

The non-bf16 variants generally generated near realtime in this fixture. On the
MacBook Pro, representative live-generation realtime factors were:

| Backend | Tokens/s | Generated audio | Generation time | Realtime factor | Gap warnings |
| --- | ---: | ---: | ---: | ---: | ---: |
| `qwen3_smol_4bit` | 12.83 | 17.4 s | 16.9 s | 1.03x | 0 |
| `qwen3_big_5bit` | 12.99 | 16.6 s | 16.0 s | 1.04x | 0 |
| `qwen3_big_8bit` | 12.15 | 16.3 s | 16.8 s | 0.97x | 0 |
| `qwen3_big_bf16` | 6.98 | 17.0 s | 30.4 s | 0.56x | 133 |

On the Mac mini, representative live-generation realtime factors were:

| Backend | Tokens/s | Generated audio | Generation time | Realtime factor | Gap warnings |
| --- | ---: | ---: | ---: | ---: | ---: |
| `qwen3_smol_4bit` | 13.32 | 16.3 s | 15.3 s | 1.07x | 0 |
| `qwen3_big_5bit` | 13.00 | 16.8 s | 16.1 s | 1.04x | 0 |
| `qwen3_big_8bit` | 12.12 | 17.3 s | 17.8 s | 0.97x | 0 |
| `qwen3_big_bf16` | 3.11 | 17.2 s | 69.3 s | 0.25x | 468 |

The clearest early negative signal is `bf16` for live playback defaults. It
completed, but it generated well below realtime and emitted many chunk-gap
warnings while startup preroll prevented actual rebuffer events. Treat "zero
rebuffers" in this first report as proof that playback buffering masked gaps,
not proof that generation cadence was healthy.

The most surprising positive signal is `qwen3_big_5bit`: it completed cleanly on
both machines and was competitive with adjacent big variants. Keep it in the
next benchmark round unless audible quality or load testing contradicts this
first-pass result.

## Default Selection Rules To Design

Default backend selection should be explicit and explainable:

- Prefer a known-good Qwen3 variant for the detected hardware class.
- Prefer the smaller or more quantized backend on memory-constrained machines
  when quality remains acceptable.
- Prefer a higher-quality backend only when first-audio latency, memory pressure,
  and chunk cadence remain stable on the device.
- Log the selected default backend with the detected hardware facts and the
  reason for the choice.
- Keep an explicit configuration override so operators can pin a backend.
- Fail clearly when an override names a backend unsupported by the installed
  package version.

The first implementation should not silently download or switch models during an
active request. Default selection belongs at startup or resident-model reload
boundaries.

Before implementing default selection, run a second benchmark pass that varies:

- macOS power mode and battery or AC state.
- Thermal state after sustained generation.
- Unrelated CPU load.
- Unrelated GPU or MLX load.
- Memory pressure from unrelated processes.
- Live-service residency and other SpeakSwiftly or SpeakSwiftlyServer activity.
- Longer audible fixtures that can expose volume decay, prosody drift, repeated
  output, and late-request quality failures.

## Carry-Forward From Older Branches

Review and selectively reimplement:

- Benchmark signposts around generation timing. The stale
  `BenchmarkSignposts.swift` helper is the closest thing to a direct carryover:
  reuse the `OSSignposter` shape, subsystem
  `com.gaelic-ghost.SpeakSwiftly.benchmarks`, and events such as first token,
  first audio chunk, preroll ready, playback finished, and request completed.
- A benchmark trace wrapper script, updated for the v11 Qwen-only suite layout.
- Timestamped plus `latest` JSON artifact writing under `.local/benchmarks`,
  extended with device-specific directories for MacBook and Mac mini results.
- Resource snapshots for process CPU time, resident memory, physical footprint,
  and MLX active/cache/peak memory when available.
- A two-queued-live-requests workload to measure queue wait, first-audio
  penalty, completion penalty, and playback stability under realistic local
  live-speech pressure.
- Qwen volume-decay and code-capture findings that explain why audible quality,
  prosody drift, and repeated-output metrics matter.
- Any cadence-sweep notes that help choose fixtures and quality thresholds.
- Generated-code capture, replay, and comparison ideas, but retargeted to
  `SpeakSwiftlyProbeTool`, `SpeakSwiftlyTestSupport`, and
  `QwenBenchmarkE2ETests` rather than the removed `SpeakSwiftlyTesting` target.
- Quarter- or finer-grid codebook summaries such as repeat ratio,
  distinct-token spread, head/tail Jaccard, distribution shift, and leading
  shifted codebooks.
- Matched-span volume comparison rules from the current `VolumeProbeAnalysis`
  contract.

The volume-decay branch should inform benchmark interpretation with these
findings:

- Long-form Qwen failures are a symptom cluster, not only an amplitude issue:
  loudness decay, pitch or cadence drift, glitchier delivery, and inconsistent
  presentation can appear in different mixes.
- The issue can appear in retained output, so benchmark quality checks should
  not focus only on live playback scheduling.
- The behavior is profile-, prompt-length-, and conditioning-sensitive.
- Prepared conditioning improved some benchmark timings but did not remove all
  quality risk.
- Captured-code replay suggested severe failures were not explained by a single
  bounded/helper/streaming decode split.
- Coarse generated-code statistics did not expose an obvious token-collapse
  signature, so the next benchmark should keep audio-side metrics and human
  notes alongside token/code summaries.
- The first prosody proxy was useful scaffolding but too blunt to treat as
  decisive evidence; a future estimator needs a more stable F0 contour and
  speaking-rate measure before driving hard quality decisions.

Drop or rewrite:

- Generic `BackendBenchmarkE2ETests` framing; v11 is Qwen-only and should use a
  Qwen-specific benchmark suite name such as `QwenQuantizationBenchmarkE2ETests`.
- Stale benchmark environment variable names such as
  `SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E`,
  `SPEAKSWIFTLY_BACKEND_BENCHMARK_AUDIBLE`, and
  `SPEAKSWIFTLY_BACKEND_BENCHMARK_ITERATIONS`; prefer
  `SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_E2E` and the existing Qwen benchmark
  iteration naming style.
- Multi-backend benchmark lanes that included Marvis or Chatterbox.
- References to removed benchmark docs or pre-v11 E2E paths.
- Local dependency path guidance that conflicts with the current repository
  dependency provenance rules.
- Any probe output that depends on machine-local paths or stale generated files.
- Old `Package.swift` or `Package.resolved` changes pinning a local or
  investigation-specific `mlx-audio-swift` revision.
- Cadence-sweep numeric conclusions from invalidated `compare-volume` evidence.
- Stale pre-v11 paths such as `ModelClients.swift`,
  `SpeechGeneration+Qwen.swift`, and `Sources/SpeakSwiftlyTesting`.

## Exit Criteria

- The benchmark branch can run the same Qwen3 quant matrix on both target Macs.
- Results are comparable across devices without requiring raw logs in Git.
- The supported Qwen backend matrix is reduced or justified with evidence.
- Default backend selection has a concrete device-aware rule set, tests, and
  operator-facing diagnostics.
