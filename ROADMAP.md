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
- [ ] Add assertions for operator-facing `stderr` diagnostics in the automated test suite.
- [ ] Add a stronger automated check that a real non-`nil` reference-audio object reaches the resident generation path in fast tests without making the unit suite depend on MLX runtime initialization.

Exit criteria:

- [x] The docs describe the real playback-priority queue instead of FIFO behavior.
- [x] Immediate-start requests do not emit misleading queued events.
- [x] Corrupt stored-profile manifests returned through `list_profiles` surface as `filesystem_error`.
- [x] Opt-in serialized real-model e2e coverage exists for both the `1.7B` profile-creation path and the resident `0.6B` live path.
- [ ] The fast test suite also covers `stderr` diagnostics and the remaining profile-conditioning edge assertions.
