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
