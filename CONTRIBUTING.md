# Contributing to SpeakSwiftly

Use this guide when preparing changes so SpeakSwiftly stays understandable, runnable, and reviewable.

## Table of Contents

- [Overview](#overview)
- [Contribution Workflow](#contribution-workflow)
- [Local Setup](#local-setup)
- [Development Expectations](#development-expectations)
- [Pull Request Expectations](#pull-request-expectations)
- [Communication](#communication)
- [License and Contribution Terms](#license-and-contribution-terms)

## Overview

### Who This Guide Is For

This guide is for people changing the SpeakSwiftly package, its tests, its worker executable, its maintainer scripts, or its contributor-facing documentation.

Agent-facing maintainer rules live in [AGENTS.md](./AGENTS.md). Keep the public [README.md](./README.md) focused on end users and agents deciding whether SpeakSwiftly fits their local speech workflow.

### Before You Start

Start from the package root. Read [AGENTS.md](./AGENTS.md), [ROADMAP.md](./ROADMAP.md), and any maintainer note under [docs/maintainers](./docs/maintainers/) that matches the area you are changing.

Use this repository as the source-of-truth development home for SpeakSwiftly. The larger `speak-to-user` repository consumes this package as a submodule and should not be used for primary package work.

## Contribution Workflow

### Choosing Work

Keep changes focused on one coherent package concern: API, generation, normalization, playback, runtime, tests, scripts, or docs. If a change needs to widen into a coordinated `speak-to-user` submodule bump, a release, or a runtime-publishing pass, confirm that scope before doing it.

### Making Changes

Use Swift Package Manager as the source of truth for package structure. Keep feature logic in its feature directory, keep public library surface in `Sources/SpeakSwiftly/API`, and mirror the source tree in `Tests/SpeakSwiftlyTests`.

Use Swift Testing for new package tests unless an existing external constraint requires XCTest. Keep operator-facing diagnostics descriptive enough that a maintainer can tell what broke and where to look next.

### Asking For Review

Before asking for review, make sure the docs split still holds:

- `README.md` is short, end-user and agent focused, and nontechnical.
- `CONTRIBUTING.md` owns contributor workflow, validation, maintainer operations, and technical reference pointers.
- `AGENTS.md` owns agent-facing maintainer guidance.
- `docs/maintainers/` owns deeper plans, runbooks, audits, and validation notes.

## Local Setup

### Runtime Config

Resolve package dependencies from the package root:

```bash
swift package resolve
```

Runtime state normally lives under the platform Application Support directory. Use an explicit state root only when a test, host, or local investigation needs isolated profiles, configuration, text profiles, and generated artifacts.

Useful environment variables include:

- `SPEAKSWIFTLY_STATE_ROOT` for an isolated worker state root when startup arguments are not available
- `SPEAKSWIFTLY_PROFILE_ROOT` is a deprecated compatibility alias for older hosts; do not use it in new integrations
- `SPEAKSWIFTLY_SPEECH_BACKEND` for backend selection fallback, including `qwen3_smol`, `qwen3_smol_6bit`, `qwen3_smol_8bit`, `qwen3_smol_bf16`, `qwen3_big`, `qwen3_big_6bit`, `qwen3_big_8bit`, and `qwen3_big_bf16`
- `SPEAKSWIFTLY_QWEN_RESIDENT_MODEL` is a deprecated compatibility alias for older hosts; choose a Qwen backend value instead
- `SPEAKSWIFTLY_ALLOW_PROFILE_CPU_FALLBACK=1` to explicitly allow the voice-profile model to load on CPU when the process cannot see a Metal GPU device; this is off by default because CPU-generated voice-profile conditioning is slow and should not become the normal package or host behavior
- `SPEAKSWIFTLY_E2E=1` for opt-in real-model end-to-end tests
- `SPEAKSWIFTLY_PLAYBACK_TRACE=1` for playback trace diagnostics

### System Profile Resource Authoring

System voice profiles are package-owned bundled resources, not ordinary end-user library creations. The supported authoring workflow inserts a new profile or updates the existing profile with the same name:

1. Run the `upsert-system-voice-profile` SwiftPM command plugin from the consumer package checkout.
2. Submit `upsert_system_voice_profile_from_description` through the tool JSONL surface or `SpeakSwiftly.Tool.upsertBuiltInVoiceProfile(...)`.
3. Review the generated profile under `Resources/SystemProfiles/profiles/<profile-name>/` in the consumer target.
4. Bundle the reviewed profile directory with the target that owns it by declaring `.copy("Resources/SystemProfiles")` in that target's package manifest entry.
5. Pass that target's bundled root into SpeakSwiftly at startup with `SpeakSwiftly.Configuration(systemProfileResourceRoots:)`, usually from `SpeakSwiftly.SupportResources.systemProfileRootURL(in: .module)`.

For example, a consumer package target can generate a bundled system profile with:

```bash
swift package plugin --allow-writing-to-package-directory upsert-system-voice-profile \
  --target SpeakSwiftlyServer \
  --name server-announcer \
  --text "A clear server status voice." \
  --vibe femme \
  --voice-description "Clear, bright, steady, and concise."
```

SwiftPM is the intended command-plugin entry point. Downstream packages get that entry point from the `UpsertSystemVoiceProfile` plugin product, while the user-facing command remains the verb `upsert-system-voice-profile`. The plugin itself resolves and runs `SpeakSwiftlyTool` through `context.tool(named: "SpeakSwiftlyTool")`, but host packages should not treat another checkout's `.build/.../SpeakSwiftlyTool` path as the plugin API. Launching that executable directly can be useful for lower-level maintainer diagnosis when paired with `--system-profile-resource-root PATH`, but it bypasses SwiftPM's plugin context, target lookup, write-permission gate, and artifact-path management.

If a host deliberately runs the helper executable directly, it owns the launch contract explicitly: pass `--system-profile-resource-root PATH`, send one JSONL request per stdin line, and review output under `PATH/profiles/<profile-name>/`. Direct helper launches may also pass `--allow-profile-cpu-fallback` when a nonstandard launch context cannot expose Metal and CPU authoring is an intentional one-off fallback.

The profile store uses `.profile-store.lock` inside the active `profiles/` directory to coordinate writers while profiles are generated or seeded. For plugin-authored system profiles, that means the lock can appear under `Resources/SystemProfiles/profiles/` after a successful run. It is an advisory coordination artifact, not a generated profile resource; leave it out of commits and reviews, and remove it only after confirming no SpeakSwiftly process is using that profile root.

Then the consuming target should pass its bundled system-profile root during startup:

```swift
let systemProfileRoots = [
    SpeakSwiftly.SupportResources.systemProfileRootURL(in: .module),
].compactMap(\.self)

let runtime = await SpeakSwiftly.liftoff(
    configuration: .init(systemProfileResourceRoots: systemProfileRoots)
)
```

At runtime, SpeakSwiftly loads bundled system profiles from its own package resource bundle and from configured consumer resource roots, then seeds them into the writable profile store. Do not expose system-profile upserts through `runtime.voices` or any ordinary public end-user API. If `upsert_system_voice_profile_from_description` is used without `--system-profile-resource-root`, the request must fail instead of writing package-owned profiles into ordinary runtime state.

When `SpeakSwiftlyTool` is launched with `--system-profile-resource-root`, it starts with resident playback models unloaded so the resource-authoring process does not warm unrelated runtime models before it can read JSONL input. The generated profile is still valid bundled profile material; prepared Qwen conditioning remains lazy and is created later by ordinary runtime use after resident models are explicitly loaded.

### Runtime Behavior

For ordinary package work, use the SwiftPM build and test lane first. Real standalone worker runs should use the deterministic runtime launcher produced by the repo-maintenance scripts, not a plain SwiftPM-built worker executable.

If a standalone worker run reports `default.metallib` or `mlx-swift_Cmlx.bundle` errors, treat that as a build-and-launch-path problem first. Rebuild the deterministic runtime and launch through the generated `run-speakswiftly` script.

## Development Expectations

### Naming Conventions

The typed Swift surface uses Cocoa-style names rooted at `SpeakSwiftly.liftoff(...)` and `SpeakSwiftly.Runtime` concern handles such as `generate`, `playback`, `voices`, `normalizer`, `jobs`, and `artifacts`.

Typed observation follows the `RequestEvent`, `RequestState`, `RequestUpdate`, and `RequestSnapshot` convention. Generate, Playback, Runtime, and per-request Synthesis observation families should keep rhyming with that model; see [docs/maintainers/typed-observation-api.md](./docs/maintainers/typed-observation-api.md).

The JSONL worker surface uses snake_case, verb-first operation names. Use `get_*` for one resource, `list_*` for collections, `create_*`, `update_*`, `replace_*`, and `delete_*` for CRUD-shaped mutations, and literal control verbs such as `queue_*`, `set_*`, `reload_*`, `unload_*`, `pause`, `resume`, `clear_*`, and `cancel_*` when those words match the real operation.

When adding or renaming a JSONL operation, update the worker contract article and this guide in the same pass.

Keep `upsert_system_voice_profile_from_description` as a development-time resource authoring operation. The flat JSONL operation name is intentional, but the operation belongs behind the `SpeakSwiftlyTool` development workflow and the `SpeakSwiftly.Tool` namespace, not the normal `SpeakSwiftly.Runtime.voices` library surface.

### Accessibility Expectations

SpeakSwiftly is not a UI repository, but it is part of Gale's local accessibility and speech-output surface. Treat local service disruption, unexpected audio playback, resident model memory pressure, and unclear diagnostics as accessibility-impacting concerns.

Before worker-backed E2E, use the repo-maintenance wrappers so they can unload and later reload resident models in the live `SpeakSwiftlyServer` service without uninstalling or stopping that service.

### Verification

Baseline package checks:

```bash
swift build
swift test
```

Full repo-maintenance validation:

```bash
bash scripts/repo-maintenance/validate-all.sh
```

Formatting and linting:

```bash
sh scripts/repo-maintenance/install-hooks.sh
swiftformat --lint --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

Worker-backed E2E:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite quick
sh scripts/repo-maintenance/run-e2e.sh --suite qwen-backends
sh scripts/repo-maintenance/run-e2e-full.sh
```

Deterministic runtime publishing and verification:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Release
```

Use [docs/maintainers/validation-lanes.md](./docs/maintainers/validation-lanes.md) for Xcode-backed fallback validation, iOS simulator smoke checks, real-model E2E details, and benchmark lanes.

## Pull Request Expectations

Summarize what changed, why it changed, and how it was verified. Call out any skipped validation, runtime behavior change, JSONL operation change, package dependency change, or public API change.

Keep README edits brief and reader-facing. Put contributor workflow, release operations, validation lanes, and maintainer details here or under [docs/maintainers](./docs/maintainers/).

## Communication

Surface uncertainty early when a change crosses package boundaries, changes runtime ownership, affects resident-model behavior, touches live-service safety, or needs a coordinated downstream adoption.

Ask before changing the shared test profile convention, release validation lane, runtime publishing layout, resident-model queue behavior, or the `speak-to-user` submodule pointer.

## License and Contribution Terms

By contributing, you agree that your contribution is provided under this repository's Apache License 2.0 terms. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
