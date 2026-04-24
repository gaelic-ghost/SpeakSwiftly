# v4.0.5 Release Prep

Date: 2026-04-24

This note captures the intended scope and validation story for the `v4.0.5`
release.

## Intended Scope

The release should be framed as:

- a measurement-contract hardening pass for the package-local
  `SpeakSwiftlyTesting` volume probes
- a strict `compare-volume` safety fix that prevents streamed-vs-direct
  conclusions unless analyzed spans are actually comparable
- a documentation cleanup that makes the probe semantics visible in README,
  CONTRIBUTING, and maintainer notes

Included work on the current branch:

- move reusable volume-analysis math into the `SpeakSwiftlyTestingSupport`
  target so it can be covered by cheap synthetic tests
- expand `volume-probe` summaries with duration, sample count, analyzed span,
  fixed-duration window count, quarter buckets, averaged head and tail RMS,
  tail/head ratio, last-window average RMS, and an explicit
  `endpoint_rms_delta_pct`
- write versioned `volume-probe` and `compare-volume` JSON artifacts under
  `.local/volume-probes/` with unique per-run filenames
- make `compare-volume` refuse mismatched sample rates or sample counts by
  default
- add `--matched-duration trim-to-shorter` as the explicit opt-in path for
  comparing the same prefix span from both outputs
- write direct Qwen comparison WAVs to unique temporary filenames so overlapping
  probe runs cannot contaminate trimmed metrics
- reject invalid analysis inputs before writing artifacts with meaningless
  values
- document the probe contract in
  `docs/maintainers/volume-probe-instrument-contract-2026-04-24.md`
- update README, CONTRIBUTING, and the backend-benchmark follow-up note so they
  no longer imply `compare-volume` is trustworthy without matched spans

Not included:

- a Qwen generation-default change
- a `mlx-audio-swift` dependency update
- real-model Qwen decay conclusions from the new probes
- tagging or publishing the release before the branch lands on `main`

## SemVer Framing

- release this as `v4.0.5`
- this is a patch release because it hardens package-local maintainer tooling,
  JSON probe artifacts, tests, and documentation without changing the public
  `SpeakSwiftly` runtime library or worker protocol
- the only CLI behavior change is that `compare-volume` now refuses unsafe
  comparisons unless trimming is explicitly requested

## Validation Performed

Baseline package validation:

```bash
swift build
```

```bash
swift test
```

Focused probe coverage:

```bash
swift test --filter VolumeProbeAnalysisTests
```

Formatting and linting:

```bash
swiftformat --lint --config .swiftformat .
```

```bash
swiftlint lint --config .swiftlint.yml
```

Diff hygiene:

```bash
git diff --check
```

Commit-hook repo-maintenance validation:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

## Release Checklist

- call out that `compare-volume` now refuses unmatched spans by default
- call out that `endpoint_rms_delta_pct` is an endpoint metric, not a whole-run
  degradation score
- include the new maintainer contract doc in the release notes
- keep any real-model Qwen decay investigation as a follow-up after the release
  lands
