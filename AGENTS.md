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

### Documentation Ownership

- Keep `README.md` short, nontechnical, and focused on end users and agents deciding whether SpeakSwiftly fits a local speech workflow.
- Keep contributor workflow, maintainer operations, validation lanes, release workflow, and technical reference pointers in `CONTRIBUTING.md` or `docs/maintainers/`, not in `README.md`.
- Keep agent-facing maintainer guidance in this `AGENTS.md` file so future agents do not need to infer operating rules from public-facing docs.
- Leave `README.md` Overview subsections that need Gale's own wording as `TBD` until Gale provides the replacement text.

### Change Scope

- Use Swift Package Manager as the source of truth for package structure and dependencies.
- Prefer `swift package` subcommands for dependency, target, and manifest-adjacent changes before hand-editing `Package.swift`.
- Keep package graph updates cohesive across `Package.swift`, `Package.resolved`, and related source or test targets.
- Use `xcodebuild` only when Apple-platform configuration details, test plans, SDK behavior, or Metal-toolchain behavior matter in a way plain SwiftPM cannot validate well.
- Treat `mlx-audio-swift` as a current compatibility dependency to shrink and
  eventually remove, not as the default implementation home for new model
  families.
- For new speech model research and backend work, prefer first-party
  Swift-owned Apple-platform pipelines using Core AI, Accelerate, CoreMedia,
  CoreAudio, and AVFoundation where those frameworks fit the stage.
- Treat community ports such as `mlx-audio` and `mlx-audio-swift` as comparison
  evidence unless Gale explicitly asks to adopt or port them directly.
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
- When adding or renaming a JSONL operation, update `Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md` and `CONTRIBUTING.md` in the same pass so the wire naming convention stays documented without making `README.md` technical.
- Keep `SpeakSwiftly.liftoff(configuration:)` as the single public startup entry point, with optional configuration carrying startup-time choices such as `speechBackend` and an optional `textNormalizer`.
- Expose stored concern handles such as `generate`, `playback`, `voices`, `normalizer`, `jobs`, and `artifacts` from `SpeakSwiftly.Runtime` instead of growing one monolithic method namespace.
- Keep typed Swift observation surfaces aligned around `Event`, `State`, `Update`, and `Snapshot` model families. `RequestEvent`, `RequestState`, `RequestUpdate`, and `RequestSnapshot` are the baseline shape; Generate, Playback, Runtime, and per-request Synthesis observation should rhyme with that model.
- Keep those concern handles lightweight views over shared runtime state, not separate subsystems with their own lifecycle or duplicated ownership.
- Prefer separate public generation verbs for live playback and file output, such as `Generate.speech(...)` and `Generate.audio(...)`, instead of exposing a public job-type switch.
- Keep generation-queue inspection on `Generate` / `Jobs` and playback-queue inspection on `Playback`; do not mirror internal queue routing details in the public typed surface when the domain handle already makes ownership clearer.
- Public transport and result model types may stay public for inspection, but keep memberwise construction internal unless callers have a concrete reason to author those values directly.
- Use `SpeakSwiftly.Name` as the semantic name type for stored voice-profile names and similar stable operator-facing resources.
- For the voice-profile library surface, prefer one `Voices.create(...)` verb with explicit overloaded first labels, such as `create(design named: Name, ...)` and `create(clone named: Name, ...)`, instead of multiplying unrelated creation verbs.
- For first-party bundled built-in voices, use the `create-system-voice-profile` SwiftPM command plugin from this checkout with `--target SpeakSwiftly`; it writes reviewed system profile resources under `Sources/SpeakSwiftly/Resources/SystemProfiles/profiles/`, which the `SpeakSwiftly` target already bundles.

### Communication and Escalation

- Read the relevant Apple or Swift documentation first for any Swift, Apple-framework, Apple-platform, SwiftUI, SwiftData, Observation, AppKit, UIKit, Foundation-on-Apple, or Xcode-related task before planning or changing code.
- Use Dash or local Apple documentation first, then official Apple or Swift web docs when local docs are insufficient.
- Before proposing an architecture or implementation, state the documented API behavior, lifecycle rule, or workflow requirement being relied on.
- If documentation and the current code disagree, stop and report the conflict before continuing.
- Before adding a new layer, abstraction, wrapper, manager, bridge, coordinator, repository, store, helper type, service, dependency, or package, explain which near-term use cases it unlocks here in `SpeakSwiftly`, which real pain or duplication it removes, and which simpler extension path was considered first.
- Do not change this repository's core architecture casually or silently. If the design starts needing a new queue, subsystem, storage model, or ownership boundary, stop and make that pivot explicit to Gale before implementing it, or as soon as the need becomes clear.
- When future scope is already visible and the current model will not compose cleanly, prefer strengthening the core primitives on purpose over shipping narrow stopgaps that will soon block momentum.

### Workflow Sync

- Use `bootstrap-swift-package` only when a new Swift package repository still needs to be created from scratch.
- Use `sync-swift-package-guidance` when this repository's package workflow guidance drifts and needs to be refreshed or merged forward.
- Re-run `sync-swift-package-guidance` after substantial package-workflow or Apple Dev Skills plugin updates so the local guidance and repo-maintenance contract stay aligned.
- Keep the repo-owned Codex local environment in `.codex/environments/swift-package.toml` portable and repo-relative so shared setup and action buttons work the same way across worktrees.

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
SPEAKSWIFTLY_E2E=1 swift test --filter GeneratedFileE2ETests
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
- The older vendored `mlx-audio-swift` parser failure in `EnglishG2P.swift` is historical with the current dependency pin. If a future `swift build` or `swift test` run hits that same failure again, stop retrying the same SwiftPM lane and switch to the Xcode-backed validation path documented in `CONTRIBUTING.md` and `docs/maintainers/validation-lanes.md`.
- Treat the GitHub Actions package lane as its own documented CI surface: keep `swift package dump-package`, then use the current Xcode-backed `build-for-testing` plus targeted `test-without-building` matrix shown in `.github/workflows/swift.yml`.
- Use Swift Testing (`import Testing`) as the default package test framework, and keep XCTest only when an external dependency or platform constraint requires it.
- Treat `sh scripts/repo-maintenance/run-e2e.sh --suite quick` as the smallest opt-in real-model E2E path for this package.
- For release-grade standalone-worker validation, Marvis overlap investigation, or any validation pass that is actually blocked by a renewed SwiftPM parser regression, prefer running `xcodebuild build-for-testing` from the repo root with `-scheme SpeakSwiftly-Package`, then follow it with targeted `xcodebuild test-without-building` runs instead of ad hoc retries through plain SwiftPM.
- Before worker-backed E2E, use the repo-maintenance wrappers so `scripts/repo-maintenance/unload-live-service-resident-models.sh` can ask the live `SpeakSwiftlyServer` service to unload resident models without uninstalling or stopping the LaunchAgent-backed service, and `scripts/repo-maintenance/reload-live-service-resident-models.sh` can restore residency after testing completes. The helpers use `SPEAKSWIFTLY_LIVE_SERVICE_BASE_URL` when set and only skip deliberately when `SPEAKSWIFTLY_SKIP_LIVE_SERVICE_UNLOAD=1` and `SPEAKSWIFTLY_SKIP_LIVE_SERVICE_RELOAD=1`.
- Keep the shared test profile convention stable unless Gale explicitly changes it:
  - `profile_name`: `testing-profile`
  - `voice_description`: `A generic, warm, masculine, slow speaking voice.`
- Expect generated `*.profraw` coverage artifacts from local test runs and do not commit them.

## Safety Boundaries

### Never Do

- Do not use a plain SwiftPM-built worker product for real MLX-backed command-line runs and real-model E2E coverage. Use the Xcode-built worker product for those standalone executable lanes because upstream `mlx-swift` does not make the Metal shader bundle available to the plain SwiftPM command-line build.
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

## Swift Package Workflow

- Use `swift build` and `swift test` as the default first-pass validation commands for this package.
- Use `bootstrap-swift-package` when a new Swift package repo still needs to be created from scratch.
- Use `sync-swift-package-guidance` when the repo guidance for this package drifts and needs to be refreshed or merged forward.
- Re-run `sync-swift-package-guidance` after substantial package-workflow or plugin updates so local guidance stays aligned.
- Use `swift-package-build-run-workflow` for manifest, dependency, plugin, resource, Metal-distribution, build, and run work when `Package.swift` is the source of truth.
- Use `swift-package-testing-workflow` for Swift Testing, XCTest holdouts, `.xctestplan`, fixtures, and package test diagnosis.
- Use `scripts/repo-maintenance/validate-all.sh` for local maintainer validation and `scripts/repo-maintenance/sync-shared.sh` for repo-local sync steps.
- Use `scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z` from a feature branch or worktree only when the task is actually a protected-main release, publish, merge, tag, or release-PR preparation.
- Do not run the standard release workflow from `main`; when a protected-main release is explicitly requested, let it validate, bump versions, tag, push the branch and tag, open the release PR, watch CI, address valid PR comments or record out-of-scope concerns in `ROADMAP.md`, merge to protected `main`, fast-forward local `main`, and clean up stale branches.
- Treat `scripts/repo-maintenance/config/profile.env` as the installed `maintain-project-repo` profile marker, and keep it on the `swift-package` profile for plain package repos.
- Read relevant SwiftPM, Swift, and Apple documentation before proposing package-structure, dependency, manifest, concurrency, or architecture changes.
- Prefer Dash or local Swift docs first, then official Swift or Apple docs when local docs are insufficient.
- When SwiftPM behavior, manifest syntax, package plugins, resources, products, targets, or dependency rules matter, prefer the Dash.app docset workflow with the `swiftlang/swift-package-manager` docset first; fall back to the canonical `swiftlang/swift-package-manager` GitHub repository only when the local docset is unavailable or insufficient.
- Prefer the simplest correct Swift that is easiest to read and reason about.
- Prefer synthesized and framework-provided behavior over extra wrappers and boilerplate.
- For public Swift APIs, treat streamlined, compact, ergonomic call sites as the only acceptable default; prefer optional parameters with explicit default values over additional methods or overloads when the difference is optional behavior on the same operation.
- When a public function, initializer, or method reaches four or more arguments or parameters, strongly prefer a named typed `struct` request, options, or configuration value so call sites stay readable and future additions do not multiply overloads.
- Prefer enums, enum cases with associated values, and narrow typed values over strings, booleans, sentinel values, or parallel parameters whenever the domain has a closed or meaningful set of choices.
- Keep data flow straight and dependency direction unidirectional.
- Treat `Package.swift` as the source of truth for package structure, targets, products, and dependencies.
- Prefer `swift package` subcommands for structural package edits before manually editing `Package.swift`.
- Edit `Package.swift` intentionally and keep it readable; agents may modify it when package structure, targets, products, or dependencies need to change, and should try to keep package graph updates consolidated in one change when possible.
- Keep `Package.swift` explicit about its package-wide Swift language mode. On current Swift 6-era manifests, prefer `swiftLanguageModes: [.v6]` as the default declaration, treat `swiftLanguageVersions` as a legacy alias used only when an older manifest surface requires it, and keep the supported Swift toolchain window focused on the latest stable minor and previous stable minor. Treat Swift `6.2` as the current minimum floor for trait-enabled manifests, not as a ceiling; use newer stable Swift toolchains when available and validated, and refresh this guidance when the maintained floor or window changes. Do not lower `// swift-tools-version:` below `6.2` without an explicit repo policy and a matching guidance update.
- Keep `swift-configuration` as the default configuration dependency for Swift packages unless the package has a concrete reason to remove it. The preferred manifest shape depends on `https://github.com/apple/swift-configuration` from `1.2.0`, enables the `.defaults`, `Reloading`, `YAML`, and `CommandLineArguments` package traits, and adds the `Configuration` product to the primary target. Add the `PropertyList` trait when the package should parse property-list configuration, and add the `Logging` trait when configuration access should integrate with `SwiftLog.Logger`.
- Keep dependency provenance concise but explicit enough for another contributor to fetch the same package: use package-manager, package-registry, GitHub URL, or other real remote repository requirements, and do not commit machine-local dependency paths such as `/Users/...`, `~/...`, `../...`, local worktrees, or private checkout paths. Avoid branch- or revision-based requirements unless the user explicitly asks for that level of control.
- Treat `Package.resolved` and similar package-manager outputs as generated files; do not hand-edit them.
- Prefer Swift Testing by default unless an external constraint requires XCTest.
- Use `apple-ui-accessibility-workflow` when the package work crosses into SwiftUI accessibility semantics, Apple UI accessibility review, or UIKit/AppKit accessibility bridge behavior.
- Keep package resources under the owning target tree, declare them intentionally with `Resource.process(...)`, `Resource.copy(...)`, `Resource.embedInCode(...)`, and load them through `Bundle.module`.
- Keep test fixtures as test-target resources instead of relying on the working directory.
- Bundle precompiled Metal artifacts such as `.metallib` files as explicit resources when they ship with the package, and prefer `xcode-build-run-workflow` when shader compilation or Apple-managed Metal toolchain behavior matters.
- Prefer normal SwiftPM parallel test execution for ordinary Swift Testing and XCTest runs. Do not serialize regular package tests just because they use Swift, XCTest, async tests, fixtures, or test plans.
- Treat tests that load large local AI or ML models, especially models over 500 million parameters, as heavy system-resource tests. Run those tests sequentially, one at a time, and call `unload_models` on Gale's live TTS service before the heavy run and `reload_models` after it ends, even when the run fails or is interrupted.
- Validate both Debug and Release paths when optimization or packaging differences matter, and treat tagged releases as a cue to verify the Release artifact path before publishing.
- Prefer `xcode-build-run-workflow` or `xcode-testing-workflow` only when package work needs Xcode-managed SDK, toolchain, or test behavior.
- Keep runtime UI accessibility verification and XCUITest follow-through in `xcode-testing-workflow` rather than treating package-side testing as a substitute for live UI verification.
