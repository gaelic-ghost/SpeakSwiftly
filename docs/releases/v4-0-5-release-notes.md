# v4.0.5 Release Notes

## What changed

- hardened `SpeakSwiftlyTesting volume-probe` so it reports explicit analyzed
  span metadata, fixed-duration windows, quarter-bucket summaries, averaged
  head/tail RMS, tail/head ratio, slope, and last-window average RMS
- renamed the old endpoint-style drop metric in the probe output to
  `endpoint_rms_delta_pct`, making clear that it compares only the first and
  last windows
- added versioned JSON artifacts for `volume-probe` and `compare-volume` under
  `.local/volume-probes/`, with unique per-run filenames for fast repeated
  probes
- made `compare-volume` refuse mismatched sample rates or sample counts by
  default, with `--matched-duration trim-to-shorter` as the explicit opt-in
  comparison mode
- made direct Qwen comparison WAV filenames unique so overlapping runs cannot
  overwrite another run before trimmed metrics are recomputed
- moved reusable probe math into `SpeakSwiftlyTestingSupport` and added cheap
  synthetic tests for window slicing, tail/head summaries, matched-span
  trimming, and invalid analysis inputs
- documented the volume-probe measurement contract in README, CONTRIBUTING, and
  `docs/maintainers/volume-probe-instrument-contract-2026-04-24.md`

## Breaking changes

- none for the public `SpeakSwiftly` runtime library or JSONL worker protocol

## Migration or upgrade notes

- `compare-volume` may now fail where it previously printed a comparison table
  for mismatched outputs; this is intentional and prevents invalid
  streamed-vs-direct conclusions
- use `--matched-duration trim-to-shorter` only when trimming both sides to the
  same prefix span is acceptable for the investigation
- downstream maintainers should treat `endpoint_rms_delta_pct` as an endpoint
  metric, not as a whole-run degradation score

## Verification performed

```bash
swift build
```

```bash
swift test --filter VolumeProbeAnalysisTests
```

```bash
swift test
```

```bash
swiftformat --lint --config .swiftformat .
```

```bash
swiftlint lint --config .swiftlint.yml
```

```bash
git diff --check
```

```bash
sh scripts/repo-maintenance/validate-all.sh
```
