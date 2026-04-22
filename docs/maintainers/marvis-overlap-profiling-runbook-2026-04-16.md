# Marvis Profiling Runbook

## Why This Exists

This note captures the current maintainer workflow for profiling the Marvis
generation path on Apple silicon.

The immediate use case is:

- compare a clean Marvis baseline against the current serialized package behavior
- compare the current serialized `SpeakSwiftly` Marvis path against candidate
  resident policies or upstream-informed changes
- line Instruments captures up with the package's existing JSONL deep-trace events
- determine whether first-request rebuffering is mainly caused by CPU contention,
  GPU scheduling pressure, unified-memory pressure, or some combination of those
- preserve a repeatable profiling workflow so later maintainers do not have to
  reconstruct the Xcode-backed test path from old notes and shell history

This is not a general-purpose Xcode profiling guide. It is a package-specific
runbook for the current serialized `SpeakSwiftly` Marvis path.

## Current Ground Truth

The current Marvis resident model repo in this package is:

- `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit`

That configuration lives in
[Sources/SpeakSwiftly/Generation/ModelClients.swift](../../Sources/SpeakSwiftly/Generation/ModelClients.swift).

So the current profiling question is not "is Marvis bf16 or int8?" The package
is already using the MLX 8-bit build. The more relevant question now is whether
the remaining audible instability comes from the current `mlx-audio-swift`
generation path itself, from resident-policy differences, or from some local
playback-policy mismatch that still survives after the runtime simplification.

## Existing Trace Anchors

These are the package's existing events and state surfaces that should be used
to line Instruments captures up with runtime behavior:

- `marvis_generation_lane_reserved`
- `marvis_generation_lane_released`
- `marvis_generation_scheduler_snapshot`
- `playback_rebuffer_started`
- `playback_rebuffer_resumed`
- `playback_finished`

Those traces come from:

- [Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift)

The current retained run artifacts live under:

- `.local/e2e-runs`

## Important Workflow Constraint

For ordinary reruns of the Marvis suite, prefer the plain SwiftPM wrapper:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite marvis --playback-trace
```

For this specific Instruments-driven profiling workflow, keep using the
Xcode-backed path below so one build-for-testing pass can feed repeated,
targeted `test-without-building` capture sessions. The Xcode workflow here is
about repeatable profiling mechanics, not about the older `EnglishG2P.swift`
parser failure. The current stable profiling workflow is:

1. one `xcodebuild build-for-testing` pass
2. one `.xctestrun` environment override
3. one `xcodebuild test-without-building` run per scenario

Keep the same derived-data directory for the whole profiling session unless the
code changes.

## Machine Prep

Before each capture:

- quit browsers
- quit any normal day-to-day TTS surface
- quit chat apps or anything else doing GPU-heavy compositing
- plug the machine into power
- wait about one minute for the machine to settle
- run one scenario at a time
- run one Instruments template at a time

Do not overlap build, test, or capture sessions.

## Build Step

Run this once before opening Instruments:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/derived-data/Instruments-MarvisProfile \
  -clonedSourcePackagesDirPath .local/source-packages
```

## Test Environment Injection

The `.xctestrun` file produced by `build-for-testing` does not carry the e2e
gate and playback trace environment on its own. Patch it before each scenario
session. On current Xcode manifests, the override lives under
`TestConfigurations -> TestTargets -> EnvironmentVariables`:

```bash
uv run python - <<'PY'
from pathlib import Path
import plistlib

xctestrun_path = Path(
    ".local/derived-data/Instruments-MarvisProfile/Build/Products/"
    "SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun"
)

with xctestrun_path.open("rb") as f:
    data = plistlib.load(f)

for config in data.get("TestConfigurations", []):
    for target in config.get("TestTargets", []):
        env = target.setdefault("EnvironmentVariables", {})
        env["SPEAKSWIFTLY_E2E"] = "1"
        env["SPEAKSWIFTLY_PLAYBACK_TRACE"] = "1"

with xctestrun_path.open("wb") as f:
    plistlib.dump(data, f)
PY
```

## Targeted Test Command

Use this exact command for the current serialized Marvis baseline:

```bash
  xcodebuild test-without-building -quiet \
  -xctestrun .local/derived-data/Instruments-MarvisProfile/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/MarvisE2ETests/`queued audible playback stays serialized and routes expected voices`()' \
  -resultBundlePath .local/results/Instruments-MarvisProfile-serialized.xcresult
```

## Scenario Matrix

### Scenario A: Current Serialized Marvis Baseline

Use the test command above exactly as written.

This is the current package behavior and should be the first stable comparison
point for any profiling pass.

### Scenario B: Current Or Candidate Resident-Policy Comparison

If there is an in-branch resident-policy or upstream-informed candidate to
compare, rerun the same command and change only the result bundle path:

```bash
  xcodebuild test-without-building -quiet \
  -xctestrun .local/derived-data/Instruments-MarvisProfile/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/MarvisE2ETests/`queued audible playback stays serialized and routes expected voices`()' \
  -resultBundlePath .local/results/Instruments-MarvisProfile-candidate-policy.xcresult
```

### Scenario C: Single-Resident Dynamic Marvis Baseline

The package now has a real `single_resident_dynamic` policy option. If that
mode is under investigation, keep the same test command and record the exact
configuration override used for the run so the capture stays comparable to the
default `dual_resident_serialized` baseline.

## Instruments Capture Order

Use these templates in this order:

1. Time Profiler
2. Metal System Trace
3. Allocations or VM Tracker

Do not try to cram everything into one giant capture first.

### Time Profiler

Use this template to answer:

- what got hot on CPU when a Marvis generation actually began
- whether lane reservation itself is expensive
- whether the first request only becomes expensive later while playback tries
  to recover reserve

Workflow:

1. Open Instruments.
2. Choose `Time Profiler`.
3. Either attach to the `xctest` process immediately after launch or configure
   the capture so it is ready before running the test command.
4. Start recording.
5. Run the targeted `xcodebuild test-without-building` command.
6. Let the run continue until the first queued request has finished playback.
7. Stop recording.
8. Save the trace with a scenario-specific name such as:
   - `single-lane-time-profiler.trace`
   - `serialized-baseline-time-profiler.trace`
   - `candidate-policy-time-profiler.trace`

What to compare:

- the window just before `marvis_generation_lane_reserved`
- the window immediately after the queued follower request begins generating
- the first `playback_rebuffer_started` -> `playback_rebuffer_resumed` window

### Metal System Trace

Use this template to answer:

- whether GPU scheduling pressure appears at lane reservation time
- whether GPU work stays flat at reservation and only rises after sustained
  overlap begins
- whether the machine looks bandwidth-limited or queue-limited while the first
  playback is trying to refill reserve

Workflow:

1. Open Instruments.
2. Choose `Metal System Trace`.
3. Start recording before launching the test.
4. Run the same targeted `xcodebuild test-without-building` command.
5. Stop the capture after the first queued request has drained.
6. Save the trace with a scenario-specific name such as:
   - `single-lane-metal-system-trace.trace`
   - `serialized-baseline-metal-system-trace.trace`
   - `candidate-policy-metal-system-trace.trace`

What to compare:

- just before `marvis_generation_lane_reserved`
- the period immediately after the follower request begins generating
- the first rebuffer window

### Allocations or VM Tracker

Use one of these templates to answer:

- whether unified-memory pressure grows gradually during overlap
- whether the process footprint stays flat at lane reservation but ramps once
  overlap has been active for a while

Workflow:

1. Open Instruments.
2. Choose `Allocations` or `VM Tracker`.
3. Start recording before launching the test.
4. Run the same targeted `xcodebuild test-without-building` command.
5. Stop the capture after the first queued request has drained.
6. Save the trace with a scenario-specific name such as:
   - `single-lane-memory.trace`
   - `serialized-baseline-memory.trace`
   - `candidate-policy-memory.trace`

## How To Line the Capture Up With JSONL

The retained run artifact from the same test command is the source of truth for
event-level alignment.

After each run:

1. Find the newest run directory under `.local/e2e-runs`.
2. Open `stderr.jsonl`.
3. Find:
   - the first `marvis_generation_lane_reserved`
   - the first `playback_rebuffer_started`
   - the matching `playback_rebuffer_resumed`
   - the first request's `playback_finished`
4. Note each event's `ts` and `elapsed_ms`.
5. Match those windows against the Instruments timeline.

If needed, also keep the corresponding result bundle:

- `.local/results/Instruments-MarvisProfile-*.xcresult`

## What Good Evidence Looks Like

### Evidence that the former local queue policy was the problem

- single-lane stays clean
- serialized baseline stays cleaner than a more aggressive candidate
- lane reservation itself is quiet
- the expensive behavior appears only after a second request is allowed to compete

### Evidence that the machine is just near its ceiling

- single-lane is already rough
- the serialized baseline is still rough, and more aggressive candidates are only worse by degree
- Time Profiler and Metal System Trace both show pressure even before the
  follower request has really joined the active generation window

### Evidence that startup policy is still the main problem

- reservation and early overlap are the expensive moment
- later sustained overlap is not much worse than the initial handoff

## Follow-On Resident Policy Option

### Why A Single-Resident Marvis Policy Is Worth Considering

This would be a durable building-block change, not a local scheduler tweak.

The current backend surface already has:

- a public `SpeechBackend` enum
- startup-time `SpeakSwiftly.Configuration.speechBackend`
- the JSONL `set_speech_backend` control path
- runtime overview and job surfaces that already report which backend is active

The near-term use case it unlocks is simple:

- keep Marvis available on machines where the dual-resident default trade is not
  worth the audible instability
- preserve explicit operator intent instead of hiding that behavior behind
  scheduler heuristics or machine-local folklore
- let docs, tests, runtime overview, and stored job records say plainly which
  Marvis mode the worker is using

### Simpler Extension Path Considered First

The simpler path is the one the package now already has: keep one `marvis`
backend and expose the resident choice through `marvisResidentPolicy` instead
of adding another backend name.

That path was considered first, but it is less clear:

- it still needs clean profiling and docs work so the policy choices stay
  obvious
- it makes machine-specific behavior worth documenting explicitly
- it makes upstream-versus-local behavior comparison more important

The current policy-based shape is acceptable as long as the runtime and docs
keep the active resident policy explicit.

### Where That Policy Investigation Fits

The main surfaces that would need to widen are:

- [Sources/SpeakSwiftly/API/Configuration.swift](../../Sources/SpeakSwiftly/API/Configuration.swift)
- [Sources/SpeakSwiftly/Generation/ResidentSpeechModels.swift](../../Sources/SpeakSwiftly/Generation/ResidentSpeechModels.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift)

The expected behavior split is now:

- model loading can still reuse the same Marvis weights and the same built-in
  voice routing for `conversational_a` and `conversational_b`
- `dual_resident_serialized` keeps both voices warm while still serializing
  generation
- `single_resident_dynamic` reuses one resident model object for whichever
  conversational voice the next request needs

## Apple Documentation Anchors

These Apple docs are the main behavior anchors behind this runbook:

- Metal device memory inspection:
  <https://developer.apple.com/documentation/metal/device-inspection#Checking-a-GPU-devices-memory>
- Unified-memory and storage behavior on Apple GPUs:
  <https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus>
- CPU and GPU timestamp correlation:
  <https://developer.apple.com/documentation/metal/converting-gpu-timestamps-into-cpu-time>

## Repo References

- [Sources/SpeakSwiftly/Generation/ModelClients.swift](../../Sources/SpeakSwiftly/Generation/ModelClients.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift)
- [CONTRIBUTING.md](../../CONTRIBUTING.md)
