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
- [ ] Milestone 18: Package docs and distribution polish
- [x] Milestone 19: Persisted async generation jobs and batch artifacts
- [ ] Milestone 20: Per-request event stream observability
- [ ] Milestone 21: Unified Logging with `Logger`

## Milestone 0: Bootstrap

Scope:

- [x] Create the Swift executable package scaffold.
- [x] Establish Swift Testing as the default test framework.
- [x] Add grounded `README.md` and `ROADMAP.md` files.

Tickets:

- [x] Bootstrap the package in a standalone local repository checkout.
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
- [x] Make `list_profiles` skip one-off corrupt entries so one bad manifest does not poison the full listing.
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
- [x] `list_profiles` returns healthy profiles even when one stored-profile entry is damaged or incomplete.
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

## Milestone 18: Package docs and distribution polish

Scope:

- [ ] Add first-class package documentation and index metadata so Swift package consumers can discover and understand the library surface without reading the source tree.
- [x] Standardize repository formatting expectations for Swift code so contributor output stays predictable across local work and CI.
- [ ] Keep Swift Package Index presentation aligned with the actual package surface without adding maintenance-only metadata that the package does not need.

Tickets:

- [x] Add a first DocC catalog for `SpeakSwiftly` with entry points for runtime ownership, top-level normalizer ownership, and the JSONL worker contract.
- [x] Add baseline DocC coverage for text-profile management, live playback requests, and voice-profile creation operations.
- [x] Add SwiftFormat to the repository with checked-in configuration and a documented formatting command.
- [x] Decide whether SwiftLint belongs in the same pass or should remain a separate follow-up once SwiftFormat is in place.
- [x] Add a minimal `.spi.yml` that reflects the package's DocC and Swift Package Index needs once the docs surface exists.
- [ ] Document when `.spi.yml` needs changes and keep it intentionally small.

## Milestone 20: Per-request event stream observability

Scope:

- [ ] Make per-request event streaming a first-class documented part of the Swift package surface instead of an incidental detail of `RequestHandle`.
- [ ] Add an explicit in-process per-request observation surface for callers that only have a request ID and need to reconnect later.
- [ ] Keep request correlation and event observation readable without forcing callers down into JSONL worker internals.
- [ ] Clarify the relationship between request IDs, streamed request events, cancellation, queue snapshots, request snapshots, and any later cross-process subscription story.

Tickets:

- [ ] Replace the current single-continuation request-stream bookkeeping with a runtime-owned per-request event broker that supports multiple in-process subscribers.
- [ ] Add a public `runtime.request(id:)` snapshot API for callers that need current per-request state before attaching to live updates.
- [ ] Add a public `runtime.updates(for:)` API for callers that only know a request ID and need on-demand in-process observation.
- [ ] Decide whether the new on-demand stream should replay a bounded recent window on attach or start at the live tail only, and make that behavior explicit in the API contract.
- [ ] Introduce a data-first per-request update payload that can represent terminal failure as data for late subscribers, while keeping `RequestHandle.events` source-compatible for existing callers.
- [ ] Audit the current `RequestHandle` and `RequestEvent` surface for any missing event types, missing lifecycle guarantees, or mismatches between docs and implementation.
- [ ] Document the exact lifecycle guarantees for request snapshots and streamed updates, including queued, acknowledgement, started, progress, completed, failed, cancelled, and stream teardown behavior.
- [ ] Ensure request IDs returned by the Swift API are clearly described as stable correlation IDs for event observation and cancellation.
- [ ] Add or tighten fast tests around request-handle event ordering, terminal completion semantics, cancellation semantics, multiple subscribers, late subscribers, replay behavior, and stream teardown.
- [ ] Update package docs so Swift consumers can discover and use per-request snapshots and update streams without reading runtime internals.
- [ ] Record the intentional boundary that this milestone is in-process only and does not yet promise durable cross-process subscriptions or persisted request-event history.

Implementation notes:

- Detailed design and sequencing live in `docs/maintainers/per-request-update-stream-plan-2026-04-09.md`.
- The preferred implementation shape is a runtime-owned request-event broker plus additive `request(id:)` and `updates(for:)` APIs, not a second ad-hoc observer map.
- If bounded replay needs a queue structure richer than `Array`, prefer a first-party or top-tier Swift package such as `swift-collections` on purpose rather than bespoke ring-buffer code.

Exit criteria:

- [ ] The package documents one clear per-request observation story for Swift callers.
- [ ] In-process callers can reconnect to per-request state and live updates using only a request ID.
- [ ] Streamed request events and request snapshots have explicit lifecycle guarantees backed by tests.
- [ ] Request IDs, streamed updates, snapshots, and cancellation semantics are easy to understand from the public docs alone.
- [ ] The in-process scope boundary is explicit, so callers do not mistake this milestone for a durable cross-process subscription guarantee.

Exit criteria:

- [ ] A new consumer can navigate the main package API through DocC instead of relying on README snippets alone.
- [x] Swift formatting expectations are explicit, repeatable, and checked into the repo.
- [ ] Swift Package Index has the minimal metadata it needs to render the package cleanly without stale or speculative configuration.
- [x] Add playback queue-depth instrumentation so low-buffer and starvation conditions are visible in stderr logs.
- [x] Add profile-store instrumentation for create, load, list, remove, and export with concrete filesystem paths.
- [x] Add automated assertions for important stderr diagnostics in the fast test suite.

Exit criteria:

- [x] A live-service latency complaint can be broken down into warmup, queueing, generation, playback, and filesystem phases from existing logs.
- [x] Operator-facing diagnostics contain enough context to identify the request, profile, path, and likely failure point without attaching a debugger.
- [x] The JSONL contract remains clean while stderr becomes a trustworthy operational signal.

## Milestone 21: Unified Logging with `Logger`

Scope:

- [ ] Move package-owned operator diagnostics from ad-hoc stderr writes toward Apple's Unified Logging surface built around `Logger`.
- [ ] Preserve the current human-friendly, concrete diagnostic wording while making runtime logs easier to filter in Console, Instruments, and later log-store tooling.
- [ ] Keep the logging shape direct and local to the runtime instead of adding a wrapper-heavy logging abstraction.
- [ ] Make the relationship between structured package logs and the JSONL worker contract explicit, so logs stay operational and stdout stays protocol-only.

Tickets:

- [ ] Inventory the current stderr logging surface and group it by subsystem, category, and intended audience before changing call sites.
- [ ] Define a small package logging layout using `Logger` with clear subsystem and category names for runtime lifecycle, playback, generation, profiles, persistence, and request observation.
- [ ] Add a package-owned logger access pattern that keeps dependency flow simple and does not introduce a second diagnostics coordinator.
- [ ] Replace direct runtime stderr writes with `Logger` call sites where Apple Unified Logging is the right surface, while preserving stdout for JSONL protocol traffic.
- [ ] Decide which diagnostics should remain mirrored to stderr for parent-process operability during local worker runs, and make that mirroring policy explicit instead of accidental.
- [ ] Audit current message strings so migrated log lines still explain what failed, where it failed, and the most likely cause in concrete language.
- [ ] Use appropriate log levels such as debug, info, notice, error, and fault intentionally instead of flattening everything to one severity.
- [ ] Add or tighten tests around the logging seam where practical, especially where the runtime currently depends on injected stderr writers for diagnostics assertions.
- [ ] Document how package logs are intended to be consumed locally with Console or other Unified Logging readers, and clarify which information remains on the JSONL contract versus the logging channel.
- [ ] Decide whether any later `OSLogStore`-based inspection or export story belongs in this package or should remain a separate follow-up once `Logger` adoption is stable.

Implementation notes:

- Apple documents the unified logging direction under `OSLog` and `Logging`, with `Logger` as the structured Swift API surface for emitting logs.
- Prefer a durable building-block change here: one clear package logging story that future observability work can reuse, not a temporary stderr-to-logger bridge that leaves both paths half-owned.
- If a helper type is needed, keep it narrow and local to package logging setup rather than introducing a general-purpose service layer.

Exit criteria:

- [ ] Package-owned operational diagnostics primarily flow through `Logger` with clear subsystem and category names.
- [ ] The JSONL worker contract remains stdout-only and easy to reason about, with logging clearly separated from protocol traffic.
- [ ] Operator-facing log messages remain specific, readable, and useful in Console as well as local debugging flows.
- [ ] The repo documents when to use Unified Logging, when stderr mirroring still exists, and what future log-inspection work is intentionally out of scope for this milestone.

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
- [ ] Persist a little more voice-profile source provenance from `create_profile` and `create_clone`, especially whether clone transcripts were supplied or inferred plus any stable source-audio details that would make rerolls, diagnostics, and future profile introspection easier to explain.
- [x] Investigate automatic audio-route and output-device change handling for live playback, including headphones, AirPods, and macOS default-output switches, and decide whether `SpeakSwiftly` should observe route-change or hardware-change notifications and rebuild or retarget the playback engine when those changes occur.

## Milestone 16: `mlx-audio-swift` upgrade review

Scope:

- [ ] Review a newer `mlx-audio-swift` release or revision soon and decide whether `SpeakSwiftly` should adopt it.
- [ ] Keep the worker thin and direct while making dependency drift easier to reason about.
- [ ] Avoid wrapper-heavy “compatibility” architecture unless a real upstream API break makes it necessary.

Tickets:

- [ ] Compare the currently pinned `mlx-audio-swift` revision with the latest available tagged release or stable candidate.
- [ ] Review upstream changes to Qwen3 TTS defaults, generation controls, streaming behavior, and model-loading expectations for any impact on `SpeakSwiftly`.
- [ ] Preserve upstream `AudioGeneration` event detail through a first-class side-channel, trace stream, or equivalent logging surface instead of collapsing every resident generation path down to raw sample chunks at the first wrapper boundary.
- [ ] Evaluate whether the resident `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit` default is still the right MLX choice on Apple Silicon versus a `bf16` build or a different `0.6B` family member, and record the latency, memory, and audible tradeoffs explicitly.
- [ ] Verify whether `Qwen3-TTS-12Hz-0.6B-CustomVoice` is a viable resident clone backend for `SpeakSwiftly`, including what `voice`, `ref_audio`, and `ref_text` semantics actually hold for that model family and whether it meaningfully changes startup or per-request conditioning cost.
- [ ] Generalize stored Qwen materializations so `SpeakSwiftly` can load profile assets per resident backend or Qwen family instead of assuming one hard-coded `.qwen3` materialization shape.
- [ ] Define a versioned persisted Qwen conditioning-artifact payload that captures reusable profile-side preparation work beyond raw `reference.wav` plus `referenceText`, and record what remains request-shaped versus profile-shaped explicitly.
- [ ] Add resident runtime caching for the active profile's prepared Qwen conditioning artifact, with clear invalidation on profile switch, reroll, backend change, artifact-version change, and explicit unload or reload operations.
- [ ] Re-run the resident Qwen benchmark suite only after persisted conditioning artifacts and active-profile caching land, and record that the post-artifact benchmark is the authoritative int8 versus bf16 comparison.
- [ ] Re-run the resident playback, profile-generation, and typed-library integration checks against a candidate upgrade in an isolated branch.
- [ ] Record any concrete reasons to upgrade, defer, or stay pinned, including behavior changes that affect playback stability or generation length.
- [ ] If the upgrade is adopted, pin to an explicit stable revision or release instead of a moving branch tip.

Variant B plan:

- [ ] Keep the upstream patch model-specific and additive by introducing a `Qwen3TTS` semantic reference-conditioning type instead of changing `SpeechGenerationModel` or adding a cross-model conditioning abstraction.
- [ ] Keep that conditioning type semantic and stable: expose reusable reference-side ingredients such as speaker embedding, encoded reference speech codes, prepared reference-text state, and resolved language data, but do not expose fused prompt embeddings, pad embeddings, trailing hidden state, or other final assembled talker-input machinery.
- [ ] Split the current `prepareICLGenerationInputs(...)` implementation into two helpers:
  - [ ] stage 1: prepare reusable reference conditioning from `refAudio`, `refText`, and `language`
  - [ ] stage 2: assemble request-specific Qwen input tensors from `text` plus prepared reference conditioning
- [ ] Keep `prepareICLGenerationInputs(...)` itself as the compatibility wrapper that composes stage 1 and stage 2 so the current implementation path stays readable and centralized.
- [ ] Add additive `Qwen3TTSModel.generate(...)` and `generateStream(...)` overloads that accept prepared reference conditioning plus target text while leaving the existing `refAudio`/`refText` entry points untouched.
- [ ] Route the existing raw-reference generation path through the new helpers so the new conditioning flow and the compatibility flow share one implementation instead of drifting.
- [ ] Add focused upstream Qwen tests that prove:
  - [ ] reference conditioning can be prepared successfully
  - [ ] generation from prebuilt conditioning succeeds and remains behaviorally aligned with the raw-reference path
  - [ ] existing generation entry points still work unchanged
  - [ ] `CustomVoice` behavior stays separate from the clone-conditioning path
- [ ] Keep persistence out of the upstream patch entirely; persistence remains a `SpeakSwiftly` follow-up after the new conditioning seam proves useful in memory.
- [ ] After the upstreamable conditioning patch exists locally, add a `SpeakSwiftly` resident in-memory cache keyed by profile identity, backend, and artifact version before designing any on-disk profile artifact format.

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
- [ ] Make active-playback interruption and lifecycle observation predictable from both the executable and `SpeakSwiftly`.
- [ ] Preserve the current thin worker shape instead of turning playback control into a manager or coordinator layer.

Tickets:

- [x] Define the minimum playback control operations that are actually worth owning around `playback_pause`, `playback_resume`, and `playback_state`, and keep the contract narrow instead of growing a generic command surface.
- [ ] Define typed `SpeakSwiftly` API parity for playback control requests and events instead of forcing library callers back through ad-hoc JSONL handling.
- [ ] Unify playback-state reporting under one controller-owned source of truth so `playback_state.state` and `playback_state.active_request` cannot diverge during preroll, rebuffer, interruption, or drain.
- [ ] Add an explicit playback-route policy surface so worker owners can choose whether live playback follows the current system output immediately, waits for the original device class to return, or fails over only for specific route categories.
- [ ] Add a wake-recovery grace policy for Bluetooth routes so the runtime can remember the pre-sleep device, wait briefly after wake when that device is likely to auto-reconnect, and only then fall back to speakers if the preferred route does not return in time.
- [ ] Keep the current default route policy as “follow the active system output device” until a narrower policy surface is implemented and documented.
- [ ] Add targeted coverage for Bluetooth and default-output-device churn, including a simulated “AirPods leave for another device, then return” path that proves active requests recover without dying.
- [ ] Add an out-of-band playback hardware harness that can trigger sleep, wake, and route-change scenarios from a second machine so host power-state validation does not depend only on manual local testing.
- [ ] Once an iPhone companion app exists, revisit route policy with a smarter multi-device model that can see both endpoints at once and make better choices than blind speaker fallback.
- [ ] Decide and document whether a stop request only interrupts the active request or can also affect queued playback requests.
- [ ] Emit structured lifecycle output for control acceptance, playback interruption, and terminal request state so parent processes can reason about what happened without guessing.
- [ ] Add runtime coverage for `playback_pause`, `playback_resume`, and `playback_state`, including no-op state transitions when nothing is currently playing and explicit state payload assertions for idle, paused, and resumed playback.
- [ ] Add automated coverage for active `speak_live` interruption, background-playback interruption, and control requests that must not disturb queued playback ownership when they only target the active request.
- [ ] Add targeted queued-live coverage that exercises preroll, rebuffer, and drain while asserting that playback-state snapshots stay internally consistent.
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
- [ ] Add typed `SpeakSwiftly` parity for queue inspection and clearing instead of exposing those behaviors only through raw JSONL.
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
- [ ] Start carving the normalization stack into the future `TextForSpeech` package family without coupling the pure text transforms to app- or file-ownership concerns.
- [ ] Let worker owners inspect, add, remove, and clear replacement rules without hard-coding all normalization behavior into the executable.
- [ ] Keep the normalization system concrete and readable instead of turning it into an over-abstracted plugin or rule-engine layer.

Tickets:

- [ ] Split out a reusable `TextForSpeech` library target inside this repository first, before deciding whether a separate standalone repository is justified.
- [ ] Keep the lowest-level normalization core deterministic and side-effect free, with profile and replacement types that stay reusable outside `SpeakSwiftly`.
- [ ] Add a text-system-owned runtime profile store that can snapshot the current effective profile for each job start without letting hot reload mutate in-flight requests.
- [ ] Treat YAML loading, file watching, SwiftUI settings integration, and remote update adapters as text-system configuration concerns layered above the pure normalization core.
- [ ] Define the smallest useful replacement-rule shape, likely simple exact-match and phrase-replacement entries before considering broader pattern support.
- [ ] Add initial typed replacement rules with explicit phase and input-kind scoping before considering regex or broader pattern families.
- [ ] Decide and document rule precedence between built-in normalization passes and custom replacement rules so downstream callers can predict the final spoken text.
- [x] Add worker operations for listing normalization replacements, adding or updating a replacement, removing a replacement, and clearing all custom replacements.
- [x] Add typed `SpeakSwiftly` parity for normalization-replacement management instead of exposing those behaviors only through raw JSONL.
- [ ] Decide whether replacement rules are process-local, profile-store-local, or shared per-user state, and document the persistence boundary explicitly.
- [ ] Emit structured success and failure output for replacement-rule mutations so callers can distinguish validation failures, duplicate-key behavior, and filesystem errors.
- [ ] Add automated coverage for replacement precedence behavior against the built-in normalization pipeline.
- [x] Document the normalization-replacement semantics and examples in the README once the contract exists.

Exit criteria:

- [ ] The repository contains an internal `TextForSpeech` target with reusable profile and runtime primitives, and the later repo-extraction decision is still free to happen after another real consumer appears.
- [ ] A parent process can inspect and manage custom normalization replacements through documented worker operations and the equivalent typed library path.
- [ ] Replacement behavior is predictable, test-covered, and explicit about precedence and persistence.
- [ ] The normalization surface stays thin and understandable instead of growing into a generic rules framework.

## Milestone 13: Swift package distribution

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

Exit criteria:

- [ ] A downstream Swift package can adopt `SpeakSwiftly` through a documented supported distribution path without relying on repo-local adjacency assumptions.
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

- [x] Finish the typed Swift API breakout from a kitchen-sink `Runtime` method surface into stable concern handles.
- [x] Make the public startup story and generation surface read like a deliberate library instead of a thin transport wrapper.
- [x] Trim public transport-shaped model construction points that do not need to be caller-authored.

Tickets:

- [x] Replace `SpeakSwiftly.live(...)` with `SpeakSwiftly.liftoff(configuration:)`, keeping `configuration` optional.
- [x] Reshape `SpeakSwiftly.Configuration` so startup options include the selected `speechBackend` plus an optional `textNormalizer`.
- [x] Keep explicit path-based configuration persistence public, and move default persistence helpers out of the primary public API story.
- [x] Rename `Generate.speak(...)` to `Generate.speech(...)`.
- [x] Add `Generate.audio(...)` for file-oriented audio generation.
- [x] Remove the public `SpeakSwiftly.Job` multiplexing surface once `Generate.speech(...)` and `Generate.audio(...)` exist.
- [x] Move generation-queue inspection from `Player` to `Jobs`.
- [x] Collapse playback-queue inspection into a player-owned query such as `Player.list(...)`.
- [x] Keep `Voices.create(design named: ...)` and `Voices.create(clone named: ...)` as the overloaded voice-profile creation surface.
- [x] Review all public output model memberwise initializers and make transport/result-model construction internal unless a real caller-authored use case exists.
- [ ] Revisit whether `BatchItem` remains a public caller-authored batch input type or should be narrowed once `Generate` owns more shaping work.

Exit criteria:

- [x] The typed Swift startup path is one obvious `liftoff(...)` entry point with clean defaults.
- [x] Live playback and file generation are separate public generation calls instead of a shared job-type switch.
- [x] Queue inspection methods live on the concern handle that matches the data being inspected.
- [ ] Public model construction points are limited to the inputs and outputs callers truly need to author or inspect.

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

## Milestone 19: Persisted async generation jobs and batch artifacts

Scope:

- [x] Source of truth design note: `docs/maintainers/persisted-generation-jobs-and-batch-plan-2026-04-07.md`
- [x] Evolve managed generated-file output into a durable async job surface that can support later batch-oriented generation work cleanly.
- [x] Let callers reconnect to generation state, inspect saved artifacts, and fetch completed output without relying on one live request stream staying attached forever.
- [x] Keep the first expansion grounded in the current worker and typed-library model, and avoid introducing a broader service subsystem until the batch and multi-client use cases truly require it.

Tickets:

- [x] Define a persisted generation-job record shape that can represent queued, running, completed, failed, and expired generated-file requests.
- [x] Make job kind explicit in the contract from the start: file jobs for one-file generation and batch jobs for many-file generation.
- [x] Split durable identifiers intentionally into `jobID` for generation work and `artifactID` for saved outputs so later batch generation does not force a naming reset.
- [x] Decide which parts of job state belong in the immediate worker contract versus a later service or MCP resource surface.
- [x] Add first-class stored artifact metadata for generated files so callers can list, inspect, fetch, and eventually garbage-collect output intentionally.
- [x] Define the retention, cleanup, and expiry rules for generated files and their job metadata without making single-file generation harder to reason about.
- [x] Reconcile current request-id behavior with the new durable identifier split so `queue_speech_file` no longer implies that one request id is the saved artifact id.
- [x] Design the batch-generation shape explicitly, including a future `generated_batch(id:)` and `generated_batches()` surface where a batch is the many-files unit and is backed by a batch job in the persisted-job model.
- [x] Add reconnectable inspection semantics for completed and in-flight generation jobs so callers do not have to keep one typed stream or stdio session attached for long-running work.
- [x] Document the point at which this milestone should become a true service or subscription surface rather than an extension of the current worker contract.

Exit criteria:

- [x] The repository has one documented direction for persisted async generation jobs that clearly composes from single-file generation into future batch generation.
- [x] Generated-file metadata, retention rules, and later batch identifiers are explicit enough that future implementation work does not need a second naming or ownership reset.
- [x] The roadmap distinguishes the near-term managed `.file` generation path from the later heavier async-job-service expansion.

## Current Review Findings To Address

These findings came out of the latest live-service review pass and are duplicated here on purpose so they stay visible after the current chat context is gone.

- [x] Tighten shutdown so terminal cancellation is not emitted until in-flight work has actually unwound, especially around post-generation filesystem work during `create_profile`.
- [x] Add or document stronger cancellation checkpoints around temp WAV writing, profile persistence, and export so shutdown behavior is not only bounded but also truly quiescent.
- [x] Make `list_profiles` resilient to stray files, partial directories, and one-off corrupt entries instead of poisoning the full operation on the first bad manifest.
- [x] Add a strict multi-request audible live-playback e2e lane that pre-queues several jobs on one worker and validates queued drain behavior directly.
- [x] Revisit relative `output_path` resolution so exports do not silently depend on the worker process launch directory.
- [x] Keep the README and roadmap aligned with the real implementation whenever playback semantics, shutdown behavior, or stderr instrumentation changes.
- [x] Fix the current log structure drift, or adopt a real logging framework boundary, so operator output stays structured and readable end to end.
- [x] Use the new playback metrics to decide whether the remaining wobble and pops are primarily starvation, schedule jitter, or chunk-boundary shaping problems before changing cadence again.
- [ ] Tune the first drained-queue Marvis playback so it reaches a steadier audible startup without sacrificing the restored dual-lane generation model.
- [ ] Use the new scheduler and playback observability to compare first-request startup reserve, rebuffer count, and schedule-gap behavior before and after each tuning pass.
- [ ] Keep the restored dual-lane queued-live Marvis overlap semantics intact while adjusting only playback-buffer and cadence behavior.

## Milestone 20: First-request Marvis playback tuning

Scope:

- [ ] Improve the first live Marvis playback in a drained queue without collapsing the restored dual-lane generation scheduler back into blanket serialization.
- [ ] Keep playback tuning and scheduler correctness clearly separated so later regressions are easier to diagnose.
- [ ] Use the runtime's explicit playback and scheduler observability as the source of truth for each tuning pass.

Tickets:

- [ ] Establish a repeatable tuning checklist for the first drained-queue Marvis playback using the existing queued-live Marvis E2E lane plus stderr scheduler and playback metrics.
- [ ] Compare first-request startup-buffer targets, buffered-audio reserve, and rebuffer counts across at least one before and after capture for each tuning change.
- [ ] Investigate whether resident preload is too eager about preparing local playback hardware, especially the `startResidentPreload()` -> `playbackController.prepare(...)` -> `AudioPlaybackDriver.rebuildEngine(sampleRate:)` path that currently tears down hardware, begins routing arbitration, starts a fresh `AVAudioEngine`, and immediately calls `play()` before an active live request exists.
- [ ] Revisit warmup startup, low-water, and resume thresholds specifically for the first active Marvis playback request.
- [ ] Revisit Marvis resident streaming cadence only if buffer tuning alone cannot reduce first-request rebuffering.
- [ ] Keep the `marvis_generation_scheduler_snapshot` and lane-reservation logs aligned with any playback-tuning changes so queue truth stays obvious.
- [ ] Add or update regression coverage when a tuning change intentionally shifts logged threshold values or expected playback metrics.
- [ ] Record subjective audible outcomes and objective stderr metrics together in the maintainer note after each meaningful tuning pass.

Exit criteria:

- [ ] The first drained-queue Marvis playback is measurably steadier than the current baseline.
- [ ] The restored dual-lane queued-live Marvis overlap model remains intact and verified.
- [ ] The repository has a documented before and after record for the tuning work that makes later regressions obvious.

## Pre-v1 Release Hardening

Before the first full `v1.0.0` release, finish the release-hardening pass in [pre-v1-release-hardening-2026-04-07.md](docs/maintainers/pre-v1-release-hardening-2026-04-07.md).

- [x] Persist real e2e worker stdout and stderr artifacts plus compact per-run summaries so memory and later CPU telemetry can be inspected after a run finishes.
- [x] Add CPU accounting to the retained real e2e run summaries through the same unprivileged process-accounting path used for current memory snapshots.
- [x] Enforce Debug and Release runtime publication and verification on tagged prereleases and final releases, not only through the local repo-maintenance release script.
- [x] Publish launcher scripts, stable runtime aliases, and manifest-first consumption helpers so local consumers stop reconstructing executable and `default.metallib` paths by hand.
- [x] Keep runtime resource lookup anchored to bundle or manifest reality instead of current-working-directory assumptions wherever published runtimes are consumed.
