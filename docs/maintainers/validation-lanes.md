# SpeakSwiftly Validation Lanes

This note exists so maintainers stop rediscovering the same validation snags.

## What To Use First

For ordinary package work, start with the fast SwiftPM lane:

```bash
swift build
swift test
```

That is still the right default for quick compile, unit-coverage, and ordinary
MLX-backed package-test feedback in this repository.

The current package test lane works with MLX because:

- `SpeakSwiftlyTests` bundles `default.metallib` as a test resource
- the shared test bootstrap copies that metallib into the exact direct MLX
  probe paths under `.build/...` before the first MLX-backed test model is
  created

If a plain `swift test` failure now mentions `default.metallib`, treat that as
a real regression in the test bootstrap or test-product layout, not as a known
reason to jump straight to `xcodebuild`.

## Historical SwiftPM Snag

The current `mlx-audio-swift` `0.79.0` fork release preserves the ordinary
SwiftPM lane for this repository. The notes below are retained because earlier
pins could fail under plain SwiftPM with parser errors in `EnglishG2P.swift`,
and we may need the same fallback again if a future toolchain regression
reintroduces that behavior.

Typical symptom:

```text
.../EnglishG2P.swift: error: new Swift parser generated errors for code that C++ parser accepted
```

If that failure returns:

1. Stop retrying the same `swift build` or `swift test` command.
2. Switch to the Xcode-backed package workspace lane.
3. Keep validation targeted so the signal stays readable.

## Xcode-Backed Fallback Lane

Use this fallback for:

- release hardening
- standalone-worker validation
- Marvis overlap investigation
- any validation pass blocked by the SwiftPM parser failure

Build once:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/derived-data/validation \
  -clonedSourcePackagesDirPath .local/source-packages
```

Then run one targeted test lane at a time with `test-without-building`.

Example targeted package test rerun:

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/derived-data/validation/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests'
```

For GitHub Actions, keep the manifest sanity check as:

```bash
swift package dump-package
```

GitHub Actions currently keeps build-and-test coverage on the Xcode-backed
package lane even though local ordinary package work starts with SwiftPM. The
current macOS CI target set is:

- `SpeakSwiftlyTests/WorkerRuntimePlaybackTests`
- `SpeakSwiftlyTests/LibrarySurfaceTests`
- `SpeakSwiftlyTests/ModelClientsTests`

## iOS Compile-And-Smoke Lane

The iOS lane is intentionally smaller than the macOS package lane. Its job is
to prove that:

- the package resolves for iOS
- the shared library and playback-environment code compile for iOS Simulator
- a small library-first smoke slice still runs under Simulator

Build once:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -derivedDataPath .local/derived-data/ios-smoke \
  -clonedSourcePackagesDirPath .local/source-packages
```

Then run the current smoke slice:

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/derived-data/ios-smoke/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests' \
  -only-testing:'SpeakSwiftlyTests/SupportResourcesTests' \
  -only-testing:'SpeakSwiftlyTests/ProfileStoreTests'
```

Keep this lane library-first. The worker-driven e2e harness is macOS-only and
should stay out of the iOS simulator smoke path unless we deliberately create an
app-hosted iOS e2e story later.

## E2E and Real-Model Notes

Now that the plain SwiftPM parser failure in `EnglishG2P.swift` has been fixed
in the current `mlx-audio-swift` fork pin, prefer the repo-maintenance shell
wrappers instead of the older Xcode `.xctestrun` dance for ordinary E2E work:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite quick
sh scripts/repo-maintenance/run-e2e.sh --suite qwen
sh scripts/repo-maintenance/run-e2e.sh --suite qwen-longform
sh scripts/repo-maintenance/run-e2e-full.sh
```

The wrappers intentionally run one top-level worker-backed suite per process so
Xcode or Swift Testing cannot freeze Gale's machine by launching multiple model
loading suites at once.

Each wrapper invocation also runs the live-service resident-model unload
preflight before `swift test`. The preflight posts to the
LaunchAgent-backed `SpeakSwiftlyServer` `/runtime/models/unload` endpoint when
that service is reachable, leaving the service installed and only freeing
resident model memory for the package-owned E2E worker. The wrapper reloads the
live service resident models after the test invocation completes. The full-lane
wrapper owns one outer unload/reload pair around the full release-safe sequence,
so child suite invocations do not repeatedly reload the live service between
suites. Set `SPEAKSWIFTLY_LIVE_SERVICE_BASE_URL` for a non-default live-service
URL, set `SPEAKSWIFTLY_LIVE_SERVICE_UNLOAD_TIMEOUT_SECONDS` when active
generation or playback can keep `unload_models` waiting longer than the default
preflight window, or set `SPEAKSWIFTLY_SKIP_LIVE_SERVICE_UNLOAD=1` and
`SPEAKSWIFTLY_SKIP_LIVE_SERVICE_RELOAD=1` for a deliberate skip.

Plain `swift test` remains the execution engine under those wrappers. Keep the
Xcode-backed lane as a fallback only if a future toolchain regression breaks the
ordinary SwiftPM path again.

For the default full macOS e2e slice, prefer the repo-maintenance wrappers:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite quick
sh scripts/repo-maintenance/run-e2e-full.sh
```

Keep the older Xcode lane below as a fallback only if the SwiftPM parser
regression returns. In that fallback, build once, patch the generated
`.xctestrun` file to inject `SPEAKSWIFTLY_E2E=1`, then run the current
top-level suite set explicitly:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/derived-data/e2e-full \
  -clonedSourcePackagesDirPath .local/source-packages
```

```bash
uv run python - <<'PY'
from pathlib import Path
import plistlib

xctestrun_path = next(
    Path(".local/derived-data/e2e-full/Build/Products").glob("*.xctestrun")
)

with xctestrun_path.open("rb") as f:
    data = plistlib.load(f)

for config in data.get("TestConfigurations", []):
    for target in config.get("TestTargets", []):
        env = target.setdefault("EnvironmentVariables", {})
        env["SPEAKSWIFTLY_E2E"] = "1"

with xctestrun_path.open("wb") as f:
    plistlib.dump(data, f)
PY
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/derived-data/e2e-full/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/GeneratedFileE2ETests' \
  -only-testing:'SpeakSwiftlyTests/GeneratedBatchE2ETests' \
  -only-testing:'SpeakSwiftlyTests/ChatterboxE2ETests' \
  -only-testing:'SpeakSwiftlyTests/QueueControlE2ETests' \
  -only-testing:'SpeakSwiftlyTests/MarvisE2ETests' \
  -only-testing:'SpeakSwiftlyTests/QwenE2ETests'
```

That lane excludes the opt-in `DeepTraceE2ETests` and `QwenBenchmarkE2ETests`
families unless you deliberately inject their extra environment flags too.

For the broader backend-comparison benchmark design that should eventually
replace the Qwen-only benchmark as the main package benchmark lane, see:

- [backend-benchmarking-plan-2026-04-20.md](backend-benchmarking-plan-2026-04-20.md)

The package now also has an opt-in backend-wide benchmark suite behind:

- `SPEAKSWIFTLY_E2E=1`
- `SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E=1`
- optional `SPEAKSWIFTLY_BACKEND_BENCHMARK_ITERATIONS=<n>`
- optional `SPEAKSWIFTLY_BACKEND_BENCHMARK_AUDIBLE=1`

Prefer the repo-maintenance wrapper instead of exporting those by hand:

```bash
sh scripts/repo-maintenance/run-benchmark.sh
sh scripts/repo-maintenance/run-benchmark.sh --audible --iterations 3
sh scripts/repo-maintenance/run-benchmark.sh --qwen --iterations 5
```

For the Marvis-specific resident-policy comparison lane, run the benchmark test
directly so the filter stays narrow:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E=1 SPEAKSWIFTLY_BACKEND_BENCHMARK_ITERATIONS=1 swift test --filter 'BackendBenchmarkE2ETests/compare marvis resident policies with three queued voice switches'
```

That lane compares `dual_resident_serialized` against
`single_resident_dynamic` with a three-request voice order that goes
`femme` -> `masc` -> `femme` again.

For Marvis profiling, throughput investigation, and trace work, prefer the dedicated runbook:

- [marvis-overlap-profiling-runbook-2026-04-16.md](marvis-overlap-profiling-runbook-2026-04-16.md)

## Practical Rules

- Never run multiple heavy validation commands at the same time.
- Never run multiple SwiftPM or Xcode build or test processes concurrently.
- Prefer one clean targeted rerun over broad shotgun retries.
- If a failure clearly matches the older vendored parser snag, document that fallback-lane choice in your notes instead of treating it as an unexplained flake.
