# Marvis Overlap Profiling Runbook

## Why This Exists

This note captures the current maintainer workflow for profiling the Marvis
resident overlap path on Apple silicon.

The immediate use case is:

- compare a clean Marvis baseline against the current dual-lane overlap behavior
- line Instruments captures up with the package's existing JSONL deep-trace events
- determine whether first-request rebuffering is mainly caused by CPU contention,
  GPU scheduling pressure, unified-memory pressure, or some combination of those
- preserve a repeatable profiling workflow so later maintainers do not have to
  reconstruct the Xcode-backed test path from old notes and shell history

This is not a general-purpose Xcode profiling guide. It is a package-specific
runbook for the exact `SpeakSwiftly` Marvis path that has already been under
investigation.

## Current Ground Truth

The current Marvis resident model repo in this package is:

- `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit`

That configuration lives in
[Sources/SpeakSwiftly/Generation/ModelClients.swift](../../Sources/SpeakSwiftly/Generation/ModelClients.swift).

So the current profiling question is not "is Marvis bf16 or int8?" The package
is already using the MLX 8-bit build. The more relevant question is whether the
current dual-lane overlap shape still creates enough sustained Apple-silicon
CPU, GPU, or unified-memory pressure to make the first audible playback unstable.

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

Use the Xcode-backed e2e path for this work.

Plain `swift test` is still not the reliable path for this exact Marvis lane
because the vendored `mlx-audio-swift` checkout can hit the parser issue in
`EnglishG2P.swift`. The current stable maintainer workflow is:

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
  -derivedDataPath .local/xcode/derived-data/Instruments-MarvisProfile \
  -clonedSourcePackagesDirPath .local/xcode/source-packages
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
    ".local/xcode/derived-data/Instruments-MarvisProfile/Build/Products/"
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

Use this exact command for the current dual-lane Marvis overlap baseline:

```bash
xcodebuild test-without-building -quiet \
  -xctestrun .local/xcode/derived-data/Instruments-MarvisProfile/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/MarvisWorkflowSuite/`prequeued jobs drain in order`()' \
  -resultBundlePath .local/xcode/results/Instruments-MarvisProfile-dual-lane.xcresult
```

## Scenario Matrix

### Scenario A: Current Dual-Lane Marvis Baseline

Use the test command above exactly as written.

This is the current package behavior and should be the first stable comparison
point for any profiling pass.

### Scenario B: Current or Candidate Safer-Overlap Policy

If there is an in-branch overlap experiment to compare, rerun the same command
and change only the result bundle path:

```bash
xcodebuild test-without-building -quiet \
  -xctestrun .local/xcode/derived-data/Instruments-MarvisProfile/Build/Products/SpeakSwiftly-Package_SpeakSwiftly-Package_macosx26.4-arm64.xctestrun \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/SpeakSwiftlyE2ETests/MarvisWorkflowSuite/`prequeued jobs drain in order`()' \
  -resultBundlePath .local/xcode/results/Instruments-MarvisProfile-candidate-policy.xcresult
```

### Scenario C: Single-Lane Marvis Baseline

This is not yet a stable package backend.

If a real `marvis_single_lane` or `marvis_sequential` backend is added later,
this runbook should be updated so the single-lane command becomes a first-class
copy-paste path.

Until then, do not pretend there is already a stable shell-only single-lane
command. If a single-lane comparison is needed before that backend exists, make
it in an isolated branch and record exactly what was changed for that branch.

## Instruments Capture Order

Use these templates in this order:

1. Time Profiler
2. Metal System Trace
3. Allocations or VM Tracker

Do not try to cram everything into one giant capture first.

### Time Profiler

Use this template to answer:

- what got hot on CPU when overlap started
- whether the reservation moment itself is expensive
- whether the first request only becomes expensive later while it tries to
  rebuild reserve

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
   - `dual-lane-time-profiler.trace`
   - `candidate-policy-time-profiler.trace`

What to compare:

- the window just before `marvis_generation_lane_reserved`
- the window immediately after overlap is active
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
   - `dual-lane-metal-system-trace.trace`
   - `candidate-policy-metal-system-trace.trace`

What to compare:

- just before `marvis_generation_lane_reserved`
- the period immediately after overlap becomes active
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
   - `dual-lane-memory.trace`
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

- `.local/xcode/results/Instruments-MarvisProfile-*.xcresult`

## What Good Evidence Looks Like

### Evidence that the overlap shape is the problem

- single-lane stays clean
- dual-lane degrades
- lane reservation itself is quiet
- the expensive behavior appears only after overlap has already been active

### Evidence that the machine is just near its ceiling

- single-lane is already rough
- dual-lane is worse, but not categorically different
- Time Profiler and Metal System Trace both show pressure even before the
  follower lane has really joined the overlap window

### Evidence that startup policy is still the main problem

- reservation and early overlap are the expensive moment
- later sustained overlap is not much worse than the initial handoff

## Follow-On Backend Option

### Why a Single-Lane Marvis Backend Is Worth Considering

This would be a durable building-block change, not a local scheduler tweak.

The current backend surface already has:

- a public `SpeechBackend` enum
- startup-time `SpeakSwiftly.Configuration.speechBackend`
- the JSONL `set_speech_backend` control path
- runtime overview and job surfaces that already report which backend is active

So a backend such as:

- `marvis_single_lane`
- `marvis_sequential`

would fit naturally beside:

- `qwen3`
- `marvis`

The near-term use case it unlocks is simple:

- keep Marvis available on machines where the two-lane overlap trade is not
  worth the audible instability
- preserve explicit operator intent instead of hiding that behavior behind
  scheduler heuristics
- let docs, tests, runtime overview, and stored job records say plainly which
  Marvis mode the worker is using

### Simpler Extension Path Considered First

The simpler path is to keep one `marvis` backend and add a hidden internal flag
or scheduler special case for single-lane behavior.

That path was considered first, but it is less clear:

- it hides a major behavior difference inside policy
- it makes logs and runtime expectations fuzzier
- it makes machine-specific behavior harder to reason about

A distinct backend is cleaner because it turns "single-lane Marvis" into a
first-class operator-facing choice.

### Where That Backend Would Fit

The main surfaces that would need to widen are:

- [Sources/SpeakSwiftly/Generation/SpeechBackend.swift](../../Sources/SpeakSwiftly/Generation/SpeechBackend.swift)
- [Sources/SpeakSwiftly/API/Configuration.swift](../../Sources/SpeakSwiftly/API/Configuration.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntimeProcessing+ResidentModels.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntimeProcessing+ResidentModels.swift)
- [Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift](../../Sources/SpeakSwiftly/Runtime/WorkerRuntimeScheduling.swift)

The expected behavior split is:

- model loading can still reuse the same Marvis weights and the same built-in
  voice routing for `conversational_a` and `conversational_b`
- the real behavior change lives in scheduling
- the single-lane backend should cap Marvis live generation concurrency at one
  and stop trying to open a second Marvis generation lane

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
