# AGENTS.md

Repo-local guidance for the standalone `SpeakSwiftly` Swift package.

## Repository Scope

### What This File Covers

- This file is the repo-local guidance surface for the standalone `SpeakSwiftly` Swift package.
- Treat this repository as the source of truth for `SpeakSwiftly` package development, tags, and releases.
- Treat `../speak-to-user/packages/SpeakSwiftly` as the integration submodule copy, not the primary development home.

### Where To Look First

- Start with `Package.swift`, `Package.resolved`, `README.md`, `CONTRIBUTING.md`, and `ROADMAP.md` for package shape, dependency state, public docs, contributor workflow, and planned work.
- Read `Sources/SpeakSwiftly/API`, `Sources/SpeakSwiftly/Generation`, `Sources/SpeakSwiftly/Playback`, `Sources/SpeakSwiftly/Normalization`, and `Sources/SpeakSwiftly/Runtime` according to the feature surface being changed.
- Mirror source-tree context in `Tests/SpeakSwiftlyTests` before adding or moving test coverage.
- Use `docs/maintainers/validation-lanes.md` and `scripts/repo-maintenance/` for validation, release, runtime publishing, and maintainer operations.

## Working Rules

### Change Scope

- Use Swift Package Manager as the source of truth for package structure and dependencies.
- Prefer `swift package` subcommands for dependency, target, and manifest-adjacent changes before hand-editing `Package.swift`.
- Keep package graph updates cohesive across `Package.swift`, `Package.resolved`, and related source or test targets.
- Use `xcodebuild` only when Apple-platform configuration details, test plans, SDK behavior, or Metal-toolchain behavior matter in a way plain SwiftPM cannot validate well.
- Treat the local `../speak-to-user` checkout as a clean base checkout only. It must stay on `main`, and it must stay clean.
- Never change the local branch of the base `../speak-to-user` checkout for feature work, experiments, release bumps, or submodule updates.
- For any monorepo change, create a new branch in a new `git worktree` and do the work there instead of touching the base `../speak-to-user` checkout.
- After a monorepo branch is merged, fast-forward the base `../speak-to-user` checkout back to `main` and delete the merged worktree and branch.
- When `speak-to-user` adopts a new `SpeakSwiftly` version, prefer updating the submodule pointer to a tagged `SpeakSwiftly` release rather than an arbitrary branch tip.
- Land monorepo submodule bumps through a pull request against the monorepo instead of pushing those pointer updates directly to monorepo `main`.
- Use tagged releases for the monorepo when publishing coordinated umbrella states that depend on specific submodule versions.

### Source of Truth

- Keep `Sources/SpeakSwiftly/API` as the single home for public `SpeakSwiftly.Runtime` concern-handle accessors, `SpeakSwiftly.Name`, and other operator-facing library surface declarations.
- Keep feature logic in its feature directory, not in `Runtime/`. Text-normalization logic belongs in `Normalization/`, generation and voice-profile logic belongs in `Generation/`, and playback logic belongs in `Playback/`.
- Keep `Sources/SpeakSwiftly/Runtime` for runtime-only internals such as worker request handling, queue orchestration, lifecycle management, event emission, and other machinery that is genuinely part of the worker runtime itself.
- Do not split one feature across three places when two will do. For any given feature, prefer one API file in `API/` plus one logic file in the relevant feature directory.
- Mirror the source tree by feature area in tests so API, generation, playback, normalization, runtime, support, and e2e coverage are easy to find.
- For the JSONL worker surface, keep operation names snake_case and verb-first.
- For JSONL reads, use `get_*` for one resource or snapshot and `list_*` for collections and queue snapshots.
- For JSONL writes, prefer `create_*`, `update_*`, `replace_*`, and `delete_*` when those verbs fit the real semantics.
- Keep literal lifecycle and control verbs like `queue_*`, `set_*`, `reload_*`, `unload_*`, `pause`, `resume`, `clear_*`, `cancel_*`, `load_*`, `save_*`, and `reset_*` when the operation is not best modeled as CRUD.
- When adding or renaming a JSONL operation, update both `README.md` and `CONTRIBUTING.md` in the same pass so the wire naming convention stays documented.
- Keep `SpeakSwiftly.liftoff(configuration:)` as the single public startup entry point, with optional configuration carrying startup-time choices such as `speechBackend` and an optional `textNormalizer`.
- Expose stored concern handles such as `generate`, `player`, `voices`, `normalizer`, `jobs`, and `artifacts` from `SpeakSwiftly.Runtime` instead of growing one monolithic method namespace.
- Keep those concern handles lightweight views over shared runtime state, not separate subsystems with their own lifecycle or duplicated ownership.
- Prefer separate public generation verbs for live playback and file output, such as `Generate.speech(...)` and `Generate.audio(...)`, instead of exposing a public job-type switch.
- Keep generation-queue inspection on `Jobs` and playback-queue inspection on `Player`; do not mirror internal queue routing details in the public typed surface when the domain handle already makes ownership clearer.
- Public transport and result model types may stay public for inspection, but keep memberwise construction internal unless callers have a concrete reason to author those values directly.
- Use `SpeakSwiftly.Name` as the semantic name type for stored voice-profile names and similar stable operator-facing resources.
- For the voice-profile library surface, prefer one `Voices.create(...)` verb with explicit overloaded first labels, such as `create(design named: Name, ...)` and `create(clone named: Name, ...)`, instead of multiplying unrelated creation verbs.

### Communication and Escalation

- Read the relevant Apple or Swift documentation first for any Swift, Apple-framework, Apple-platform, SwiftUI, SwiftData, Observation, AppKit, UIKit, Foundation-on-Apple, or Xcode-related task before planning or changing code.
- Use Dash or local Apple documentation first, then official Apple or Swift web docs when local docs are insufficient.
- Before proposing an architecture or implementation, state the documented API behavior, lifecycle rule, or workflow requirement being relied on.
- If documentation and the current code disagree, stop and report the conflict before continuing.
- Before adding a new layer, abstraction, wrapper, manager, bridge, coordinator, repository, store, helper type, service, dependency, or package, explain which near-term use cases it unlocks here in `SpeakSwiftly`, which real pain or duplication it removes, and which simpler extension path was considered first.
- Do not change this repository's core architecture casually or silently. If the design starts needing a new queue, subsystem, storage model, or ownership boundary, stop and make that pivot explicit to Gale before implementing it, or as soon as the need becomes clear.
- When future scope is already visible and the current model will not compose cleanly, prefer strengthening the core primitives on purpose over shipping narrow stopgaps that will soon block momentum.

## Commands

### Setup

```bash
swift package resolve
```

### Validation

```bash
swift build
swift test
bash scripts/repo-maintenance/validate-all.sh
```

### Optional Project Commands

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/run-e2e.sh --suite quick
sh scripts/repo-maintenance/run-e2e-full.sh
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

Use `SPEAKSWIFTLY_PLAYBACK_TRACE=1` for chunk, scheduling, and rebuffer trace events during deep-trace playback work. For audible deep-trace playback verification, use:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter longCodeHeavy
```

Use `scripts/repo-maintenance/sync-shared.sh` for repo-local shared sync tasks, `scripts/repo-maintenance/release.sh` for releases, and the maintained scripts under `scripts/repo-maintenance/` for publish, verify, vendored-bundle refresh, and repo validation work instead of reconstructing those flows ad hoc.

## Review and Delivery

### Review Expectations

- Prefer the simplest correct Swift that is easiest to read, reason about, and maintain.
- Treat idiomatic Swift and Cocoa conventions as tools in service of readability, not goals by themselves.
- Do not add ceremony, abstraction, or boilerplate just to make code look more architectural, more generic, or more "Swifty".
- Strongly prefer synthesized, implicit, and framework-provided behavior over handwritten setup code.
- Prefer synthesized conformances, memberwise initializers, default property values, and framework defaults whenever they satisfy the real requirements.
- Do not add `CodingKeys`, manual `Codable`, custom initializers, wrappers, helper types, protocols, coordinators, or extra layers unless they are required by a concrete constraint or make the final code clearly easier to understand.
- Prefer stable, source-of-truth naming across layers when the data and meaning have not changed.
- Preserve raw wire and persistence shapes by default; do not add DTO, domain, or view-model conversion layers unless meaning actually changes or a concrete boundary requires it.
- Keep code compliant with Swift 6 language mode and strict concurrency checking.
- Prefer modern structured concurrency (`async`/`await`, task groups, actors, `AsyncSequence`) when it keeps the flow clearer and more direct.
- Prefer first-party and top-tier Swift ecosystem packages from Apple, `swiftlang`, the Swift Server Work Group, and similar trusted core Swift projects when they simplify the code and make it easier to reason about.
- For packages, server-side, or cross-platform Swift, prefer Swift Logging as the primary logging API.
- Prefer Swift OpenTelemetry for telemetry and instrumentation when telemetry is needed, and prefer existing ecosystem integrations over bespoke wrappers.
- Prefer Nick Lockwood's SwiftFormat and/or SwiftLint as the baseline Swift formatting and linting tools; at least one should stay configured and used in this repository.

### Definition of Done

- Never run multiple build toolchains, package managers, test runners, or other heavy validation commands at the same time on Gale's machine.
- Never run multiple SwiftPM or Xcode build or test processes concurrently for this repository.
- Treat `swift build` and `swift test` as the fast inner-loop checks for this package.
- For MLX-backed package tests, stay in the plain `swift test` lane by default. The test target bundles `default.metallib` and the shared test bootstrap stages it into the direct SwiftPM probe path under `.build/...` before the first MLX-backed test model is created.
- If `swift build` or `swift test` hit the current vendored `mlx-audio-swift` parser failure in `EnglishG2P.swift`, stop retrying the same SwiftPM lane and switch to the Xcode-backed validation path documented in `CONTRIBUTING.md` and `docs/maintainers/validation-lanes.md`.
- Treat the GitHub Actions package lane the same way: keep `swift package dump-package`, but use the Xcode-backed `build-for-testing` plus targeted `test-without-building` path until the vendored parser snag is gone.
- Use Swift Testing (`import Testing`) as the default package test framework, and keep XCTest only when an external dependency or platform constraint requires it.
- Treat `SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests` as the opt-in real-model e2e path for this package.
- For release-grade standalone-worker validation, Marvis overlap investigation, or any validation pass that is actually blocked by a renewed SwiftPM parser regression, prefer running `xcodebuild build-for-testing` from the repo root with `-scheme SpeakSwiftly-Package`, then follow it with targeted `xcodebuild test-without-building` runs instead of ad hoc retries through plain SwiftPM.
- Before worker-backed E2E, use the repo-maintenance wrappers so `scripts/repo-maintenance/unload-live-service-resident-models.sh` can ask the live `SpeakSwiftlyServer` service to unload resident models without uninstalling or stopping the LaunchAgent-backed service. The helper uses `SPEAKSWIFTLY_LIVE_SERVICE_BASE_URL` when set and only skips deliberately when `SPEAKSWIFTLY_SKIP_LIVE_SERVICE_UNLOAD=1`.
- Keep the shared test profile convention stable unless Gale explicitly changes it:
  - `profile_name`: `testing-profile`
  - `voice_description`: `A generic, warm, masculine, slow speaking voice.`
- Expect generated `*.profraw` coverage artifacts from local test runs and do not commit them.

## Safety Boundaries

### Never Do

- For this repository, use an Xcode-built worker product for real MLX-backed command-line runs and real-model e2e coverage. Upstream `mlx-swift` does not make the Metal shader bundle available to the plain SwiftPM command-line build.
- When launching the real worker from the shell, prefer the deterministic Xcode runtime launcher under `.local/derived-data/runtime-debug/run-speakswiftly` or `.local/derived-data/runtime-release/run-speakswiftly` instead of reconstructing `DYLD_FRAMEWORK_PATH` and `default.metallib` paths by hand.
- If a real worker run fails with `default.metallib` or `mlx-swift_Cmlx.bundle` errors, treat that as a build-and-launch-path problem first, not as evidence that the worker runtime itself is broken.
- For direct deep-trace worker captures, prefer the held-open stdin pattern instead of sending one JSONL file and allowing stdin to close immediately.
- The current known worker behavior is that if stdin closes before queued work drains, the worker can cancel queued requests that are still waiting behind resident-model warmup. Treat that as a current shutdown-and-queue quirk to be fixed, not as normal playback failure.

### Ask Before

- Ask before widening a package change into a coordinated `speak-to-user` monorepo submodule bump or coordinated umbrella tag.
- Ask before changing the shared test profile convention, release validation lane, runtime publishing layout, or resident-model queue behavior.
- Ask before replacing the SwiftPM-first package workflow with an Xcode-first workflow for ordinary package work.

## Local Overrides

This repository does not currently define deeper `AGENTS.md` files. If a future subdirectory adds one, the closer file refines this root guidance for work inside that subtree.
