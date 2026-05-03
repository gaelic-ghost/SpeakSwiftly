# Project Roadmap

## Vision

- Build a small, reliable Swift worker executable that keeps MLX and Apple-runtime concerns isolated behind a simple process boundary.

## Product Principles

- Keep the worker thin and concrete instead of layering it into a mini-framework.
- Prefer one boring process boundary over multiple internal coordinators or bridges.
- Make every operator-facing error and progress message readable and specific.
- Keep the resident backend path fast, predictable, and easy to reason about.
- Let `mlx-audio-swift` own model loading and generation whenever its existing API surface already fits.
- Keep voice profiles immutable once created; require explicit removal instead of silent overwrite.
- Keep playback, generation, normalization, and runtime ownership boundaries visible in both code and docs.

## Roadmap Shape

This roadmap now keeps active milestones and the current release-hardening queue in one place. Older completed plans, superseded investigations, and landing notes have been condensed into the history section so maintainer guidance stays readable instead of fragmenting across stale documents.

## Table of Contents

- [Vision](#vision)
- [Product Principles](#product-principles)
- [Roadmap Shape](#roadmap-shape)
- [Milestone Progress](#milestone-progress)
- [Active Milestones](#active-milestones)
- [Milestone 4: File Rendering And Integration Hardening](#milestone-4-file-rendering-and-integration-hardening)
- [Milestone 6: Multi-Process Profile-Store Hardening](#milestone-6-multi-process-profile-store-hardening)
- [Milestone 9: Live-Service Operability Review](#milestone-9-live-service-operability-review)
- [Milestone 13: Swift Package Distribution](#milestone-13-swift-package-distribution)
- [Milestone 16: `mlx-audio-swift` Upgrade Review](#milestone-16-mlx-audio-swift-upgrade-review)
- [Milestone 17: Notification-Linked Priority Playback](#milestone-17-notification-linked-priority-playback)
- [Milestone 18: Package Docs And Distribution Polish](#milestone-18-package-docs-and-distribution-polish)
- [Milestone 21: Unified Logging With `Logger`](#milestone-21-unified-logging-with-logger)
- [Milestone 22: Marvis MLX Generation-Path Investigation And Playback Tuning](#milestone-22-marvis-mlx-generation-path-investigation-and-playback-tuning)
- [Milestone 26: Pre-v1 Release Hardening](#milestone-26-pre-v1-release-hardening)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Milestone Progress

- Milestone 4: File Rendering And Integration Hardening - In Progress
- Milestone 6: Multi-Process Profile-Store Hardening - Planned
- Milestone 9: Live-Service Operability Review - In Progress
- Milestone 13: Swift Package Distribution - In Progress
- Milestone 16: `mlx-audio-swift` Upgrade Review - In Progress
- Milestone 17: Notification-Linked Priority Playback - Planned
- Milestone 18: Package Docs And Distribution Polish - In Progress
- Milestone 21: Unified Logging With `Logger` - Planned
- Milestone 22: Marvis MLX Generation-Path Investigation And Playback Tuning - In Progress
- Milestone 26: Pre-v1 Release Hardening - In Progress

## Active Milestones

## Milestone 4: File Rendering And Integration Hardening

### Status

In Progress

### Scope

- [ ] Make the worker straightforward to own from a parent process.
- [ ] Finish the remaining hardening around retained file output, worker EOF, and process-lifecycle behavior.
- [ ] Keep retained file output profile-based and aligned with the live generation path.

### Tickets

- [ ] Audit the current `GeneratedFileE2ETests`, `GeneratedBatchE2ETests`, shutdown tests, malformed-input tests, and profile-store tests for any remaining file-rendering or worker-ownership gaps.
- [ ] Add targeted coverage for missing profiles, duplicate profile creation, profile removal, or process-lifecycle edges only where the audit finds behavior that is still untested.
- [ ] Tighten any remaining clean EOF or shutdown behavior for long-lived worker ownership that is not already covered by the current worker E2E lanes.
- [ ] Keep the retained-file packaging notes concrete and minimal as the worker ownership story settles.

### Exit Criteria

- [ ] The worker exits cleanly on EOF or shutdown requests.
- [ ] Saved-file generation is operationally as predictable as live playback.
- [ ] Failure modes around malformed JSONL, profile storage, and filesystem issues are covered by tests.

## Milestone 6: Multi-Process Profile-Store Hardening

### Status

Planned

### Scope

- [ ] Make the on-disk profile store safe and predictable when multiple local processes use it at the same time.
- [ ] Preserve the current shared-store shape without adding unnecessary architecture around it.
- [ ] Keep profile creation, listing, loading, and removal human-readable when cross-process contention or stale state appears.

### Tickets

- [ ] Add cross-process coordination for profile creation and removal so concurrent workers cannot partially stomp each other.
- [ ] Keep profile writes atomic across manifest and reference-audio creation, including cleanup of abandoned temp data after failed writes.
- [ ] Make profile listing and loading resilient to in-flight writes from another process without producing misleading corruption failures.
- [ ] Add clear operator-facing diagnostics for lock contention, stale temp directories, and cross-process filesystem races.
- [ ] Add automated coverage for concurrent create/load/remove access against the shared profile root.
- [ ] Document the shared per-user default profile root and the state-root override path for process-isolated profile stores.

### Exit Criteria

- [ ] Two local processes can share the default profile store without silent corruption or partially written profiles.
- [ ] Cross-process profile creation and removal failures are explicit, structured, and recoverable.
- [ ] The shared-store behavior and override-based isolation path are documented clearly for downstream apps and services.

## Milestone 9: Live-Service Operability Review

### Status

In Progress

### Scope

- [ ] Tighten the worker contract around service ownership and operational inspection for long-lived local deployments.
- [ ] Make filesystem behavior and service-state inspection predictable for parent processes.
- [ ] Make adjacent local consumer update flows explicit and reliable when standalone `SpeakSwiftly` releases are tagged.

### Tickets

- [ ] Revisit `output_path` resolution so relative paths cannot silently depend on the worker launch directory.
- [x] Extend the existing `get_runtime_overview` / `runtime.overview()` inspection story so parent processes can inspect runtime-state, profile-store, configuration, text-profile, generated-file, and generation-job paths without log scraping.
- [ ] Add a runtime-level playback and overview event stream so hosts can keep playback state current without opportunistic polling. ([#45](https://github.com/gaelic-ghost/SpeakSwiftly/issues/45))
- [x] Add native state-root startup controls so Application Support stays the default while Swift callers use `stateRootURL`, worker hosts use `--state-root`, and `SPEAKSWIFTLY_PROFILE_ROOT` remains only as a deprecated compatibility alias. ([#21](https://github.com/gaelic-ghost/SpeakSwiftly/issues/21))
- [ ] Make profile listing resilient to stray files, partial directories, and damaged entries without poisoning the full operation when recovery is possible.
- [ ] Add a first-class default-profile concept so downstream callers are not forced to treat names like `default-femme` as hidden conventions.
- [ ] Persist a little more voice-profile source provenance from creation flows so rerolls, diagnostics, and later profile introspection have stable grounding.
- [ ] Investigate whether startup-side playback preload or environment observation is still correlated with `freed pointer was not the last allocation`. ([#7](https://github.com/gaelic-ghost/SpeakSwiftly/issues/7))
- [ ] Document the parent-process ownership expectations for startup warmup, health inspection, shutdown, and state-root selection.
- [ ] Document the current tag-time adoption flow for active downstream consumers such as `SpeakSwiftlyServer` and the `speak-to-user` integration repository, including what is automatic and what remains explicit follow-up.

### Exit Criteria

- [ ] Parent processes can inspect worker state and reason about service health without log scraping alone.
- [ ] Path resolution and profile-store behavior are predictable across different launch environments.
- [ ] The standalone release workflow clearly describes which downstream consumers are updated automatically and which still require explicit follow-up.

## Milestone 13: Swift Package Distribution

### Status

In Progress

### Scope

- [ ] Make `SpeakSwiftly` straightforward to consume as a real distributed Swift package instead of only as an adjacent local checkout.
- [ ] Clarify what public API and semver guarantees the package actually intends to support for downstream apps and services.
- [ ] Keep distribution work grounded in the existing package surface instead of adding unnecessary packaging layers or wrapper targets.

### Tickets

- [ ] Decide which parts of the public API are intended stable consumer contract versus transport-facing worker compatibility surface.
- [ ] Document SwiftPM dependency examples for the library product and clarify how package consumers should think about the executable product.
- [ ] Add a package-consumer verification path that exercises dependency resolution from a clean external package instead of relying only on sibling-checkout integration.
- [ ] Land the playback-platform seam described in `docs/maintainers/ios-portability-plan-2026-04-17.md` before widening supported platforms beyond macOS.
- [ ] Decide whether package-registry publication is in scope or whether Git-based SwiftPM distribution is the intended first supported path.
- [ ] Tighten release notes and release-checklist language so package consumers can tell when a change is semver-safe versus when migration work is required.
- [ ] Document any remaining Xcode-built runtime caveats clearly so distributed package consumers understand where SwiftPM alone is sufficient and where it is not.

### Exit Criteria

- [ ] A downstream Swift package can adopt `SpeakSwiftly` through a documented supported distribution path without relying on repo-local adjacency assumptions.
- [ ] The supported package surface and migration expectations are explicit enough for semver-based consumption.
- [ ] Package distribution stays thin and concrete rather than accumulating extra compatibility wrappers.

## Milestone 16: `mlx-audio-swift` Upgrade Review

### Status

In Progress

### Scope

- [ ] Review a newer `mlx-audio-swift` release or revision and decide whether `SpeakSwiftly` should adopt it.
- [ ] Keep the worker thin and direct while making dependency drift easier to reason about.
- [ ] Avoid wrapper-heavy compatibility architecture unless a real upstream API break makes it necessary.

### Tickets

- [ ] Compare the currently pinned `mlx-audio-swift` revision with the latest available tagged release or stable candidate.
- [ ] Review upstream changes to Qwen3 TTS defaults, generation controls, streaming behavior, and model-loading expectations for any impact on `SpeakSwiftly`.
- [ ] Preserve upstream `AudioGeneration` event detail through a first-class side-channel, trace stream, or equivalent logging surface instead of collapsing every resident generation path down to raw sample chunks at the first wrapper boundary.
- [ ] Land durable Qwen generated-code investigation tooling on `main`, including capture, replay, code-stream comparison, and WAV-side prosody inspection commands that replace the invalid `compare-volume` diagnostic path.
- [ ] Add Qwen E2E quality gates that inspect late-generation behavior, repeated or spiraling output, suspicious token/audio length, and per-chunk tail drift instead of treating playback completion as sufficient proof of speech quality.
- [ ] Run the sampling-headroom investigation described in `docs/maintainers/qwen-sampling-headroom-report-2026-04-24.md` after generated-file rendering and the generated-code capture tools are trustworthy on `main`.
- [ ] Evaluate whether the current resident backend defaults are still the right MLX choices on current Apple Silicon, and record the latency, memory, and audible tradeoffs explicitly.
- [ ] Generalize stored Qwen materializations so profiles can load backend-appropriate conditioning material without assuming one hard-coded shape forever.
- [ ] Evaluate `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit` after the 1.7B 8-bit resident path has enough local latency, memory, and audible-quality evidence.
- [ ] Make clone auto-transcription available to every cloning-capable backend instead of treating transcript inference as a Qwen-only implementation detail.
- [ ] Re-run resident playback, profile-generation, and typed-library integration checks against a candidate upgrade in an isolated branch.
- [ ] Record any concrete reasons to upgrade, defer, or stay pinned, including behavior changes that affect playback stability or generation length.

### Exit Criteria

- [ ] The repository documents whether a newer `mlx-audio-swift` should be adopted and why.
- [ ] Dependency policy around `mlx-audio-swift` is explicit enough that future playback or generation regressions are easier to trace.

## Milestone 17: Notification-Linked Priority Playback

### Status

Planned

### Scope

- [ ] Decide how callers can submit ordinary speech work plus separate notification-linked priority playback work without making the worker contract confusing.
- [ ] Review whether the existing request queue can absorb this feature cleanly or whether a distinct playback queue is truly necessary.
- [ ] Keep the design thin and concrete instead of introducing a new queue, manager, coordinator, or job subsystem unless the simpler extension path clearly fails.

### Tickets

- [ ] Define the minimum useful notification-linked job shape, including a normal speech job, a priority notification job, and a pre-generated straight-to-playback variant if that path is still justified after contract review.
- [ ] Decide whether priority playback should be modeled as new request kinds inside the existing queueing model or whether a separate playback queue is truly required.
- [ ] Document how priority jobs interact with active playback, waiting requests, pause or resume state, and future queue inspection or cancellation controls.
- [ ] Define whether Notification Center ownership lives inside `SpeakSwiftly`, in a parent process, or behind a narrow optional integration boundary.
- [ ] If notification clicks can trigger playback, define the stable identifier and persistence boundary for the associated speech job.
- [ ] Decide how pre-generated audio is stored, referenced, expired, and played back without duplicating the normal playback path unnecessarily.
- [ ] Add typed Swift library parity for submitting, inspecting, and triggering notification-linked priority jobs if this feature lands in the package surface.
- [ ] Add automated coverage for ordinary queued playback plus injected priority work, notification-linked playback triggering, and no-op behavior when referenced jobs are missing or already consumed.

### Exit Criteria

- [ ] The project has one explicit design for notification-linked priority playback and job triggering, with queue semantics that are documented and testable.
- [ ] The design makes clear whether the existing request queue was extended or a distinct playback queue was justified after review.
- [ ] The implementation path avoids unnecessary new layers and keeps playback, generation, and notification ownership easy to reason about.

## Milestone 18: Package Docs And Distribution Polish

### Status

In Progress

### Scope

- [ ] Keep package-facing documentation easy to navigate without making maintainers read the source tree first.
- [ ] Keep DocC, README, and Swift Package Index metadata aligned with the actual public package surface.
- [ ] Treat docs as product surface, not as a dumping ground for stale planning notes.

### Tickets

- [ ] Complete the remaining DocC gaps around playback control and runtime-level observation after the `RuntimeOverview` stream decision lands.
- [ ] Tighten package-consumer discovery around `SpeakSwiftly.Runtime`, concern handles, and request observation so the public API feels deliberate from package docs alone.
- [ ] Keep the text-profile docs aligned with the SpeakSwiftly-owned profile model family while still explaining where `TextForSpeech` remains the authored input type.
- [ ] Keep `.spi.yml` intentionally small and update it only when the public docs surface actually changes.
- [ ] Keep README, CONTRIBUTING, ROADMAP, and DocC aligned whenever playback semantics, shutdown behavior, request observation, or runtime ownership change.

### Exit Criteria

- [ ] A new consumer can navigate the main package API through the docs without relying on source spelunking.
- [ ] Swift Package Index has the minimal metadata it needs to render the package cleanly without stale or speculative configuration.
- [ ] Maintainer docs stay focused on current architecture and active plans instead of accumulated dead notes.

## Milestone 21: Unified Logging With `Logger`

### Status

Planned

### Scope

- [ ] Move package-owned operator diagnostics from ad-hoc stderr writes toward Apple's Unified Logging surface built around `Logger`.
- [ ] Preserve the current human-friendly, concrete diagnostic wording while making runtime logs easier to filter in Console, Instruments, and later log-store tooling.
- [ ] Keep the logging shape direct and local to the runtime instead of adding a wrapper-heavy logging abstraction.

### Tickets

- [ ] Inventory the current stderr logging surface and group it by subsystem, category, and intended audience before changing call sites.
- [ ] Define a small package logging layout using `Logger` with clear subsystem and category names for runtime lifecycle, playback, generation, profiles, persistence, and request observation.
- [ ] Replace direct runtime stderr writes with `Logger` call sites where Unified Logging is the right surface, while preserving stdout for JSONL protocol traffic.
- [ ] Decide which diagnostics should remain mirrored to stderr for parent-process operability during local worker runs, and make that mirroring policy explicit instead of accidental.
- [ ] Audit current message strings so migrated log lines still explain what failed, where it failed, and the most likely cause in concrete language.
- [ ] Use log levels intentionally instead of flattening everything to one severity.
- [ ] Add or tighten tests around the logging seam where practical, especially where the runtime currently depends on injected stderr writers for diagnostics assertions.
- [ ] Document how package logs are intended to be consumed locally with Console or other Unified Logging readers, and clarify which information remains on the JSONL contract versus the logging channel.

### Exit Criteria

- [ ] Package-owned operational diagnostics primarily flow through `Logger` with clear subsystem and category names.
- [ ] The JSONL worker contract remains stdout-only and easy to reason about, with logging clearly separated from protocol traffic.
- [ ] Operator-facing log messages remain specific, readable, and useful in Console as well as local debugging flows.

## Milestone 22: Marvis MLX Generation-Path Investigation And Playback Tuning

### Status

In Progress

### Scope

- [ ] Keep Marvis behavior simple enough that the runtime policy is easy to reason about and the remaining instability is attributable.
- [ ] Document whether the remaining Marvis rebuffers are mainly a local playback-policy issue or a throughput limitation in the current `mlx-audio-swift` generation path.
- [ ] Use the runtime's explicit playback and scheduler observability as the source of truth for each tuning or investigation pass.

### Tickets

- [ ] Compare the current `mlx-audio-swift` Marvis generation path against Marvis's own reference implementation surface and document differences in chunking, sampler usage, cache behavior, streaming cadence, and throughput expectations.
- [ ] Confirm whether `dual_resident_serialized` versus `single_resident_dynamic` changes real audible throughput enough to matter on Gale's Apple-silicon machines.
- [ ] Verify whether the queued-Marvis playback drain abort remains reproducible after the later playback-drain and cancellation hardening. ([#13](https://github.com/gaelic-ghost/SpeakSwiftly/issues/13))
- [ ] Record subjective audible outcomes and objective stderr metrics together after each meaningful Marvis runtime or upstream investigation pass.

### Stage Notes

- Earlier Milestone 22 work explored overlap-specific thresholds, cadence tweaks, and queue-admission changes in detail.
- The current 2026-04-22 steady state is intentionally simpler:
  - Marvis generation is serialized
  - the default resident policy is `dual_resident_serialized`
  - a benchmark now exists for `dual_resident_serialized` versus `single_resident_dynamic`
  - all live Marvis playback uses one conservative startup profile
  - the current live cadence matches the upstream Marvis `0.5s` path
- The current read after the latest audible runs is:
  - local overlap complexity was not the main problem
  - simplifying the runtime improved consistency, especially for later queued requests
  - even after that simplification, audible Marvis still tends to rebuffer
  - the next useful work is upstream and reference-path investigation, not rebuilding the old overlap model

### Exit Criteria

- [ ] The repository documents how the current `mlx-audio-swift` Marvis path differs from Marvis's reference implementation surface and what those differences imply for local playback behavior.
- [ ] Marvis audible playback is either measurably steadier after upstream-aware changes or explicitly documented as limited by the current MLX path.
- [ ] The repository has a documented before-and-after record for the simplified serialized policy and the follow-on upstream investigation.

## Milestone 26: Pre-v1 Release Hardening

### Status

In Progress

### Scope

- [ ] Finish the release-hardening pass needed before the first full `v1.0.0` release.
- [ ] Keep release mechanics concrete, repeatable, and observable from this repository alone.
- [ ] Make runtime publication and package-consumer expectations explicit enough that tagged releases are genuinely shippable.

### Tickets

- [ ] Resolve the remaining active milestones that define the stable public surface and release-operability story, especially package distribution, request observation, and playback-architecture cleanup.
- [ ] Verify downstream `SpeakSwiftlyServer` adoption separately before release after the Milestone 27 typed Swift API cleanup.
- [ ] Investigate why `QueueControlE2ETests` are much heavier than the other real-model E2E suites, including whether they apply undue resource pressure, unnecessary parallelization, or avoidable resident-model contention on maintainer machines. ([#47](https://github.com/gaelic-ghost/SpeakSwiftly/issues/47))
- [ ] Re-run the release checklist against the final tagged-candidate shape and tighten any remaining migration notes or operator guidance before `v1.0.0`.

### Exit Criteria

- [ ] Tagged releases are operationally self-explanatory for local consumers and package consumers.
- [ ] The package and worker surfaces are documented clearly enough that `v1.0.0` does not freeze accidental behavior.
- [ ] Release verification proves both package correctness and published-runtime correctness.

## Backlog Candidates

- No committed backlog sits outside the active milestones right now; open follow-ups are assigned to the milestone blocks above.

## History

### 2026-05-03 roadmap accuracy audit

- Milestone 20 was condensed out of Active Milestones because the runtime-owned request-event broker, `request(id:)`, `updates(for:)`, `generationEvents(for:)`, replay semantics, and lifecycle tests are now landed.
- Milestone 27 was condensed out of Active Milestones because the public API simplification shipped in PR #46 with queue-control ownership cleanup, SpeakSwiftly-owned text-profile return models, typed request kind and completion, canonical retained `GenerationJob` inspection, and polished `Voices.create(...)` labels.
- Milestone 13 no longer carries completed public-API-audit, semantic-identifier, `BatchItem`, or retained-generation-model decision tickets; those outcomes now live in `docs/maintainers/public-api-surface-audit-2026-05-02.md` and `docs/maintainers/milestone-27-migration-note.md`.
- Milestone 18 no longer carries completed retained-generation-model or typed request-completion DocC tickets; the active docs work is now narrowed to remaining playback-control, runtime-level observation, package-discovery, text-profile, and SPI-facing polish.
- Milestone 26 no longer repeats completed E2E artifact, CPU-accounting, runtime-publication, launcher, resource-lookup, or public-API-simplification tickets; the remaining release-hardening work is downstream adoption, queue-control E2E pressure, unresolved active milestones, and final release-candidate validation.
- Milestone 9 was corrected to acknowledge the existing `get_runtime_overview` / `runtime.overview()` inspection surface and now tracks the missing runtime-level playback or overview event stream separately in #45.
- Open GitHub issues #7, #13, #21, #45, and #47 are now assigned to active roadmap milestones so the roadmap and issue tracker describe the same outstanding work.

### 2026-04-18 release-history consolidation

These older release-prep and release-note docs were archived and removed as
standalone files because their durable roadmap-relevant outcomes are better
captured here than in a growing patch-by-patch document pile.

- `docs/releases/v3-0-5-release-prep.md`
  Result: the durable outcome was startup-playback cleanup plus a temporary
  Xcode-backed validation fallback while the vendored `EnglishG2P.swift`
  parser snag was still active.
- `docs/releases/v3-0-5-release-notes.md`
  Result: the durable outcome was playback-startup hardening and the
  `TextForSpeech` `0.17.0` uptake rather than a release-note surface worth
  preserving on its own.
- `docs/releases/v3-0-6-release-prep.md`
  Result: the durable outcome was the Chatterbox backend landing, runtime-owned
  chunked live playback for non-streaming synthesis, and the first cleanup pass
  that moved stale planning details into roadmap history.
- `docs/releases/v3-0-6-release-notes.md`
  Result: the durable outcome was one stable Chatterbox story in the package
  docs and active milestones, not a branch-specific release summary.
- `docs/releases/v3-0-7-release-prep.md`
  Result: the durable outcome was playback-drain waiter hardening for queued
  live playback and the explicit Swift 6 language-mode declaration in
  `Package.swift`.
- `docs/releases/v3-0-7-release-notes.md`
  Result: the durable outcome was playback cancellation safety and release-doc
  relocation completion, now reflected by the remaining docs layout rather than
  by keeping this note around.
- `docs/releases/v3-0-8-release-prep.md`
  Result: the durable outcome was `TextForSpeech` `0.17.1` uptake plus source
  and test layout cleanup that mirrors the feature-oriented package structure.
- `docs/releases/v3-0-8-release-notes.md`
  Result: the durable outcome was maintainability cleanup and dependency
  uptake, not a release-note surface that still needs to live separately.

Release-train summary that remains historically important:

- `v3.0.5` hardened startup playback behavior, stopped noisy pre-request
  playback environment observation, and picked up `TextForSpeech` `0.17.0`.
- `v3.0.6` landed Chatterbox as a first-class backend with runtime-owned
  chunked live playback over a non-streaming backend path.
- `v3.0.7` hardened playback-drain waiter cancellation and pinned the package
  explicitly to Swift 6 language mode.
- `v3.0.8` picked up `TextForSpeech` `0.17.1` and finished a feature-oriented
  playback and test-tree cleanup.
- The old temporary Xcode-backed e2e and package-test fallback belongs to this
  historical era, not the current default workflow. The current branch has
  since moved back to ordinary SwiftPM validation after the
  `mlx-audio-swift` parser fix and now uses one-suite-at-a-time wrapper scripts
  for worker-backed e2e coverage.

### 2026-04-15 playback architecture cleanup

- `Milestone 23` landed by flattening live playback request ownership around one runtime-owned `LiveSpeechRequestState` that survives from acceptance through terminal playback completion.
- `Milestone 24` landed by splitting playback execution mechanics into `PlaybackExecutionState` and `LiveSpeechPlaybackState`, keeping streamed audio and task ownership playback-local instead of request-local.
- `Milestone 25` landed by narrowing generation scheduling to a playback admission signal while keeping richer playback telemetry in runtime overview and diagnostics.
- Review outcome: keep the public `PlaybackState` surface thin for now, and treat buffering and rebuffer details as operator-facing playback telemetry rather than as a widened public state enum.
- Review hardening: `LiveSpeechRequestState` now fails immediately with a descriptive runtime-bug message if anything other than a live playback request tries to construct it.

### 2026-04-15 roadmap consolidation

These notes were archived and removed as standalone maintainer docs because they were either completed plans, superseded investigations, or low-level tuning logs whose durable outcomes now live in this roadmap and `CONTRIBUTING.md`.

- `docs/maintainers/textforspeech-split-plan.md`
  Result: the `TextForSpeech` split is functionally complete, and the remaining work is refinement rather than extraction.
- `docs/maintainers/worker-runtime-split-plan-2026-04-05.md`
  Result: the runtime split landed, with public API, playback, normalization, and runtime-extension breakouts now part of the source tree.
- `docs/maintainers/persisted-generation-jobs-and-batch-plan-2026-04-07.md`
  Result: persisted generation jobs and artifact records landed and now live as completed milestone history.
- `docs/maintainers/speech-text-normalizer-audit-2026-04-02.md`
  Result: the older `SpeechTextNormalizer`-centric audit is superseded by `TextForSpeech` ownership and the surviving maintainer note in `docs/maintainers/slices.md`.
- `docs/maintainers/audio-route-and-live-playback-investigation-2026-04-03.md`
  Result: route-change and engine-reconfiguration observations have been folded into the active playback-operability and playback-control milestones.
- `docs/maintainers/playback-metrics-review-2026-04-08.md`
  Result: the main lesson was to treat playback truth as controller-owned and to keep tuning grounded in trace metrics, now tracked in milestone 22 plus the completed playback-architecture cleanup history below.
- `docs/maintainers/queued-marvis-playback-state-review-2026-04-08.md`
  Result: the immediate controller-owned playback-state fix landed, the architecture cleanup landed, and the remaining follow-up is now first-request Marvis tuning.
- `docs/maintainers/playback-forensics-2026-04-02.md`
  Result: early playback-threshold and adaptive-buffer tuning logs are now historical context rather than active guidance.

### 2026-04-17 backend-planning cleanup

These notes were archived and removed as standalone maintainer docs because their durable outcomes now live in active milestones, current package docs, or the landed runtime implementation.

- `docs/maintainers/marvis-vs-qwen-cloning-plan-2026-04-07.md`
  Result: the surviving durable conclusion is already captured by milestone 16 and the current profile-routing docs: keep one public profile system and make backend-specific materialization a follow-up instead of a caller-facing split.
- `docs/maintainers/multi-backend-profile-plan-2026-04-07.md`
  Result: the package now has one stable logical profile story, backend-specific resident routing, and a narrower remaining follow-up around backend-aware stored materializations tracked in milestone 16.
- `docs/maintainers/qwen-base-default-migration-plan-2026-04-16.md`
  Result: the Qwen backend collapse and prepared-conditioning default already landed, so the remaining durable guidance now lives in `CONTRIBUTING.md`, package tests, and milestone 16 follow-up work.
- `docs/maintainers/v3-1-0-release-prep.md`
  Result: this unreleased branch note became stale once the Chatterbox follow-up work widened after the original backend-add pass. Fresh release-prep notes should be written against the final chosen tag instead of preserving misleading version-specific prep.
- `docs/maintainers/v3-1-0-release-notes.md`
  Result: these unreleased draft notes are superseded by the current branch state and should be recreated for the final chosen release tag instead of preserved as stale pseudo-history.

### Completed milestone history

- Milestones 0 through 3 established the package, JSONL worker contract, resident runtime, and on-demand voice-profile creation path.
- Milestone 5 hardened the contract and added opt-in real-model end-to-end coverage.
- Milestones 7 and 8 hardened playback and shutdown safety, then added grounded stderr observability.
- Basic playback control, queue inspection, and normalization-replacement management are now part of the package surface instead of future concepts.
- The typed Swift API breakout away from a kitchen-sink runtime surface landed, and the package now uses concern handles such as `generate`, `player`, `voices`, `normalizer`, `jobs`, and `artifacts`.
