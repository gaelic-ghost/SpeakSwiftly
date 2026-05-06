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
- [Milestone 16: `mlx-audio-swift` Upgrade Review](#milestone-16-mlx-audio-swift-upgrade-review)
- [Milestone 21: Unified Logging With `Logger`](#milestone-21-unified-logging-with-logger)
- [Milestone 22: Marvis MLX Generation-Path Investigation And Playback Tuning](#milestone-22-marvis-mlx-generation-path-investigation-and-playback-tuning)
- [Milestone 26: Pre-v1 Release Hardening](#milestone-26-pre-v1-release-hardening)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Milestone Progress

- Milestone 16: `mlx-audio-swift` Upgrade Review - In Progress
- Milestone 21: Unified Logging With `Logger` - Planned
- Milestone 22: Marvis MLX Generation-Path Investigation And Playback Tuning - In Progress
- Milestone 26: Pre-v1 Release Hardening - In Progress

## Active Milestones

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
- [ ] Re-run resident playback, profile-generation, and typed-library integration checks against a candidate upgrade in an isolated branch.
- [ ] Record any concrete reasons to upgrade, defer, or stay pinned, including behavior changes that affect playback stability or generation length.

### Exit Criteria

- [ ] The repository documents whether a newer `mlx-audio-swift` should be adopted and why.
- [ ] Dependency policy around `mlx-audio-swift` is explicit enough that future playback or generation regressions are easier to trace.

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

- [ ] Run and record Marvis resident-policy benchmark results for `dual_resident_serialized` versus `single_resident_dynamic` on target Apple-silicon machines.
- [ ] Verify whether the queued-Marvis playback drain abort remains reproducible after the later playback-drain and cancellation hardening. ([#13](https://github.com/gaelic-ghost/SpeakSwiftly/issues/13))
- [ ] If Marvis audible instability remains, identify whether it is upstream `mlx-audio-swift` throughput, wrapper behavior, local playback policy, or machine-specific pressure, and record the evidence.
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

- [ ] The repository records target-machine benchmark evidence for the resident policy choice instead of only noting that a harness exists.
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

- [ ] Resolve the remaining active milestones that define the stable public surface and release-operability story, especially logging migration and Marvis playback tuning.
- [ ] Verify downstream `SpeakSwiftlyServer` adoption separately before release after the Milestone 28 typed observation API cleanup.
- [ ] Re-run the release checklist against the final tagged-candidate shape and tighten any remaining migration notes or operator guidance before `v1.0.0`.

### Exit Criteria

- [ ] Tagged releases are operationally self-explanatory for local consumers and package consumers.
- [ ] The package and worker surfaces are documented clearly enough that `v1.0.0` does not freeze accidental behavior.
- [ ] Release verification proves both package correctness and published-runtime correctness.

## Backlog Candidates

- Notification-linked priority playback is a backlog candidate, not an active milestone. It should only return to Active Milestones after a current issue or implementation plan proves the package should own notification-triggered priority playback instead of leaving that concern to a parent app.

## History

### 2026-05-06 typed observation API cleanup

- Milestone 28 was condensed out of Active Milestones after the breaking typed Swift observation cleanup landed without compatibility shims. The public package surface now uses `RequestEvent` / `RequestState` / `RequestUpdate` / `RequestSnapshot`, per-request `SynthesisEvent` / `SynthesisUpdate`, generation-queue `GenerateEvent` / `GenerateState` / `GenerateUpdate` / `GenerateSnapshot`, singleton playback `PlaybackEvent` / `PlaybackState` / `PlaybackUpdate` / `PlaybackSnapshot`, and singleton runtime `RuntimeEvent` / `RuntimeState` / `RuntimeUpdate` / `RuntimeSnapshot`.
- The typed runtime handles now expose `runtime.generate`, `runtime.playback`, and `runtime` `updates()` plus `snapshot()` surfaces. Removed typed Swift names include `runtime.player`, `SpeakSwiftly.Player`, `GenerationEvent`, `GenerationEventUpdate`, `runtime.status()`, `runtime.overview()`, `Player.list()`, `Player.state()`, and `runtime.statusEvents()`.
- JSONL worker compatibility remains intentionally stable for `worker_status`, `get_runtime_overview`, and existing playback-state response shapes. Internal `WorkerStatusEvent`, `WorkerRuntimeOverview`, and `WorkerPlaybackStateSnapshot` models preserve the wire contract while public typed Swift consumers use the new observation vocabulary.
- DocC, `CONTRIBUTING.md`, `AGENTS.md`, maintainer API-audit notes, and `v5.0.0` migration notes were updated in the same pass. Downstream `SpeakSwiftlyServer` adoption remains explicit release-hardening work under Milestone 26.

### 2026-05-03 TextForSpeech 0.19 simplification

- Milestone 27 was condensed out of Active Milestones after the `TextForSpeech` `0.19.0` simplification landed on the `v5.0.0-rc.1` release-candidate branch. The package now uses `TextForSpeech.SourceFormat` directly only for whole-source generation, carries request metadata and path context through `SpeakSwiftly.RequestContext`, and removes the public `SpeakSwiftly.InputTextContext` typed surface.
- The current JSONL generation wire shape uses `source_format` for whole-source input and `request_context` for request metadata and path context. Removed generation-context keys such as `input_text_context`, `text_format`, and `nested_source_format` are rejected with an explicit invalid-request diagnostic instead of being silently ignored.
- The old `v5.0.0-rc.1` release-candidate notes were later consolidated into `docs/releases/release-history.md`; the stale standalone Milestone 27 migration note and superseded `v4.1.0` draft release docs were removed.
- Downstream adoption, especially `SpeakSwiftlyServer`, remains release-hardening work under Milestone 26 so this package does not carry temporary compatibility shims while consumers move to the current surface.

### 2026-05-03 Milestone 9 closeout

- Milestone 9 was condensed out of Active Milestones after the default-profile work landed as a deliberately small API: `runtime.defaultVoiceProfile`, `runtime.setDefaultVoiceProfile(_:)`, optional `voiceProfile:` on generation calls, JSONL generation fallback when `voice_profile` is omitted, and the built-in `swift-signal` fallback. At that time, the proposed runtime overview stream from #45 was rejected because it did not yet have a clean package-wide observation vocabulary. The later Milestone 28 plan reopens typed Swift runtime observation as part of an across-the-board `Event` / `State` / `Update` / `Snapshot` cleanup instead of as a one-off overview stream.
- Milestone 18 was condensed out of Active Milestones because the remaining package-docs work depended on the then-closed #45 decision. The later Milestone 28 plan owns the next typed observation documentation cleanup.

### 2026-05-03 full roadmap active-item audit

- Milestone 4 was condensed out of Active Milestones after auditing retained generated-file E2E coverage, generated-batch E2E coverage, worker EOF handling, shutdown cancellation behavior, malformed JSONL handling, and profile-store failure coverage. No current file-rendering or worker-ownership gap remained specific enough to justify an active milestone.
- Milestone 9 was narrowed during this audit to the live-service items that still appeared backed by open evidence at the time: #45 for runtime-level playback and overview streaming, #7 for the startup-side allocator-warning investigation, and the still-missing first-class default-profile concept. That narrowing was later closed out in the 2026-05-03 Milestone 9 closeout entry above.
- Milestone 13 was condensed out of Active Milestones after a second audit confirmed the package already has SemVer Git tags, GitHub SwiftPM dependency documentation, `.spi.yml`, a live Swift Package Index page, and a real adjacent Swift package consumer in `SpeakSwiftlyServer` using `https://github.com/gaelic-ghost/SpeakSwiftly.git` from `4.2.0`.
- Milestone 17 was moved out of Active Milestones because notification-linked priority playback has no current issue, implementation branch, or package-ownership decision. It remains a backlog candidate only.
- Milestone 18 was narrowed during this audit to documentation work that depended on still-open runtime observation decisions. That remaining docs work was later closed out in the 2026-05-03 Milestone 9 closeout entry above.
- Milestone 22 was narrowed to the Marvis work that still needs fresh target-machine evidence: resident-policy benchmark results, #13 reproduction or closure, and an evidence-backed decision about whether remaining instability belongs to upstream generation throughput, local wrapper behavior, playback policy, or machine pressure. The completed Marvis-reference comparison no longer appears as open active work.
- Milestone 16 no longer tracks clone auto-transcription as active because clone transcript inference now lives in the shared clone-profile creation path and has Qwen plus Chatterbox E2E coverage for provided and inferred transcripts.

### 2026-05-03 roadmap accuracy audit

- Milestone 6 was condensed out of Active Milestones because the multi-process profile-store hardening landed across PRs #52 through #55: profile listing skips stray, partial, hidden staged, and corrupt entries; profile writes use a per-root advisory lock; profile creation and replacement publish staged data only after complete writes; manifest, reference-audio, and Qwen-conditioning writes use atomic file writes; lock contention now reports a bounded stuck-writer diagnostic; concurrent create, load, remove, and duplicate-create coverage is in place; and `CONTRIBUTING.md` documents the shared default state root plus `stateRootURL`, `--state-root`, and `SPEAKSWIFTLY_STATE_ROOT` isolation paths.
- Milestone 26 no longer tracks queue-control E2E pressure as active release-hardening work because #47 closed after PR #49 reduced that suite's pressure while preserving its coverage intent.
- Milestone 20 was condensed out of Active Milestones because the runtime-owned request-event broker, `request(id:)`, `updates(for:)`, the then-current `generationEvents(for:)` synthesis-event side channel, replay semantics, and lifecycle tests had landed. The later Milestone 28 cleanup renamed that typed side channel to `synthesisUpdates(for:)`.
- Milestone 27 was condensed out of Active Milestones because the public API simplification shipped in PR #46 with queue-control ownership cleanup, SpeakSwiftly-owned text-profile return models, typed request kind and completion, canonical retained `GenerationJob` inspection, and polished `Voices.create(...)` labels.
- Milestone 13 no longer carries completed public-API-audit, semantic-identifier, `BatchItem`, or retained-generation-model decision tickets; those outcomes now live in `docs/maintainers/public-api-surface-audit-2026-05-02.md` and the `v5.0.0-rc.1` release-candidate notes.
- Milestone 18 no longer carried completed retained-generation-model or typed request-completion DocC tickets after this audit; the later Milestone 9 closeout removed its remaining active docs work.
- Milestone 26 no longer repeats completed E2E artifact, CPU-accounting, runtime-publication, launcher, resource-lookup, queue-control E2E pressure, or public-API-simplification tickets; the remaining release-hardening work is downstream adoption, unresolved active milestones, and final release-candidate validation.
- Milestone 9 was corrected during this audit to acknowledge the existing `get_runtime_overview` / `runtime.overview()` inspection surface and to track the proposed runtime-level playback or overview event stream separately in #45. The later Milestone 9 closeout rejected that stream as API bloat.
- Open GitHub issues #7, #13, and #45 were assigned to active roadmap milestones during this audit so the roadmap and issue tracker described the same outstanding work at that time. The later Milestone 9 closeout removes #7 and #45 from active roadmap work.

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
- The typed Swift API breakout away from a kitchen-sink runtime surface landed, and the package now uses concern handles such as `generate`, `playback`, `voices`, `normalizer`, `jobs`, and `artifacts`.
