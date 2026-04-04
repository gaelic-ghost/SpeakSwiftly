# Project Roadmap

## Vision

- Build a small, reliable Swift worker executable that keeps MLX and Apple-runtime concerns isolated behind a simple process boundary.

## Product principles

- Keep the worker thin and concrete instead of layering it into a mini-framework.
- Prefer one boring process boundary over multiple internal coordinators or bridges.
- Make every operator-facing error and progress message readable and specific.
- Keep the resident `0.6B` path fast, predictable, and easy to reason about.
- Let `mlx-audio-swift` own model loading and generation whenever its existing API surface already fits.
- Keep voice profiles immutable once created; require explicit removal instead of silent overwrite.

## Milestone Progress

- [x] Milestone 0: Bootstrap
- [x] Milestone 1: JSONL worker contract
- [x] Milestone 2: Resident `0.6B` runtime
- [x] Milestone 3: On-demand `1.7B` VoiceDesign path
- [ ] Milestone 4: Integration hardening
- [ ] Milestone 5: Contract and e2e hardening
- [ ] Milestone 6: Multi-process profile-store hardening
- [x] Milestone 7: Playback and shutdown safety hardening
- [x] Milestone 8: Observability and instrumentation
- [ ] Milestone 9: Live-service operability review
- [ ] Milestone 10: Playback control surface
- [ ] Milestone 11: Queue inspection and clear endpoint
- [ ] Milestone 12: Custom normalization replacements
- [ ] Milestone 13: Swift package distribution
- [ ] Milestone 14: Contract naming and terminology alignment
- [ ] Milestone 15: Package structure and breakout planning
- [ ] Milestone 16: `mlx-audio-swift` upgrade review
- [ ] Milestone 17: Notification-linked priority playback

## Milestone 0: Bootstrap

Scope:

- [x] Create the Swift executable package scaffold.
- [x] Establish Swift Testing as the default test framework.
- [x] Add grounded `README.md` and `ROADMAP.md` files.

Tickets:

- [x] Bootstrap the package in `/Users/galew/Workspace/SpeakSwiftly`.
- [x] Replace the generated XCTest stub with Swift Testing.
- [x] Document the intended resident `0.6B` and on-demand `1.7B` split.

Exit criteria:

- [x] `swift build` passes.
- [x] `swift test` passes.
- [x] The repo explains the intended worker contract clearly enough for the next implementation pass.

## Milestone 1: JSONL worker contract and queue

Scope:

- [x] Define the first request, progress-event, success, and failure message shapes.
- [x] Define preload-aware status events and a single-consumer priority request queue.

Tickets:

- [x] Write the first `stdin` read loop and `stdout` JSONL encoder.
- [x] Add request decoding and terminal response encoding.
- [x] Add a single-consumer playback-prioritized queue for incoming requests.
- [x] Add structured status and progress events for preload, queueing, request start, and terminal completion.
- [x] [P] Add tests for decoding and encoding the JSONL contract.

Exit criteria:

- [x] The executable can stay alive, accept requests, queue them deterministically, and emit deterministic JSONL responses.
- [x] Protocol errors are human-readable and unambiguous.

## Milestone 2: Resident `0.6B` runtime and live playback

Scope:

- [x] Pre-warm the `Qwen3-TTS 0.6B` model at worker startup.
- [x] Keep the resident model alive for live playback requests that select a stored profile by name.
- [x] Own audio playback inside this executable.

Tickets:

- [x] Add startup warmup flow for the resident model.
- [x] Accept requests during warmup and emit queue status that explains the model is still loading.
- [x] Emit a status event when the resident model finishes loading and queued work begins.
- [x] Add `speak_live` request handling around the resident path.
- [x] Pipe streamed audio into AVFoundation playback owned by this process.
- [x] Emit progress updates during resident-model generation, buffering, and playback.
- [x] Validate resident-model failure reporting when warmup or inference breaks.

Exit criteria:

- [x] The worker warms the resident model once at startup.
- [x] `speak_live` requests do not reload the resident model each time.
- [x] Live playback is owned by this executable rather than the parent process.
- [x] Startup and runtime failures clearly explain the most likely cause.

## Milestone 3: On-demand `1.7B` profile creation and profile store

Scope:

- [x] Support immutable stored voice-profile creation with `Qwen3 VoiceDesign 1.7B`.
- [x] Keep the resident `0.6B` model loaded while `1.7B` profile creation work runs.
- [x] Add profile storage, lookup, listing, and removal.

Tickets:

- [x] Add request handling for `create_profile`.
- [x] Add request handling for `remove_profile`.
- [x] Add request handling for `list_profiles`.
- [x] Load the `1.7B` model on demand.
- [x] Generate a reference audio file plus stored source text for each created profile.
- [x] Store profile metadata and assets on disk under immutable profile names.
- [x] Reject duplicate profile names instead of overwriting them.
- [x] Release the `1.7B` model after request completion.
- [x] Add validation around profile names, input text, output paths, and request failures.

Exit criteria:

- [x] `create_profile` requests produce stored immutable profiles through the on-demand path.
- [x] Stored profiles are selectable by name for resident `0.6B` playback.
- [x] The worker does not keep the `1.7B` model resident after the request completes.
- [x] Progress and failure output stay structured and readable.

## Milestone 4: File rendering and integration hardening

Scope:

- [ ] Make the worker straightforward to own from a parent process.
- [ ] Add the later `0.6B` file-rendering path for batch-capable profile-based output.
- [ ] Harden logs, shutdown behavior, and repo validation.

Tickets:

- [ ] Add `render_file` request handling around resident `0.6B`.
- [ ] Keep the file-rendering path profile-based instead of exposing raw clone inputs.
- [ ] Add clean EOF and shutdown handling for the worker loop.
- [ ] Add tests for malformed input, missing profiles, duplicate profile creation, removal, and process-lifecycle edges.
- [ ] Add any minimal packaging notes needed for parent-process ownership.

Exit criteria:

- [ ] The worker exits cleanly on EOF or shutdown requests.
- [ ] The later file-rendering path can write audio files with a selected stored profile.
- [ ] Failure modes around malformed JSONL, profile storage, and filesystem issues are covered by tests.
- [ ] Parent-process integration expectations are documented without adding unnecessary architecture.

## Milestone 5: Contract and e2e hardening

Scope:

- [x] Make the documented queue contract match the implemented playback-priority scheduler.
- [x] Tighten worker error mapping for broken stored-profile metadata.
- [x] Add opt-in real-model e2e coverage for both model paths.
- [ ] Add the remaining runtime and diagnostics assertions that are still missing from the fast test suite.

Tickets:

- [x] Replace lingering FIFO wording with playback-priority wording in the docs.
- [x] Ensure queued events are emitted only for requests that actually wait.
- [x] Make `list_profiles` corrupt-manifest failures surface as `filesystem_error`.
- [x] Add runtime tests for immediate-start requests, queued-event semantics, and filesystem failure mapping.
- [x] Add an opt-in serialized Swift Testing e2e suite gated by `SPEAKSWIFTLY_E2E=1`.
- [x] Add real `create_profile` and `speak_live` subprocess e2e coverage using isolated profile storage.
- [x] Add a silent live-playback e2e mode so the real worker path can be exercised without audible output.
- [x] Add a real non-silent `speak_live` e2e that exercises the local `AVAudioEngine` playback path and its stderr playback diagnostics.
- [x] Add assertions for operator-facing `stderr` diagnostics in the automated test suite.
- [x] Add a stronger automated check that a real non-`nil` reference-audio object reaches the resident generation path in fast tests without making the unit suite depend on MLX runtime initialization.

Exit criteria:

- [x] The docs describe the real playback-priority queue instead of FIFO behavior.
- [x] Immediate-start requests do not emit misleading queued events.
- [x] Corrupt stored-profile manifests returned through `list_profiles` surface as `filesystem_error`.
- [x] Opt-in serialized real-model e2e coverage exists for both the `1.7B` profile-creation path and the resident `0.6B` live path.
- [x] The fast test suite also covers the remaining profile-conditioning edge assertions.

## Milestone 6: Multi-process profile-store hardening

Scope:

- [ ] Make the on-disk profile store safe and predictable when multiple local processes use it at the same time.
- [ ] Preserve the current simple shared store shape without adding unnecessary architecture around it.
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

## Milestone 7: Playback and shutdown safety hardening

Scope:

- [x] Make stuck playback and drain completion failures visible, bounded, and recoverable.
- [x] Make worker shutdown deterministic when requests are in flight.
- [x] Keep the current simple single-actor shape without adding unnecessary service layers.

Tickets:

- [x] Add an explicit timeout or other bounded completion strategy around playback drain after streaming input finishes.
- [x] Distinguish generated-audio completion from local-player drain completion in both code paths and diagnostics.
- [x] Track the active request task so shutdown can cancel or finish it intentionally instead of orphaning it.
- [x] Define and implement the exact terminal behavior for in-flight requests during shutdown, including operator-facing diagnostics.
- [x] Add automated coverage for stuck playback-drain, cancelled shutdown, and in-flight request teardown paths.

Exit criteria:

- [x] A stalled playback callback cannot wedge the worker indefinitely without a clear failure path.
- [x] Worker shutdown is deterministic and observable even with active playback or profile-generation work in progress.
- [x] The runtime safety behavior is covered by automated tests and readable diagnostics.

## Milestone 8: Observability and instrumentation

Scope:

- [x] Add grounded operator-facing logs and timing signals so live-service behavior is explainable from stderr alone.
- [x] Keep stdout reserved for the JSONL worker contract while making stderr useful for debugging and production support.
- [x] Add only the minimum instrumentation needed to understand latency, queueing, and failure modes clearly.

Tickets:

- [x] Add request lifecycle timing logs for accept, queue, start, first audio chunk, playback finish, terminal success, and terminal failure.
- [x] Include request id, operation name, relevant profile name, queue depth, and elapsed time in operator-facing runtime logs.
- [x] Add resident-model preload instrumentation for start time, finish time, duration, model repo, and failure classification.
- [x] Add playback instrumentation for profile-load time, time to first generated chunk, time from first chunk to drain, and generated chunk or sample counts.
- [x] Add playback queue-depth instrumentation so low-buffer and starvation conditions are visible in stderr logs.
- [x] Add profile-store instrumentation for create, load, list, remove, and export with concrete filesystem paths.
- [x] Add automated assertions for important stderr diagnostics in the fast test suite.

Exit criteria:

- [x] A live-service latency complaint can be broken down into warmup, queueing, generation, playback, and filesystem phases from existing logs.
- [x] Operator-facing diagnostics contain enough context to identify the request, profile, path, and likely failure point without attaching a debugger.
- [x] The JSONL contract remains clean while stderr becomes a trustworthy operational signal.

## Milestone 9: Live-service operability review

Scope:

- [ ] Tighten the worker contract around service ownership and operational inspection for long-lived local deployments.
- [ ] Make filesystem behavior and service-state inspection predictable for parent processes.
- [ ] Make adjacent local consumer update flows explicit and reliable when standalone `SpeakSwiftly` releases are tagged.
- [ ] Preserve the current direct architecture and avoid adding wrappers or coordinators unless they are clearly necessary.

Tickets:

- [ ] Revisit `output_path` resolution so relative paths cannot silently depend on the worker launch directory.
- [ ] Make profile listing resilient to stray files, partial directories, and damaged entries without poisoning the full operation when recovery is possible.
- [ ] Add a first-class default-profile concept so downstream callers are not forced to treat names like `default-femme` as implicit conventions.
- [ ] Investigate automatic audio-route and output-device change handling for live playback, including headphones, AirPods, and macOS default-output switches, and decide whether `SpeakSwiftly` should observe route-change or hardware-change notifications and rebuild or retarget the playback engine when those changes occur.

## Milestone 16: `mlx-audio-swift` upgrade review

Scope:

- [ ] Review a newer `mlx-audio-swift` release or revision soon and decide whether `SpeakSwiftly` should adopt it.
- [ ] Keep the worker thin and direct while making dependency drift easier to reason about.
- [ ] Avoid wrapper-heavy “compatibility” architecture unless a real upstream API break makes it necessary.

Tickets:

- [ ] Compare the currently pinned `mlx-audio-swift` revision with the latest available tagged release or stable candidate.
- [ ] Review upstream changes to Qwen3 TTS defaults, generation controls, streaming behavior, and model-loading expectations for any impact on `SpeakSwiftly`.
- [ ] Re-run the resident playback, profile-generation, and typed-library integration checks against a candidate upgrade in an isolated branch.
- [ ] Record any concrete reasons to upgrade, defer, or stay pinned, including behavior changes that affect playback stability or generation length.
- [ ] If the upgrade is adopted, pin to an explicit stable revision or release instead of a moving branch tip.

Exit criteria:

- [ ] The repository documents whether a newer `mlx-audio-swift` should be adopted and why.
- [ ] Dependency policy around `mlx-audio-swift` is explicit enough that future playback or generation regressions are easier to trace.
- [ ] Add a lightweight worker `status` operation or equivalent health/introspection surface for resident state, active request id, queue length, profile root, and playback-drain state.
- [ ] Document the parent-process ownership expectations for startup warmup, health inspection, shutdown, and profile-root selection.
- [ ] Add an explicit qualitative runtime review checklist for future live-service passes so regressions in operability stay visible.
- [ ] Explore turning the new playback and text forensics into a user-side machine calibration path that can learn text-length-to-audio-duration behavior on specific hardware and seed hardware-matched buffering profiles for common machines.
- [ ] Use the richer playback observability to separate generation jitter, scheduling jitter, queue collapse, and chunk-boundary discontinuity before retuning cadence or DSP behavior again.
- [ ] Revisit chunk-boundary discontinuity and pop reduction after the adaptive buffering work is stable enough that buffering no longer dominates audible defects.
- [ ] Document the current tag-time cached-binary refresh into `../speak-to-user-mcp`, including when it runs, what it updates, and what it intentionally does not cover yet.
- [ ] Expand the adjacent-repo release propagation workflow so other local binary consumers such as `../speak-to-user-server` can be updated intentionally from the same standalone release process instead of drifting silently.

Exit criteria:

- [ ] Parent processes can inspect worker state and reason about service health without log scraping alone.
- [ ] Path resolution and profile-store behavior are predictable across different launch environments.
- [ ] The standalone release workflow clearly describes which adjacent local consumers are updated automatically and which still require explicit follow-up.
- [ ] The worker stays small and concrete while becoming easier to operate as a long-lived local service.

## Milestone 10: Playback control surface

Scope:

- [ ] Add a small, explicit playback-control surface for long-lived worker owners.
- [ ] Make active-playback interruption and lifecycle observation predictable from both the executable and `SpeakSwiftlyCore`.
- [ ] Preserve the current thin worker shape instead of turning playback control into a manager or coordinator layer.

Tickets:

- [x] Define the minimum playback control operations that are actually worth owning around `playback_pause`, `playback_resume`, and `playback_state`, and keep the contract narrow instead of growing a generic command surface.
- [ ] Define typed `SpeakSwiftlyCore` API parity for playback control requests and events instead of forcing library callers back through ad-hoc JSONL handling.
- [ ] Decide and document whether a stop request only interrupts the active request or can also affect queued playback requests.
- [ ] Emit structured lifecycle output for control acceptance, playback interruption, and terminal request state so parent processes can reason about what happened without guessing.
- [ ] Add runtime coverage for `playback_pause`, `playback_resume`, and `playback_state`, including no-op state transitions when nothing is currently playing and explicit state payload assertions for idle, paused, and resumed playback.
- [ ] Add automated coverage for active `speak_live` interruption, background-playback interruption, and control requests that must not disturb queued playback ownership when they only target the active request.
- [ ] Document the control semantics clearly in the README once the contract is real.

Exit criteria:

- [ ] A parent process can intentionally interrupt active playback through a documented worker operation and the equivalent typed library path.
- [ ] Control requests have clear, structured success and failure semantics instead of ambiguous side effects.
- [ ] The playback-control design stays narrow and concrete rather than growing extra wrapper layers.

## Milestone 11: Queue inspection and clear endpoint

Scope:

- [ ] Add a first-class queue inspection and queue-clearing surface for worker owners.
- [ ] Make queued-request state visible without forcing downstream apps to scrape logs or reconstruct queue state from partial event history.
- [ ] Keep queue operations explicit and bounded so the worker does not grow into an unnecessary job-management subsystem.

Tickets:

- [ ] Add a lightweight queue-inspection operation that reports the active request id, queued request ids, queue length, and enough operation metadata for an owner process to explain what is waiting.
- [ ] Add an explicit `clear_queue` operation that removes waiting requests without interrupting the currently active request unless a separate control request says otherwise.
- [ ] Define how cleared requests surface terminal failure or cancellation output so callers can distinguish queue removal from playback or generation failure.
- [ ] Add typed `SpeakSwiftlyCore` parity for queue inspection and clearing instead of exposing those behaviors only through raw JSONL.
- [ ] Add coverage for the accepted live-speech queue bound so the ninth accepted job is rejected clearly and capacity reopens after playback drain, cancellation, or queue clearing.
- [ ] Add automated coverage for clearing an empty queue, clearing multiple waiting requests, and clearing while active playback continues.
- [ ] Document the queue-inspection and queue-clearing semantics in the README once the contract exists.

Exit criteria:

- [ ] A parent process can inspect waiting work and intentionally clear queued requests through a documented worker operation and the equivalent typed library path.
- [ ] Cleared requests terminate with explicit structured output that identifies queue removal rather than a generic runtime failure.
- [ ] Queue operations remain small, readable, and bounded instead of becoming a sprawling control layer.

## Milestone 12: Custom normalization replacements

Scope:

- [ ] Add a first-class custom replacement surface for speech-text normalization.
- [ ] Let worker owners inspect, add, remove, and clear replacement rules without hard-coding all normalization behavior into the executable.
- [ ] Keep the normalization system concrete and readable instead of turning it into an over-abstracted plugin or rule-engine layer.

Tickets:

- [ ] Define the smallest useful replacement-rule shape, likely simple exact-match and phrase-replacement entries before considering broader pattern support.
- [ ] Decide and document rule precedence between built-in normalization passes and custom replacement rules so downstream callers can predict the final spoken text.
- [ ] Add worker operations for listing normalization replacements, adding or updating a replacement, removing a replacement, and clearing all custom replacements.
- [ ] Add typed `SpeakSwiftlyCore` parity for normalization-replacement management instead of exposing those behaviors only through raw JSONL.
- [ ] Decide whether replacement rules are process-local, profile-store-local, or shared per-user state, and document the persistence boundary explicitly.
- [ ] Emit structured success and failure output for replacement-rule mutations so callers can distinguish validation failures, duplicate-key behavior, and filesystem errors.
- [ ] Add automated coverage for replacement listing, add/update, remove, clear, and precedence behavior against the built-in normalization pipeline.
- [ ] Document the normalization-replacement semantics and examples in the README once the contract exists.

Exit criteria:

- [ ] A parent process can inspect and manage custom normalization replacements through documented worker operations and the equivalent typed library path.
- [ ] Replacement behavior is predictable, test-covered, and explicit about precedence and persistence.
- [ ] The normalization surface stays thin and understandable instead of growing into a generic rules framework.

## Milestone 13: Swift package distribution

Scope:

- [ ] Make `SpeakSwiftly` straightforward to consume as a real distributed Swift package instead of only as an adjacent local checkout.
- [ ] Clarify what public API and semver guarantees the package actually intends to support for downstream apps and services.
- [ ] Keep distribution work grounded in the existing package surface instead of adding unnecessary packaging layers or wrapper targets.

Tickets:

- [ ] Audit the `SpeakSwiftlyCore` public API for the minimum supported downstream surface before advertising broader package distribution.
- [ ] Document SwiftPM dependency examples for both the library product and the executable product in the README.
- [ ] Add a package-consumer verification path that exercises dependency resolution from a clean external package instead of relying only on sibling-checkout integration.
- [ ] Decide whether package-registry publication is in scope or whether Git-based SwiftPM distribution is the intended first supported path.
- [ ] Tighten release notes and release-checklist language so package consumers can tell when a change is semver-safe versus when migration work is required.
- [ ] Document any remaining Xcode-built runtime caveats clearly so distributed package consumers understand where SwiftPM alone is sufficient and where it is not.

Exit criteria:

- [ ] A downstream Swift package can adopt `SpeakSwiftlyCore` through a documented supported distribution path without relying on repo-local adjacency assumptions.
- [ ] The supported package surface and migration expectations are explicit enough for semver-based consumption.
- [ ] Package distribution stays thin and concrete rather than accumulating extra compatibility wrappers.

## Milestone 14: Contract naming and terminology alignment

Scope:

- [ ] Decide distinct, durable naming conventions for the stdio JSONL contract and the Swift library surface.
- [ ] Choose one consistent terminology set for queueing, playback, control, and lifecycle states.
- [ ] Keep the naming pass concrete and shim-free unless Gale explicitly approves a compatibility layer.

Tickets:

- [ ] Audit the current stdio/JSONL operation names, event names, and response fields for consistency.
- [ ] Audit the current Swift library entry points and request-handle naming for consistency with the worker contract.
- [ ] Decide and document the final terminology for queue entries, active requests, playback sessions, and control operations.
- [ ] Identify any naming mismatches that should be corrected before the package surface is treated as stable.
- [ ] Document the chosen naming rules without flattening the existing document structure.

Exit criteria:

- [ ] The project has one documented naming policy for stdio/JSONL and one documented naming policy for the Swift library surface.
- [ ] Queueing, playback, and control terms are used consistently across code, docs, tests, and operator-facing logs.
- [ ] Any remaining naming mismatches are either fixed or explicitly tracked as conscious follow-up work.

## Milestone 15: Package structure and breakout planning

Scope:

- [ ] Decide the intended final folder and file structure for the package as the future scope solidifies.
- [ ] Chart likely future breakouts without prematurely forcing them into extra targets, wrappers, or coordinators.
- [ ] Keep the structure plan grounded in the real package surface instead of speculative framework architecture.

Tickets:

- [ ] Audit the current `Sources/` and `Tests/` layout against the scope that is already implemented.
- [ ] Decide which current files should remain co-located and which future responsibilities are likely to deserve breakouts later.
- [ ] Map likely future breakouts for playback, worker protocol, profile store, and library-facing surfaces based on the future scope Gale is finalizing.
- [ ] Document the intended package structure and the decision boundaries for future extraction work.
- [ ] Identify any near-term structural cleanup that would reduce duplication without adding new layers.

Exit criteria:

- [ ] The package has a documented target file and folder structure that matches the intended scope.
- [ ] Future breakout boundaries are charted clearly enough to guide later cleanup without forcing premature fragmentation now.
- [ ] The structure plan explicitly avoids unnecessary layers and keeps data flow straight.

## Milestone 17: Notification-linked priority playback

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
- [ ] Document the final queueing and notification semantics clearly once the contract exists.

Exit criteria:

- [ ] The project has one explicit design for notification-linked priority playback and job triggering, with queue semantics that are documented and testable.
- [ ] The design makes clear whether the existing request queue was extended or a distinct playback queue was justified after review.
- [ ] The implementation path avoids unnecessary new layers and keeps playback, generation, and notification ownership easy to reason about.

## Current Review Findings To Address

These findings came out of the latest live-service review pass and are duplicated here on purpose so they stay visible after the current chat context is gone.

- [ ] Tighten shutdown so terminal cancellation is not emitted until in-flight work has actually unwound, especially around post-generation filesystem work during `create_profile`.
- [ ] Add or document stronger cancellation checkpoints around temp WAV writing, profile persistence, and export so shutdown behavior is not only bounded but also truly quiescent.
- [ ] Make `list_profiles` resilient to stray files, partial directories, and one-off corrupt entries instead of poisoning the full operation on the first bad manifest.
- [ ] Revisit relative `output_path` resolution so exports do not silently depend on the worker process launch directory.
- [ ] Keep the README and roadmap aligned with the real implementation whenever playback semantics, shutdown behavior, or stderr instrumentation changes.
- [ ] Fix the current log structure drift, or adopt a real logging framework boundary, so operator output stays structured and readable end to end.
- [ ] Use the new playback metrics to decide whether the remaining wobble and pops are primarily starvation, schedule jitter, or chunk-boundary shaping problems before changing cadence again.
