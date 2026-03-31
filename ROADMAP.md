# Project Roadmap

## Vision

- Build a small, reliable Swift worker executable that keeps MLX and Apple-runtime concerns isolated behind a simple process boundary.

## Product principles

- Keep the worker thin and concrete instead of layering it into a mini-framework.
- Prefer one boring process boundary over multiple internal coordinators or bridges.
- Make every operator-facing error and progress message readable and specific.
- Keep the resident `0.6B` path fast, predictable, and easy to reason about.

## Milestone Progress

- [x] Milestone 0: Bootstrap
- [ ] Milestone 1: JSONL worker contract
- [ ] Milestone 2: Resident `0.6B` runtime
- [ ] Milestone 3: On-demand `1.7B` VoiceDesign path
- [ ] Milestone 4: Integration hardening

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

## Milestone 1: JSONL worker contract

Scope:

- [ ] Define the first request, progress-event, success, and failure message shapes.
- [ ] Keep audio exchange file-path-based for the initial implementation.

Tickets:

- [ ] Write the first `stdin` read loop and `stdout` JSONL encoder.
- [ ] Add request decoding and terminal response encoding.
- [ ] Add structured progress events for long-running work.
- [ ] [P] Add tests for decoding and encoding the JSONL contract.

Exit criteria:

- [ ] The executable can stay alive, accept requests, and emit deterministic JSONL responses.
- [ ] Protocol errors are human-readable and unambiguous.

## Milestone 2: Resident `0.6B` runtime

Scope:

- [ ] Pre-warm the `Qwen3-TTS 0.6B` model at worker startup.
- [ ] Keep the resident model alive for streaming cloned playback requests.

Tickets:

- [ ] Add startup warmup flow for the resident model.
- [ ] Add streaming playback request handling around the resident path.
- [ ] Emit progress updates during resident-model work.
- [ ] Validate resident-model failure reporting when warmup or inference breaks.

Exit criteria:

- [ ] The worker warms the resident model once at startup.
- [ ] Streaming cloned playback requests do not reload the resident model each time.
- [ ] Startup and runtime failures clearly explain the most likely cause.

## Milestone 3: On-demand `1.7B` VoiceDesign path

Scope:

- [ ] Support audio-file generation with `Qwen3 VoiceDesign 1.7B`.
- [ ] Load the large model only for the duration of a request.

Tickets:

- [ ] Add request handling for VoiceDesign file generation.
- [ ] Load the `1.7B` model on demand.
- [ ] Unload or release the model after request completion.
- [ ] Add validation around input paths, output paths, and request failures.

Exit criteria:

- [ ] VoiceDesign requests produce audio files through the on-demand path.
- [ ] The worker does not keep the `1.7B` model resident after the request completes.
- [ ] Progress and failure output stay structured and readable.

## Milestone 4: Integration hardening

Scope:

- [ ] Make the worker straightforward to own from a parent process.
- [ ] Harden logs, shutdown behavior, and repo validation.

Tickets:

- [ ] Add clean EOF and shutdown handling for the worker loop.
- [ ] Add tests for malformed input, missing files, and process-lifecycle edges.
- [ ] Add any minimal packaging notes needed for parent-process ownership.

Exit criteria:

- [ ] The worker exits cleanly on EOF or shutdown requests.
- [ ] Failure modes around malformed JSONL and filesystem issues are covered by tests.
- [ ] Parent-process integration expectations are documented without adding unnecessary architecture.
