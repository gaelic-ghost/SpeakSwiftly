# Project Roadmap

## Vision

- Build a small, reliable Swift worker executable that keeps MLX and Apple-runtime concerns isolated behind a simple process boundary.

## Product principles

- Keep the worker thin and concrete instead of layering it into a mini-framework.
- Prefer one boring process boundary over multiple internal coordinators or bridges.
- Make every operator-facing error and progress message readable and specific.
- Keep the resident backend path fast, predictable, and easy to reason about.
- Let `mlx-audio-swift` own model loading and generation whenever its existing API surface already fits.
- Keep voice profiles immutable once created; require explicit removal instead of silent overwrite.
- Keep playback, generation, normalization, and runtime ownership boundaries visible in both code and docs.

## Roadmap Shape

This roadmap now keeps active milestones and the current release-hardening queue in one place. Older completed plans, superseded investigations, and landing notes have been condensed into the history section so maintainer guidance stays readable instead of fragmenting across stale documents.

## Milestone Progress

- [x] Milestone 0: Bootstrap
- [x] Milestone 1: JSONL worker contract
- [x] Milestone 2: Resident runtime and live playback
- [x] Milestone 3: On-demand profile creation and profile store
- [ ] Milestone 4: File rendering and integration hardening
- [ ] Milestone 6: Multi-process profile-store hardening
- [ ] Milestone 9: Live-service operability review
- [x] Milestone 10: Basic playback control surface
- [x] Milestone 11: Basic queue inspection and clearing
- [x] Milestone 12: Basic custom normalization replacements
- [ ] Milestone 13: Swift package distribution
- [ ] Milestone 16: `mlx-audio-swift` upgrade review
- [ ] Milestone 17: Notification-linked priority playback
- [ ] Milestone 18: Package docs and distribution polish
- [ ] Milestone 20: Per-request event stream observability
- [ ] Milestone 21: Unified Logging with `Logger`
- [ ] Milestone 22: First-request Marvis playback tuning
- [x] Milestone 23: Playback request coordination flattening
- [x] Milestone 24: Playback execution ownership split
- [x] Milestone 25: Playback scheduling boundary and public state review
- [ ] Milestone 26: Pre-v1 release hardening

## Active Milestones

## Milestone 4: File Rendering And Integration Hardening

Scope:

- [ ] Make the worker straightforward to own from a parent process.
- [ ] Add the later resident file-rendering path for profile-based saved output.
- [ ] Harden logs, shutdown behavior, and repo validation where the file path differs from live playback.

Tickets:

- [ ] Add `generate_audio_file` parity coverage wherever the live path and saved-file path still diverge operationally.
- [ ] Keep the file-rendering path profile-based instead of exposing raw clone inputs.
- [ ] Tighten clean EOF and shutdown handling for long-lived worker ownership.
- [ ] Add tests for malformed input, missing profiles, duplicate profile creation, removal, and process-lifecycle edges that still differ between live and saved-output lanes.
- [ ] Keep packaging notes for parent-process ownership concrete and minimal.

Exit criteria:

- [ ] The worker exits cleanly on EOF or shutdown requests.
- [ ] Saved-file generation is operationally as predictable as live playback.
- [ ] Failure modes around malformed JSONL, profile storage, and filesystem issues are covered by tests.

## Milestone 6: Multi-Process Profile-Store Hardening

Scope:

- [ ] Make the on-disk profile store safe and predictable when multiple local processes use it at the same time.
- [ ] Preserve the current shared-store shape without adding unnecessary architecture around it.
- [ ] Keep profile creation, listing, loading, and removal human-readable when cross-process contention or stale state appears.

Tickets:

- [ ] Add cross-process coordination for profile creation and removal so concurrent workers cannot partially stomp each other.
- [ ] Keep profile writes atomic across manifest and reference-audio creation, including cleanup of abandoned temp data after failed writes.
- [ ] Make profile listing and loading resilient to in-flight writes from another process without producing misleading corruption failures.
- [ ] Add clear operator-facing diagnostics for lock contention, stale temp directories, and cross-process filesystem races.
- [ ] Add automated coverage for concurrent create/load/remove access against the shared profile root.
- [ ] Document the shared per-user default profile root and the override path for process-isolated profile stores.

Exit criteria:

- [ ] Two local processes can share the default profile store without silent corruption or partially written profiles.
- [ ] Cross-process profile creation and removal failures are explicit, structured, and recoverable.
- [ ] The shared-store behavior and override-based isolation path are documented clearly for downstream apps and services.

## Milestone 9: Live-Service Operability Review

Scope:

- [ ] Tighten the worker contract around service ownership and operational inspection for long-lived local deployments.
- [ ] Make filesystem behavior and service-state inspection predictable for parent processes.
- [ ] Make adjacent local consumer update flows explicit and reliable when standalone `SpeakSwiftly` releases are tagged.

Tickets:

- [ ] Revisit `output_path` resolution so relative paths cannot silently depend on the worker launch directory.
- [ ] Add a lightweight health and inspection surface for resident state, active request id, queue depth, profile root, and playback state without forcing log scraping.
- [ ] Make profile listing resilient to stray files, partial directories, and damaged entries without poisoning the full operation when recovery is possible.
- [ ] Add a first-class default-profile concept so downstream callers are not forced to treat names like `default-femme` as hidden conventions.
- [ ] Persist a little more voice-profile source provenance from creation flows so rerolls, diagnostics, and later profile introspection have stable grounding.
- [ ] Document the parent-process ownership expectations for startup warmup, health inspection, shutdown, and profile-root selection.
- [ ] Document the current tag-time runtime publication flow for adjacent consumers such as `speak-to-user-mcp` and `speak-to-user-server`, including what is automatic and what remains explicit follow-up.

Exit criteria:

- [ ] Parent processes can inspect worker state and reason about service health without log scraping alone.
- [ ] Path resolution and profile-store behavior are predictable across different launch environments.
- [ ] The standalone release workflow clearly describes which adjacent local consumers are updated automatically and which still require explicit follow-up.

## Milestone 13: Swift Package Distribution

Scope:

- [ ] Make `SpeakSwiftly` straightforward to consume as a real distributed Swift package instead of only as an adjacent local checkout.
- [ ] Clarify what public API and semver guarantees the package actually intends to support for downstream apps and services.
- [ ] Keep distribution work grounded in the existing package surface instead of adding unnecessary packaging layers or wrapper targets.

Tickets:

- [ ] Audit the `SpeakSwiftly` public API for the minimum supported downstream surface before advertising broader package distribution.
- [ ] Document SwiftPM dependency examples for both the library product and the executable product in the README.
- [ ] Add a package-consumer verification path that exercises dependency resolution from a clean external package instead of relying only on sibling-checkout integration.
- [ ] Decide whether package-registry publication is in scope or whether Git-based SwiftPM distribution is the intended first supported path.
- [ ] Tighten release notes and release-checklist language so package consumers can tell when a change is semver-safe versus when migration work is required.
- [ ] Document any remaining Xcode-built runtime caveats clearly so distributed package consumers understand where SwiftPM alone is sufficient and where it is not.
- [ ] Revisit whether `BatchItem` should remain a caller-authored public input type once `Generate` owns more shaping work.

Exit criteria:

- [ ] A downstream Swift package can adopt `SpeakSwiftly` through a documented supported distribution path without relying on repo-local adjacency assumptions.
- [ ] The supported package surface and migration expectations are explicit enough for semver-based consumption.
- [ ] Package distribution stays thin and concrete rather than accumulating extra compatibility wrappers.

## Milestone 16: `mlx-audio-swift` Upgrade Review

Scope:

- [ ] Review a newer `mlx-audio-swift` release or revision and decide whether `SpeakSwiftly` should adopt it.
- [ ] Keep the worker thin and direct while making dependency drift easier to reason about.
- [ ] Avoid wrapper-heavy compatibility architecture unless a real upstream API break makes it necessary.

Tickets:

- [ ] Compare the currently pinned `mlx-audio-swift` revision with the latest available tagged release or stable candidate.
- [ ] Review upstream changes to Qwen3 TTS defaults, generation controls, streaming behavior, and model-loading expectations for any impact on `SpeakSwiftly`.
- [ ] Preserve upstream `AudioGeneration` event detail through a first-class side-channel, trace stream, or equivalent logging surface instead of collapsing every resident generation path down to raw sample chunks at the first wrapper boundary.
- [ ] Evaluate whether the current resident backend defaults are still the right MLX choices on current Apple Silicon, and record the latency, memory, and audible tradeoffs explicitly.
- [ ] Generalize stored Qwen materializations so profiles can load backend-appropriate conditioning material without assuming one hard-coded shape forever.
- [ ] Re-run resident playback, profile-generation, and typed-library integration checks against a candidate upgrade in an isolated branch.
- [ ] Record any concrete reasons to upgrade, defer, or stay pinned, including behavior changes that affect playback stability or generation length.

Exit criteria:

- [ ] The repository documents whether a newer `mlx-audio-swift` should be adopted and why.
- [ ] Dependency policy around `mlx-audio-swift` is explicit enough that future playback or generation regressions are easier to trace.

## Milestone 17: Notification-Linked Priority Playback

Scope:

- [ ] Decide how callers can submit ordinary speech work plus separate notification-linked priority playback work without making the worker contract confusing.
- [ ] Review whether the existing request queue can absorb this feature cleanly or whether a distinct playback queue is truly necessary.
- [ ] Keep the design thin and concrete instead of introducing a new queue, manager, coordinator, or job subsystem unless the simpler extension path clearly fails.

Tickets:

- [ ] Define the minimum useful notification-linked job shape, including a normal speech job, a priority notification job, and a pre-generated straight-to-playback variant if that path is still justified after contract review.
- [ ] Decide whether priority playback should be modeled as new request kinds inside the existing queueing model or whether a separate playback queue is truly required.
- [ ] Document how priority jobs interact with active playback, waiting requests, pause or resume state, and future queue inspection or cancellation controls.
- [ ] Define whether Notification Center ownership lives inside `SpeakSwiftly`, in a parent process, or behind a narrow optional integration boundary.
- [ ] If notification clicks can trigger playback, define the stable identifier and persistence boundary for the associated speech job.
- [ ] Decide how pre-generated audio is stored, referenced, expired, and played back without duplicating the normal playback path unnecessarily.
- [ ] Add typed Swift library parity for submitting, inspecting, and triggering notification-linked priority jobs if this feature lands in the package surface.
- [ ] Add automated coverage for ordinary queued playback plus injected priority work, notification-linked playback triggering, and no-op behavior when referenced jobs are missing or already consumed.

Exit criteria:

- [ ] The project has one explicit design for notification-linked priority playback and job triggering, with queue semantics that are documented and testable.
- [ ] The design makes clear whether the existing request queue was extended or a distinct playback queue was justified after review.
- [ ] The implementation path avoids unnecessary new layers and keeps playback, generation, and notification ownership easy to reason about.

## Milestone 18: Package Docs And Distribution Polish

Scope:

- [ ] Keep package-facing documentation easy to navigate without making maintainers read the source tree first.
- [ ] Keep DocC, README, and Swift Package Index metadata aligned with the actual public package surface.
- [ ] Treat docs as product surface, not as a dumping ground for stale planning notes.

Tickets:

- [ ] Add first-class DocC guidance for runtime ownership, playback control, request observation, and voice-profile creation.
- [ ] Tighten package-consumer discovery around `SpeakSwiftly.Runtime`, concern handles, and request observation so the public API feels deliberate.
- [ ] Keep `.spi.yml` intentionally small and update it only when the public docs surface actually changes.
- [ ] Keep README, CONTRIBUTING, ROADMAP, and DocC aligned whenever playback semantics, shutdown behavior, request observation, or runtime ownership change.

Exit criteria:

- [ ] A new consumer can navigate the main package API through the docs without relying on source spelunking.
- [ ] Swift Package Index has the minimal metadata it needs to render the package cleanly without stale or speculative configuration.
- [ ] Maintainer docs stay focused on current architecture and active plans instead of accumulated dead notes.

## Milestone 20: Per-Request Event Stream Observability

Scope:

- [ ] Make per-request event streaming a first-class documented part of the Swift package surface instead of an incidental detail of `RequestHandle`.
- [ ] Add an explicit in-process per-request observation surface for callers that only have a request ID and need to reconnect later.
- [ ] Keep request correlation and event observation readable without forcing callers down into JSONL worker internals.

Tickets:

- [ ] Replace the current single-continuation request-stream bookkeeping with a runtime-owned per-request event broker that supports multiple in-process subscribers.
- [ ] Add a public `runtime.request(id:)` snapshot API for callers that need current per-request state before attaching to live updates.
- [ ] Add a public `runtime.updates(for:)` API for callers that only know a request ID and need on-demand in-process observation.
- [ ] Decide whether the new on-demand stream should replay a bounded recent window on attach or start at the live tail only, and make that behavior explicit in the API contract.
- [ ] Introduce a data-first per-request update payload that can represent terminal failure as data for late subscribers, while keeping `RequestHandle.events` source-compatible for existing callers.
- [ ] Audit `RequestHandle` and `RequestEvent` for missing lifecycle guarantees or mismatches between docs and implementation.
- [ ] Tighten tests around event ordering, terminal completion semantics, cancellation semantics, multiple subscribers, late subscribers, replay behavior, and stream teardown.
- [ ] Keep the in-process boundary explicit. This milestone does not promise durable cross-process subscriptions or persisted request-event history.

Implementation notes:

- Detailed design and sequencing live in `docs/maintainers/per-request-update-stream-plan-2026-04-09.md`.
- The preferred implementation shape is a runtime-owned request-event broker plus additive `request(id:)` and `updates(for:)` APIs, not a second ad-hoc observer map.

Exit criteria:

- [ ] The package documents one clear per-request observation story for Swift callers.
- [ ] In-process callers can reconnect to per-request state and live updates using only a request ID.
- [ ] Streamed request events and request snapshots have explicit lifecycle guarantees backed by tests.

## Milestone 21: Unified Logging With `Logger`

Scope:

- [ ] Move package-owned operator diagnostics from ad-hoc stderr writes toward Apple's Unified Logging surface built around `Logger`.
- [ ] Preserve the current human-friendly, concrete diagnostic wording while making runtime logs easier to filter in Console, Instruments, and later log-store tooling.
- [ ] Keep the logging shape direct and local to the runtime instead of adding a wrapper-heavy logging abstraction.

Tickets:

- [ ] Inventory the current stderr logging surface and group it by subsystem, category, and intended audience before changing call sites.
- [ ] Define a small package logging layout using `Logger` with clear subsystem and category names for runtime lifecycle, playback, generation, profiles, persistence, and request observation.
- [ ] Replace direct runtime stderr writes with `Logger` call sites where Unified Logging is the right surface, while preserving stdout for JSONL protocol traffic.
- [ ] Decide which diagnostics should remain mirrored to stderr for parent-process operability during local worker runs, and make that mirroring policy explicit instead of accidental.
- [ ] Audit current message strings so migrated log lines still explain what failed, where it failed, and the most likely cause in concrete language.
- [ ] Use log levels intentionally instead of flattening everything to one severity.
- [ ] Add or tighten tests around the logging seam where practical, especially where the runtime currently depends on injected stderr writers for diagnostics assertions.
- [ ] Document how package logs are intended to be consumed locally with Console or other Unified Logging readers, and clarify which information remains on the JSONL contract versus the logging channel.

Exit criteria:

- [ ] Package-owned operational diagnostics primarily flow through `Logger` with clear subsystem and category names.
- [ ] The JSONL worker contract remains stdout-only and easy to reason about, with logging clearly separated from protocol traffic.
- [ ] Operator-facing log messages remain specific, readable, and useful in Console as well as local debugging flows.

## Milestone 22: First-Request Marvis Playback Tuning

Scope:

- [ ] Improve the first live Marvis playback in a drained queue without collapsing the restored dual-lane generation scheduler back into blanket serialization.
- [ ] Keep playback tuning and scheduler correctness clearly separated so later regressions are easier to diagnose.
- [ ] Use the runtime's explicit playback and scheduler observability as the source of truth for each tuning pass.

Tickets:

- [x] Establish a repeatable tuning checklist for the first drained-queue Marvis playback using the existing queued-live Marvis E2E lane plus stderr scheduler and playback metrics.
- [x] Compare first-request startup-buffer targets, buffered-audio reserve, and rebuffer counts across at least one before-and-after capture for each tuning change.
- [ ] Keep the working Milestone 22 tradeoff explicit: smoother first audible response wins even if the first audible reply waits another 1 to 2 seconds before playback begins.
- [ ] Preserve queued-live Marvis overlap in principle, but allow the second lane to start a little later if that materially reduces first-request rebuffering.
- [ ] Take Milestone 22 one stage at a time: ship one bounded tuning pass, benchmark it, record what changed, then decide whether another pass should widen into resident warmup behavior.
- [ ] Investigate whether resident preload is too eager about preparing local playback hardware, especially the `startResidentPreload()` -> `playbackController.prepare(...)` path that rebuilds playback hardware before an active live request exists.
- [ ] Revisit warmup startup, low-water, and resume thresholds specifically for the first active Marvis playback request.
- [ ] Revisit Marvis resident streaming cadence only if buffer tuning alone cannot reduce first-request rebuffering.
- [ ] Keep the scheduler snapshot and lane-reservation logs aligned with any playback-tuning changes so queue truth stays obvious.
- [ ] Record subjective audible outcomes and objective stderr metrics together after each meaningful tuning pass.

Stage notes:

- Stage 1 landed on `2026-04-15` as a bounded first-request warmup-floor pass. The first drained live Marvis request now seeds higher warmup floors before playback begins:
  - compact: `startup 1440`, `low-water 640`, `resume 1700`
  - balanced: `startup 2320`, `low-water 1040`, `resume 2700`
- Baseline artifact: `.local/e2e-runs/2026-04-15T03-14-57Z-166e3f0f-284e-45f9-ab95-618a3ea71e5a-prequeued-jobs-drain-in-order`
- Stage 1 artifact: `.local/e2e-runs/2026-04-15T17-27-27Z-e8a7db8f-cc3e-44ee-8f35-65266fb949f4-prequeued-jobs-drain-in-order`
- For the first queued femme request, the measured before-and-after stderr metrics changed like this:
  - `time_to_preroll_ready_ms`: `2320` -> `3746`
  - `startup_buffered_audio_ms`: `1440` -> `2400`
  - `startup_buffer_target_ms` at playback start: `1381` -> `2320`
  - `rebuffer_event_count`: `5` -> `4`
  - `rebuffer_total_duration_ms`: `24279` -> `25188`
- The restored dual-lane queued-live overlap model stayed intact. The second Marvis lane remained parked on `waiting_for_playback_stability` until the first request reached the stronger preroll target, then resumed and paired cleanly with the first lane.
- Stage 1 improved the initial reserve and delayed second-lane admission as intended, but it did not make the first drained-queue playback materially steady enough yet. Milestone 22 stays open, and the next pass should bias toward earlier threshold hardening or resident cadence follow-up rather than rolling overlap back into blanket serialization.
- Stage 2 landed on `2026-04-15` as a bounded first-rebuffer hardening pass. The first drained live Marvis request now keeps its tuning profile active in adaptive recovery and no longer waits for rebuffer number two before applying rebuffer penalties.
- Stage 2 artifact: `.local/e2e-runs/2026-04-15T17-52-36Z-e575274b-31ec-486f-9ef7-50f080660f33-prequeued-jobs-drain-in-order`
- For the first queued femme request, the measured stage-one to stage-two stderr metrics changed like this:
  - `time_to_preroll_ready_ms`: `3746` -> `3810`
  - `startup_buffered_audio_ms`: `2400` -> `2400`
  - `rebuffer_event_count`: `4` -> `4`
  - `rebuffer_total_duration_ms`: `25188` -> `23991`
  - `longest_rebuffer_duration_ms`: `7041` -> `9399`
- The stage-two logs show the intended policy change actually taking effect. On the first active rebuffer, the resumed target rose from the stage-one `3282` range into the `3403` range, and the later repeated-rebuffer recovery ceiling stayed strong at `4980` instead of falling back toward the standard profile.
- Stage 2 is a real improvement, but still not a full fix. Total rebuffer time dropped by about `1.2s`, yet the first request still suffered four rebuffers and one longer recovery window. The next bounded pass should probably stay in the policy lane and target earlier distress reaction before the first rebuffer finishes growing, or widen into resident Marvis cadence only if that narrower pass still stalls out.

Exit criteria:

- [ ] The first drained-queue Marvis playback is measurably steadier than the current baseline.
- [ ] The restored dual-lane queued-live Marvis overlap model remains intact and verified.
- [ ] The repository has a documented before-and-after record for the tuning work that makes later regressions obvious.

## Milestone 26: Pre-v1 Release Hardening

Scope:

- [ ] Finish the release-hardening pass needed before the first full `v1.0.0` release.
- [ ] Keep release mechanics concrete, repeatable, and observable from this repository alone.
- [ ] Make runtime publication and package-consumer expectations explicit enough that tagged releases are genuinely shippable.

Tickets:

- [x] Persist real e2e worker stdout and stderr artifacts plus compact per-run summaries so memory and later CPU telemetry can be inspected after a run finishes.
- [x] Add CPU accounting to the retained real e2e run summaries through the same unprivileged process-accounting path used for current memory snapshots.
- [x] Enforce Debug and Release runtime publication and verification on tagged prereleases and final releases, not only through the local repo-maintenance release script.
- [x] Publish launcher scripts, stable runtime aliases, and manifest-first consumption helpers so local consumers stop reconstructing executable and `default.metallib` paths by hand.
- [x] Keep runtime resource lookup anchored to bundle or manifest reality instead of current-working-directory assumptions wherever published runtimes are consumed.
- [ ] Resolve the remaining active milestones that define the stable public surface and release-operability story, especially package distribution, request observation, and playback-architecture cleanup.
- [ ] Re-run the release checklist against the final tagged-candidate shape and tighten any remaining migration notes or operator guidance before `v1.0.0`.

Exit criteria:

- [ ] Tagged releases are operationally self-explanatory for local consumers and package consumers.
- [ ] The package and worker surfaces are documented clearly enough that `v1.0.0` does not freeze accidental behavior.
- [ ] Release verification proves both package correctness and published-runtime correctness.

## History

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

### Completed milestone history

- Milestones 0 through 3 established the package, JSONL worker contract, resident runtime, and on-demand voice-profile creation path.
- Milestone 5 hardened the contract and added opt-in real-model end-to-end coverage.
- Milestones 7 and 8 hardened playback and shutdown safety, then added grounded stderr observability.
- Basic playback control, queue inspection, and normalization-replacement management are now part of the package surface instead of future concepts.
- The typed Swift API breakout away from a kitchen-sink runtime surface landed, and the package now uses concern handles such as `generate`, `player`, `voices`, `normalizer`, `jobs`, and `artifacts`.
