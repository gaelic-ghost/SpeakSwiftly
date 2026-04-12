# AGENTS.md

## Purpose

- This file is the repo-local guidance surface for the standalone `SpeakSwiftly` Swift package.
- Treat this repository as the source of truth for `SpeakSwiftly` package development, tags, and releases.
- Treat `../speak-to-user/packages/SpeakSwiftly` as the integration submodule copy, not the primary development home.

## Swift Package Workflow

- Use Swift Package Manager as the source of truth for package structure and dependencies.
- Prefer `swift package` subcommands for dependency, target, and manifest-adjacent changes before hand-editing `Package.swift`.
- Keep package graph updates cohesive across `Package.swift`, `Package.resolved`, and related source or test targets.
- Run `swift build` and `swift test` as the default validation checks after package-level changes.
- Use `xcodebuild` only when Apple-platform configuration details, test plans, SDK behavior, or Metal-toolchain behavior matter in a way plain SwiftPM cannot validate well.

## Repository Workflow

- Treat the local `../speak-to-user` checkout as a clean base checkout only. It must stay on `main`, and it must stay clean.
- Never change the local branch of the base `../speak-to-user` checkout for feature work, experiments, release bumps, or submodule updates.
- For any monorepo change, create a new branch in a new `git worktree` and do the work there instead of touching the base `../speak-to-user` checkout.
- After a monorepo branch is merged, fast-forward the base `../speak-to-user` checkout back to `main` and delete the merged worktree and branch.
- When `speak-to-user` adopts a new `SpeakSwiftly` version, prefer updating the submodule pointer to a tagged `SpeakSwiftly` release rather than an arbitrary branch tip.
- Land monorepo submodule bumps through a pull request against the monorepo instead of pushing those pointer updates directly to monorepo `main`.
- Use tagged releases for the monorepo when publishing coordinated umbrella states that depend on specific submodule versions.

## Repository Structure

- Keep `Sources/SpeakSwiftly/API` as the single home for public `SpeakSwiftly.Runtime` concern-handle accessors, `SpeakSwiftly.Name`, and other operator-facing library surface declarations.
- Keep feature logic in its feature directory, not in `Runtime/`. Text-normalization logic belongs in `Normalization/`, generation and voice-profile logic belongs in `Generation/`, and playback logic belongs in `Playback/`.
- Keep `Sources/SpeakSwiftly/Runtime` for runtime-only internals such as worker request handling, queue orchestration, lifecycle management, event emission, and other machinery that is genuinely part of the worker runtime itself.
- Do not split one feature across three places when two will do. For any given feature, prefer one API file in `API/` plus one logic file in the relevant feature directory.
- Mirror the source tree by feature area in tests so API, generation, playback, normalization, runtime, support, and e2e coverage are easy to find.

## Public Surface and Naming

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

## Swift and Architecture Baseline

- Read the relevant Apple or Swift documentation first for any Swift, Apple-framework, Apple-platform, SwiftUI, SwiftData, Observation, AppKit, UIKit, Foundation-on-Apple, or Xcode-related task before planning or changing code.
- Use Dash or local Apple documentation first, then official Apple or Swift web docs when local docs are insufficient.
- Before proposing an architecture or implementation, state the documented API behavior, lifecycle rule, or workflow requirement being relied on.
- If documentation and the current code disagree, stop and report the conflict before continuing.
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
- Before adding a new layer, abstraction, wrapper, manager, bridge, coordinator, repository, store, helper type, service, dependency, or package, explain which near-term use cases it unlocks here in `SpeakSwiftly`, which real pain or duplication it removes, and which simpler extension path was considered first.
- Do not change this repository's core architecture casually or silently. If the design starts needing a new queue, subsystem, storage model, or ownership boundary, stop and make that pivot explicit to Gale before implementing it, or as soon as the need becomes clear.
- When future scope is already visible and the current model will not compose cleanly, prefer strengthening the core primitives on purpose over shipping narrow stopgaps that will soon block momentum.

## Dependencies, Logging, and State

- Prefer first-party and top-tier Swift ecosystem packages from Apple, `swiftlang`, the Swift Server Work Group, and similar trusted core Swift projects when they simplify the code and make it easier to reason about.
- For packages, server-side, or cross-platform Swift, prefer Swift Logging as the primary logging API.
- Prefer Swift OpenTelemetry for telemetry and instrumentation when telemetry is needed, and prefer existing ecosystem integrations over bespoke wrappers.
- Prefer Nick Lockwood's SwiftFormat and/or SwiftLint as the baseline Swift formatting and linting tools; at least one should stay configured and used in this repository.

## Validation and Runtime Verification

- Never run multiple build toolchains, package managers, test runners, or other heavy validation commands at the same time on Gale's machine.
- Never run multiple SwiftPM or Xcode build or test processes concurrently for this repository.
- Treat `swift build` and `swift test` as the fast inner-loop checks for this package.
- Use Swift Testing (`import Testing`) as the default package test framework, and keep XCTest only when an external dependency or platform constraint requires it.
- Treat `SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests` as the opt-in real-model e2e path for this package.
- Keep the shared test profile convention stable unless Gale explicitly changes it:
  - `profile_name`: `testing-profile`
  - `voice_description`: `A generic, warm, masculine, slow speaking voice.`
- Expect generated `*.profraw` coverage artifacts from local test runs and do not commit them.
- Treat `SPEAKSWIFTLY_PLAYBACK_TRACE=1` as the preferred way to get chunk, scheduling, and rebuffer trace events during deep-trace playback work.
- For audible deep-trace playback verification, the standard opt-in path is:
  - `SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter longCodeHeavy`

## Runtime Publishing and Deep-Trace Guidance

- For this repository, use an Xcode-built worker product for real MLX-backed command-line runs and real-model e2e coverage. Upstream `mlx-swift` does not make the Metal shader bundle available to the plain SwiftPM command-line build.
- When launching the real worker from the shell, prefer the published runtime launcher and stable aliases under `.local/xcode/current-debug/run-speakswiftly` or `.local/xcode/current-release/run-speakswiftly`, or read the published runtime manifest first, instead of reconstructing `DYLD_FRAMEWORK_PATH` and `default.metallib` paths by hand.
- If a real worker run fails with `default.metallib` or `mlx-swift_Cmlx.bundle` errors, treat that as a build-and-launch-path problem first, not as evidence that the worker runtime itself is broken.
- For direct deep-trace worker captures, prefer the held-open stdin pattern instead of sending one JSONL file and allowing stdin to close immediately.
- The current known worker behavior is that if stdin closes before queued work drains, the worker can cancel queued requests that are still waiting behind resident-model warmup. Treat that as a current shutdown-and-queue quirk to be fixed, not as normal playback failure.
- Use the maintained scripts under `scripts/repo-maintenance/` for publish, verify, vendored-bundle refresh, release, and repo validation work instead of reconstructing those flows ad hoc.
