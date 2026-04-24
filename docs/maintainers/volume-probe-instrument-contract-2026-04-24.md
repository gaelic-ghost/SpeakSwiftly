# Volume Probe Instrument Contract

Date: 2026-04-24

## Purpose

The volume probes are measurement tools, not proof generators. Their first job is
to say exactly what audio span was inspected and how each number was derived, so
Qwen long-form investigations do not rely on comforting-looking tables that
quietly compare different things.

## Tool Boundaries

`volume-probe` profiles one retained generated audio file. It is the right tool
for asking whether one output trends quieter, louder, peakier, or flatter across
time. It does not compare model paths.

`compare-volume` compares two audio outputs only after it proves the analyzed
spans are compatible. By default it refuses mismatched sample counts. The
explicit `--matched-duration trim-to-shorter` mode trims both outputs to the
shorter sample count and records both the full analyses and the compared
analyses in the JSON artifact.

The analysis support code rejects invalid measurement inputs before it slices
audio. `sampleRate`, `windowSeconds`, and any requested trim count must describe
a real nonnegative span; otherwise the tool should fail with a descriptive
operator-facing error instead of writing an artifact with meaningless numbers.

Generated-code capture, replay, and code-stream comparison remain separate from
volume probing. Those tools answer whether Qwen generated different acoustic
codes or decode inputs before waveform-level loudness analysis begins.

## Measurement Terms

- `sample_count`: the number of mono samples loaded from the WAV file before any
  comparison trimming.
- `analyzed_sample_count`: the number of mono samples actually included in the
  reported windows and summary.
- `analyzed_sample_start`: the start of the analyzed span. It is currently `0`
  because trimming keeps the prefix of each output.
- `duration_seconds`: the full WAV sample count divided by the sample rate.
- `window`: a fixed sample-count slice, calculated as
  `sampleRate * windowSeconds`, rounded to the nearest integer. The final window
  can be shorter when the audio does not divide evenly.
- `rms`: root mean square amplitude for one window.
- `peak`: highest absolute sample value in one window.
- `endpoint_rms_delta_pct`: the percent change from the first window RMS to the
  last window RMS. This is deliberately named as an endpoint metric; it is not a
  whole-run degradation score.
- `slope_per_window`: the linear least-squares slope across all window RMS
  values.
- `head_rms` and `tail_rms`: average RMS over the first and last quarter bucket
  of windows.
- `tail_head_ratio`: `tail_rms / head_rms`.
- `last_N_window_avg_rms`: average RMS across the final N windows, currently up
  to the last three windows.

## Artifact Contract

Both probe commands write versioned JSON under `.local/volume-probes/` and also
refresh a `*-latest.json` pointer.

`volume-probe` artifacts include:

- `schemaVersion`
- `toolName`
- `sourceSurface`
- `profileName`
- optional `profileRoot`
- text size and stable text fingerprint
- generated file path
- full analysis, including sample metadata, analyzed span, windows, and summary

`compare-volume` artifacts include:

- the same command context fields
- `matchedDurationMode`
- `comparisonSampleCount`
- full and compared sample metadata for both sides
- streamed and direct generated file paths
- full streamed and direct analyses
- compared streamed and direct analyses

The JSON is the durable source for future comparisons. Console output is a
human-readable summary of the same measurement contract.

## Testing Policy

Measurement math should be covered with cheap synthetic sample tests before
running real Qwen or MLX-backed probes. Those tests should prove window slicing,
short final windows, head/tail averaging, endpoint naming, last-window averages,
and matched-span trimming behavior without warming a model.

Real-model experiments remain opt-in. Do not use `compare-volume` conclusions
unless the artifact proves the compared spans are matched or explicitly trimmed.
