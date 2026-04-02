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

## Current Review Findings To Address

These findings came out of the latest live-service review pass and are duplicated here on purpose so they stay visible after the current chat context is gone.

- [ ] Tighten shutdown so terminal cancellation is not emitted until in-flight work has actually unwound, especially around post-generation filesystem work during `create_profile`.
- [ ] Add or document stronger cancellation checkpoints around temp WAV writing, profile persistence, and export so shutdown behavior is not only bounded but also truly quiescent.
- [ ] Make `list_profiles` resilient to stray files, partial directories, and one-off corrupt entries instead of poisoning the full operation on the first bad manifest.
- [ ] Revisit relative `output_path` resolution so exports do not silently depend on the worker process launch directory.
- [ ] Keep the README and roadmap aligned with the real implementation whenever playback semantics, shutdown behavior, or stderr instrumentation changes.
- [ ] Fix the current log structure drift, or adopt a real logging framework boundary, so operator output stays structured and readable end to end.
- [ ] Use the new playback metrics to decide whether the remaining wobble and pops are primarily starvation, schedule jitter, or chunk-boundary shaping problems before changing cadence again.
