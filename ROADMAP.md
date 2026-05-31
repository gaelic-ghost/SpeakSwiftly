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
- [Milestone 26: Pre-v1 Release Hardening](#milestone-26-pre-v1-release-hardening)
- [Milestone 29: Security Audit Hardening](#milestone-29-security-audit-hardening)
- [Milestone 30: Generation Quality Telemetry And Guards](#milestone-30-generation-quality-telemetry-and-guards)
- [Milestone 31: macOS Retrench And Mobile Split](#milestone-31-macos-retrench-and-mobile-split)
- [Milestone 32: Qwen-Only Output Modularization](#milestone-32-qwen-only-output-modularization)
- [Milestone 33: First-Party Core ML Qwen3-TTS Port](#milestone-33-first-party-core-ml-qwen3-tts-port)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Milestone Progress

- Milestone 16: `mlx-audio-swift` Upgrade Review - In Progress
- Milestone 21: Unified Logging With `Logger` - Planned
- Milestone 26: Pre-v1 Release Hardening - In Progress
- Milestone 29: Security Audit Hardening - Planned
- Milestone 30: Generation Quality Telemetry And Guards - In Progress
- Milestone 31: macOS Retrench And Mobile Split - In Progress
- Milestone 32: Qwen-Only Output Modularization - In Progress
- Milestone 33: First-Party Core ML Qwen3-TTS Port - Research

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
- [ ] Align Qwen generation policy with the current `mlx-audio-swift` and official Qwen surfaces by evaluating an explicit `topK: 50`, deciding whether `maxTokens` should stay at the Swift wrapper default or move toward official checkpoint/evaluation values, and designing one narrow request-level generation-tuning surface instead of exposing raw MLX knobs everywhere.
- [ ] Recheck Qwen cancellation after the `mlx-audio-swift` upgrade, then simplify only local stream-adapter duplication that upstream cancellation now makes unnecessary while preserving SpeakSwiftly-owned queue completion, request-stream failure, and playback/generation state cleanup.
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

Superseded by Milestone 32

### Scope

- [x] Stop investing in Marvis playback tuning for the vNext package line.
- [x] Replace the Marvis investigation path with a Qwen-only output modularization pass.
- [x] Preserve the historical notes below as context for why Marvis is being removed instead of tuned further.

### Tickets

- [x] Decide that Marvis is outside the vNext supported backend set.
- [x] Remove stale Marvis validation-lane and release-hardening references while preserving older release notes as history.
- [x] Keep removed backend values rejected clearly so persisted configs and worker requests fail with descriptive unsupported-backend errors.

### Stage Notes

- Earlier Milestone 22 work explored overlap-specific thresholds, cadence tweaks, and queue-admission changes in detail.
- The 2026-04-22 steady state was intentionally simpler:
  - Marvis generation is serialized
  - the default resident policy is `single_resident_dynamic`
  - a benchmark existed for `dual_resident_serialized` versus `single_resident_dynamic`
  - all live Marvis playback uses one conservative startup profile
  - the live cadence matched the upstream Marvis `0.5s` path
- The durable read after those audible runs is:
  - local overlap complexity was not the main problem
  - simplifying the runtime improved consistency, especially for later queued requests
  - even after that simplification, audible Marvis still tends to rebuffer
  - the next useful work would have been upstream and reference-path investigation, not rebuilding the old overlap model
- The vNext decision supersedes that investigation: Marvis is removed instead
  of tuned further, and active generation work is Qwen-only.

### Exit Criteria

- [x] vNext documentation names Qwen3 as the only supported generation family.
- [x] Removed Marvis and Chatterbox values fail clearly in typed config and worker request tests.
- [x] Historical Marvis tuning notes remain separated from active prerelease work.

## Milestone 26: Pre-v1 Release Hardening

### Status

In Progress

### Scope

- [ ] Finish the release-hardening pass needed before the first full `v1.0.0` release.
- [ ] Keep release mechanics concrete, repeatable, and observable from this repository alone.
- [ ] Make runtime publication and package-consumer expectations explicit enough that tagged releases are genuinely shippable.

### Tickets

- [ ] Resolve the remaining active milestones that define the stable public surface and release-operability story, especially logging migration and Qwen-only output modularization.
- [ ] Streamline runtime persistence configuration so the package has one durable storage contract: platform Application Support by default, or one explicit startup state root that moves profiles, runtime configuration, text profiles, generated files, and generation jobs together. Remove or deprecate profile-root-specific compatibility surfaces in consumers such as `SpeakSwiftlyServer` once they can pass `stateRootURL` directly.
- [ ] Verify downstream `SpeakSwiftlyServer` adoption separately before release after the Milestone 28 typed observation API cleanup.
- [ ] Re-run the release checklist against the final tagged-candidate shape and tighten any remaining migration notes or operator guidance before `v1.0.0`.

### Exit Criteria

- [ ] Tagged releases are operationally self-explanatory for local consumers and package consumers.
- [ ] The package and worker surfaces are documented clearly enough that `v1.0.0` does not freeze accidental behavior.
- [ ] Release verification proves both package correctness and published-runtime correctness.

## Milestone 29: Security Audit Hardening

### Status

Planned

### Scope

- [ ] Resolve the May 2026 Codex Security repo-wide audit findings and keep the audit trail public-safe under `docs/security-audits/`.
- [ ] Treat package-local trusted-caller APIs separately from downstream network or multi-client exposure so fixes land at the right ownership boundary.
- [ ] Prefer narrow runtime guardrails and explicit host guidance over broad authorization machinery inside the standalone package.

### Tickets

- [ ] Remove raw Qwen live chunk text from structured logs. Keep chunk index, segmentation, counts, timing, and progress fields, but do not persist spoken request text in stderr diagnostics.
- [ ] Add retained-generation admission limits for non-playback file and batch jobs, including queued job count, batch item count, queued text size, and clear `invalidRequest` diagnostics when a caller exceeds those limits.
- [ ] Pin GitHub Actions workflow dependencies to immutable commit SHAs and add explicit least-privilege workflow `permissions`, especially for the tagged runtime-publication lane.
- [ ] Decide whether active generation cancellation should cancel the active model task immediately, then either fix it or document the intentional delayed-cancel behavior with evidence.
- [ ] Audit downstream `SpeakSwiftlyServer` HTTP/MCP exposure for retained file generation, batch generation, clone creation, profile export, runtime queue controls, model reload/unload, backend switching, and system-profile authoring.
- [ ] Harden system-profile seeding by revalidating manifest-loaded profile names before destination path construction, even when the source is a bundled or configured resource root.
- [ ] Harden manifest-loaded artifact filenames for profile reference audio and Qwen conditioning artifacts so tampered manifests cannot point reads outside the profile directory.
- [ ] Decide whether voice clone source paths and profile export output paths need package-level root policies or whether downstream hosts should gate those trusted-caller operations explicitly.
- [ ] Keep the security audit report, validation closure, and any follow-up fixes linked from the relevant release notes so future maintainers can see which rows were fixed, deferred, or intentionally host-owned.

### Exit Criteria

- [ ] All reportable audit findings are fixed or intentionally accepted with durable rationale.
- [ ] Deferred storage hardening rows have either package-level validation or a documented reason they remain trusted-resource assumptions.
- [ ] Downstream host exposure has been reviewed so local trusted-caller APIs are not accidentally treated as unauthenticated multi-client controls.

## Milestone 30: Generation Quality Telemetry And Guards

### Status

In Progress

### Scope

- [ ] Improve generation-quality telemetry so live playback can distinguish healthy buffer delivery from suspicious or runaway generated audio. ([#83](https://github.com/gaelic-ghost/SpeakSwiftly/issues/83))
- [ ] Add resource-pressure telemetry and conservative low-memory gates around Qwen generation work so the runtime can fail clearly before memory pressure becomes an operator-visible playback or process failure. ([#82](https://github.com/gaelic-ghost/SpeakSwiftly/issues/82))
- [ ] Start with Qwen3 live generation while keeping audio-derived metrics reusable across backends.
- [ ] Prefer a staged rollout: trace-only metrics first, warning events second, conservative cutoff behavior only after thresholds have evidence.
- [ ] Keep the first guard point before generated sample chunks are scheduled into `AVAudioPlayerNode`, with playback drain and rebuffer telemetry as supporting evidence.

### Tickets

- [x] Add a trace-only generated-audio quality monitor for live sample chunks before playback buffer scheduling.
- [x] Capture per-request and per-chunk metrics such as generated duration, clipping ratio, near-silence ratio, DC offset, zero-crossing rate, repeated-window similarity, chunk cadence, and boundary jump before smoothing.
- [ ] Correlate Qwen quality metrics with synthesis token/info/audio events, streaming interval, planned text chunks, prepared conditioning, and generation parameters.
- [x] Promote high-signal suspicious patterns into request-scoped warning events with concrete operator-facing messages.
- [ ] Collect warning telemetry from live-service use before enabling any cutoff behavior, especially `playback_generation_quality_warning` events from real Qwen usage.
- [ ] Use collected warning logs to tune thresholds and decide whether duration-budget, repeated-window, clipping, DC-offset, or non-finite-sample signals need different severities.
- [ ] Add conservative cutoff behavior for high-confidence runaway patterns after trace data proves the thresholds.
- [ ] Capture memory-pressure signals before and during generation, including available memory, resident-model state, active generation count, queued work, and any low-memory warnings that should block new retained or live generation requests.
- [ ] Define a clear low-memory rejection path that emits a specific operator-facing error instead of allowing generation to start when the current device does not have enough headroom.
- [ ] Keep raw spoken request text out of normal quality logs while preserving enough context for debugging.
- [ ] Use `docs/maintainers/generation-quality-guards-plan-2026-05-30.md` and `docs/maintainers/qwen-sampling-headroom-report-2026-04-24.md` as the initial planning notes for the implementation pass.

### Exit Criteria

- [ ] Maintainers can inspect generation-quality metrics for live Qwen requests without relying on listening alone.
- [ ] Suspicious generation patterns produce clear warnings before any hard cutoff is enabled.
- [ ] High-confidence runaway generations can be cancelled with a specific failure reason instead of being allowed to continue indefinitely.

## Milestone 31: macOS Retrench And Mobile Split

### Status

In Progress

### Scope

- [x] Return `SpeakSwiftly` package metadata and current support docs to a clearly macOS-only local speech worker package.
- [ ] Keep `SpeakSwiftlyServer` macOS-only and aligned with the streamlined `SpeakSwiftly` surface.
- [ ] Prepare `TextForSpeech` as the shared normalization and profile foundation for `SpeakSwiftlyMobile` after conditioning any macOS-only behavior behind explicit platform checks or injectable providers.
- [ ] Start `SpeakSwiftlyMobile` as a separate iOS app that depends on `TextForSpeech` and owns its mobile Core ML speech engine directly.

### Tickets

- [x] Remove the current iOS support promise from `SpeakSwiftly` package metadata, README wording, API docs, and maintainer docs so the package no longer advertises an unsupported mobile runtime.
- [ ] Delete or archive `SpeakSwiftly` iOS playback-only support that is no longer part of the macOS package contract.
- [ ] Audit `TextForSpeech` for macOS-only behavior, especially summarization-provider defaults, persistence defaults, filesystem assumptions, and any Apple-framework availability checks that could affect an iOS app consumer.
- [ ] Condition macOS-only `TextForSpeech` behavior with explicit platform checks or injected providers while preserving the existing iOS package platform support.
- [ ] Keep `TextForSpeech` focused on speech-safe text normalization, built-in profiles, custom profile persistence, and profile-driven pronunciation overrides rather than moving speech generation or playback into it.
- [ ] Define the initial `SpeakSwiftlyMobile` dependency shape as `TextForSpeech` plus app-owned Core ML model catalog, model loading, iOS audio-session ownership, and a narrow speak-text flow.
- [ ] Defer any new shared package until both the macOS package and mobile app prove real duplication that cannot belong cleanly in `TextForSpeech`.

### Exit Criteria

- [ ] `SpeakSwiftly` and `SpeakSwiftlyServer` are documented and packaged as macOS-only again.
- [ ] `TextForSpeech` can be consumed by `SpeakSwiftlyMobile` without inheriting macOS-only behavior or desktop speech-worker concepts.
- [ ] `SpeakSwiftlyMobile` has a documented first slice that uses `TextForSpeech` for text conditioning and keeps iOS Core ML generation inside the app until a shared boundary is earned.

## Milestone 32: Qwen-Only Output Modularization

### Status

In Progress

### Scope

- [x] Record the major-version plan for removing Marvis and Chatterbox without compatibility shims.
- [x] Keep Qwen3 as the only supported generation family in the public backend configuration surface.
- [x] Split generated-audio output primitives into Core, Playback, File, HTTP, and Network module targets.
- [x] Model live speech as generation plus an output destination rather than assuming generation always means local playback.
- [ ] Finish transport adoption so HTTP response streams and LAN streaming can consume canonical generated-audio chunks outside the local playback path.
- [ ] Keep the current Qwen implementation working while the CoreML and Metal Flash Attention port remains a future generation-module swap.

### Tickets

- [x] Add a maintainer plan note under `docs/maintainers/` for the Qwen-only vNext cleanup.
- [x] Remove Marvis and Chatterbox backend values from normal configuration and request switching paths.
- [x] Add the canonical generated-audio chunk type, sample format, output errors, and stream adapter to `SpeakSwiftlyCore`.
- [x] Add local playback chunk consumption to `SpeakSwiftlyPlayback`.
- [x] Add retained WAV and AAC/M4A file encoding and generated-file storage to `SpeakSwiftlyFileAudioOutput`.
- [x] Add HTTP-friendly raw PCM payload framing with metadata headers to `SpeakSwiftlyHTTPAudioOutput`.
- [x] Add Network.framework audio frame encoding and Bonjour audio-receiver discovery primitives to `SpeakSwiftlyNetworkAudioOutput`.
- [x] Add `generate.speech(... output:)` to the typed runtime surface.
- [x] Add `generate.audioStream(...)` so host boundaries can consume successful canonical chunk streams instead of failed request handles.
- [x] Add memory-backed recent generated-audio replay on `runtime.playback`, including replay-one, replay-all, bounded retention configuration, and JSONL/tool controls.
- [x] Remove the local `request_context.reqPurpose: "audioStream"` rejection guard after TextForSpeech removed `RequestPurpose.audioStream` in [gaelic-ghost/TextForSpeech#33](https://github.com/gaelic-ghost/TextForSpeech/issues/33).
- [x] Add tests for canonical chunks, local playback chunk consumption, HTTP frames, Network frame round trips, Bonjour metadata, discovered-destination selection, and removed backend rejection.
- [x] Add organized unit and integration matrix coverage for every Qwen3 size and quant variant so routing, decoding, configuration, resident repo mapping, generation policy, and runtime scheduling stay covered without real-model downloads in the default suite.
- [x] Add runtime routing tests for request-scoped nonlocal output failure paths until real transports are wired.
- [x] Remove stale Marvis and Chatterbox E2E lanes and validation-lane references instead of skipping them.
- [x] Add initial detailed latency and benchmarking coverage for Qwen3 local playback and generated-output paths, including first-audio latency, chunk cadence, total generation time, memory pressure, prepared-conditioning cache behavior, and warning counts for each current size and quant variant.
- [x] Use `docs/maintainers/qwen-quant-benchmark-and-default-selection-plan.md` as the starting plan for the fresh Qwen3 quant benchmark branch across Gale's MacBook Pro and Mac mini.
- [ ] Expand Qwen3 quant benchmarking across macOS power modes, battery versus AC state, sustained thermal states, unrelated CPU load, unrelated GPU or MLX load, unrelated memory pressure, active live-service residency, and longer audible fixtures before deciding automatic backend selection.
- [ ] Use the Qwen3 benchmark results to decide which quant variants should remain in the supported public matrix and slim any variants that do not justify their maintenance, download, memory, latency, or quality tradeoff.
- [ ] Design a hardware-sensitive default backend selection system that records detected device facts, explains its selected Qwen backend, and still allows explicit operator configuration.
- [ ] Harden `SpeakSwiftlyNetworkAudioOutput` after the first server receiver adoption by adding package-level LAN sender/receiver E2E coverage for real chunk streams, transport failure telemetry, receiver/sender cancellation, and reconnection behavior that does not require two Macs in default validation.
- [ ] Clarify inbound LAN playback policy in `SpeakSwiftlyPlayback`, including whether concurrent inbound streams are queued, mixed, rejected, or delegated to a host-provided policy.
- [ ] Extend LAN discovery and transport observability so hosts can show discovered receiver metadata, listener state, active stream counts, failed handshakes, and request-scoped transport errors without pretending remote output is a local playback device.
- [ ] Plan the post-alpha security model for LAN audio beyond a shared token, including pairing, token rotation, Keychain storage, and per-device trust without committing secrets to sample config.
- [ ] Draft and review `v11.0.0-alpha.1` release notes before starting the release script.
- [ ] Validate downstream `SpeakSwiftlyServer` adoption separately after the package output modules settle.

### Exit Criteria

- [ ] The package exposes Qwen-only generation plus selectable local playback, HTTP response stream, and LAN audio output destinations.
- [ ] Removed backend names fail clearly from persisted config and worker requests.
- [ ] Unit and integration tests cover module boundaries without requiring two real Macs for default validation.
- [ ] The prerelease notes clearly call out breaking changes, migration notes, verification performed, and follow-up server adoption work.
## Milestone 33: First-Party Core ML Qwen3-TTS Port

### Status

Research

### Scope

- [ ] Evaluate a first-party Core ML Qwen3-TTS conversion instead of adopting the current FluidInference artifact as-is.
- [ ] Preserve the existing runtime ownership model while deciding whether Core ML deserves a real backend slot beside the MLX-backed Qwen, Marvis, and Chatterbox paths.
- [ ] Own the conversion split points, tokenizer boundary, fixed-shape cache policy, precision choices, and stage-specific compute-unit assignments explicitly enough that performance claims are measurable.
- [ ] Keep the first implementation as a standalone probe until tokenizer parity, tensor parity, performance, memory, and audio quality evidence justify runtime integration.

### Tickets

- [ ] Inventory upstream Qwen3-TTS inference from source: text tokenizer, prompt assembly, language and control tokens, reference conditioning, codec token flow, decode loop, stop conditions, and audio decoder expectations.
- [ ] Produce a tiny Python golden path for one English sentence and one clone/reference path when practical, saving intermediate tensor shapes, token IDs, codec frames, sample rate, and final WAV output.
- [ ] Decide the first Core ML graph boundaries deliberately, including which work remains Swift-side and which stages should become separate Core ML models.
- [ ] Convert one stage at a time with Core ML Tools, recording deployment target, input/output names, fixed shapes, cache layout, precision, and known unsupported or numerically sensitive operations.
- [ ] Build a standalone Swift probe that loads converted artifacts, checks per-stage tensor parity against the Python golden path, and emits structured timing and memory metrics.
- [ ] Measure stage-specific `MLComputeUnits` choices on Gale's Apple silicon hardware, including `cpuAndGPU`, `cpuAndNeuralEngine`, `all`, and `cpuOnly` where safe.
- [ ] Use Instruments and Core ML performance reports to verify actual CPU, GPU, and Neural Engine dispatch instead of inferring dispatch from configuration alone.
- [ ] Build a calibration-data lane for Core ML compression, starting with decoder-only audio-code calibration from open speech datasets and widening later to full-stack prompts, code histories, and reference-conditioning cases.
- [ ] Probe W8A8 quantization for stages where Core ML Tools and Instruments show a realistic path to M4 Neural Engine execution.
- [ ] Evaluate Swift/Metal FlashAttention as a separate custom-GPU-kernel lane for autoregressive Qwen attention if Core ML or MLX dispatch overhead becomes the limiting factor.
- [ ] Evaluate whether autoregressive work can be batched, bucketed, prefetched, or otherwise shaped to avoid tiny per-token prediction overhead.
- [ ] Compare the first-party Core ML probe against the existing SpeakSwiftly Qwen MLX benchmark lane using matched input text, voice strategy, output duration, real-time factor, memory, startup time, and audible quality notes.
- [ ] Decide whether the result should become a hidden experimental backend, stay probe-only, feed `SpeakSwiftlyMobile`, or be dropped with evidence.

### Stage Notes

- The current FluidInference Qwen3-TTS Core ML artifact is useful research input, but it is not the target architecture. Its closed Swift backend PR lacked a built-in tokenizer and pinned core generation stages away from the Neural Engine, including one CPU-only decoder path because other compute-unit choices produced NaNs.
- A first-party port is a durable backend-extension investigation, not a local implementation detail. It only earns runtime integration if it proves a concrete advantage or a distinct Apple-platform deployment story.
- The simpler extension path of adding another MLX model repo is not enough because this work changes inference engine, artifact layout, conversion ownership, and profiling surface.
- The decoder calibration-data lane now has a first checked-in LibriTTS-R audio-code fixture for the 12 Hz speech-tokenizer decoder: three 24 kHz read-speech samples, 185 total code steps, 16 quantizers, and suggested first bucket sizes of 40, 72, and 88 code steps.
- The Swift/Metal FlashAttention package is relevant to a possible custom talker/code-predictor GPU path, but it is not a drop-in Core ML accelerator. The package builds locally, while runtime Metal JIT compilation currently fails under macOS 26.5 and Xcode 26.5 on private/removed simdgroup async-copy assembly hooks.
- Follow-up FlashAttention triage found that `mpsops/mps-flash-attention` moves past the original runtime source parser problem by using MetalASM and `makeLibrary(data:)`, but local pipeline creation still crashes inside the AGX compiler service. The ccv-backed `metal-flash-sdpa` path runs non-causal attention accurately, but local causal tests fail by multi-point differences, so neither path is ready for Qwen autoregressive attention.
- Keep detailed notes in `docs/maintainers/coreml-qwen3tts-port-plan-2026-05-31.md` and preserve the earlier external-artifact review in `docs/maintainers/coreml-qwen3tts-evaluation-2026-05-31.md`.

### Exit Criteria

- [ ] The repository contains a documented decision on whether a first-party Core ML Qwen3-TTS port is technically worth continuing.
- [ ] If continued, the branch has a runnable probe with reproducible conversion inputs, shape and parity notes, timing output, and device-dispatch evidence.
- [ ] If not continued, the repository records the blocking evidence clearly enough that future backend work does not rediscover the same failure mode.

## Backlog Candidates

- Add playback of generated file artifacts so callers can play retained WAV or M4A outputs later without regenerating speech.
- Review the generated-file flow, especially whether `Generate.audio` should hand callers richer file/path artifacts or stream/file handles instead of making every host recover paths from completion payloads.
- Run a soon-ish overall public API review after recent replay, file audio, output destinations, and LAN receiver adoption have settled enough to judge naming and ergonomics together.
- Notification-linked priority playback is a backlog candidate, not an active milestone. It should only return to Active Milestones after a current issue or implementation plan proves the package should own notification-triggered priority playback instead of leaving that concern to a parent app.
- Revisit richer public playback event types after the v11 output-destination split settles, especially whether local playback, HTTP response streams, and LAN streams need distinct typed event surfaces or one shared generated-audio observation model. ([#45](https://github.com/gaelic-ghost/SpeakSwiftly/issues/45))
- Re-test the startup-side playback preload allocator warning against the Qwen-only vNext runtime and close it if the eager playback-preload path is no longer reproducible. ([#7](https://github.com/gaelic-ghost/SpeakSwiftly/issues/7))

## History

### 2026-05-06 typed observation API cleanup

- Milestone 28 was condensed out of Active Milestones after the breaking typed Swift observation cleanup landed without compatibility shims. The public package surface now uses `RequestEvent` / `RequestState` / `RequestUpdate` / `RequestSnapshot`, per-request `SynthesisEvent` / `SynthesisUpdate`, generation-queue `GenerateEvent` / `GenerateState` / `GenerateUpdate` / `GenerateSnapshot`, singleton playback `PlaybackEvent` / `PlaybackState` / `PlaybackUpdate` / `PlaybackSnapshot`, and singleton runtime `RuntimeEvent` / `RuntimeState` / `RuntimeUpdate` / `RuntimeSnapshot`.
- The typed runtime handles now expose `runtime.generate`, `runtime.playback`, and `runtime` `updates()` plus `snapshot()` surfaces. Removed typed Swift names include `runtime.player`, `SpeakSwiftly.Player`, `GenerationEvent`, `GenerationEventUpdate`, `runtime.status()`, `runtime.overview()`, `Player.list()`, `Player.state()`, and `runtime.statusEvents()`.
- JSONL worker compatibility remains intentionally stable for `worker_status`, `get_runtime_overview`, and existing playback-state response shapes. Internal `WorkerStatusEvent`, `WorkerRuntimeOverview`, and `WorkerPlaybackStateSnapshot` models preserve the wire contract while public typed Swift consumers use the new observation vocabulary.
- DocC, `CONTRIBUTING.md`, `AGENTS.md`, maintainer API-audit notes, and `v5.0.0` migration notes were updated in the same pass. Downstream `SpeakSwiftlyServer` adoption remains explicit release-hardening work under Milestone 26.

### 2026-05-03 TextForSpeech 0.19 simplification

- Milestone 27 was condensed out of Active Milestones after the `TextForSpeech` `0.19.0` simplification landed on the `v5.0.0-rc.1` release-candidate branch. The package now uses `TextForSpeech.SourceFormat` directly only for whole-source generation, carries request metadata and path context through `SpeakSwiftly.RequestContext`, and removes the public `SpeakSwiftly.InputTextContext` typed surface.
- The current JSONL generation wire shape uses `request_context` for request metadata and path context, while `TextForSpeech` detects source structure from request text and path context. Removed generation-context keys such as `source_format`, `input_text_context`, `text_format`, and `nested_source_format` are rejected with an explicit invalid-request diagnostic instead of being silently ignored.
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
- Milestone 22 was later superseded by the vNext Qwen-only decision. Its remaining Marvis tuning questions are preserved as historical context, not active release-hardening work.
- Milestone 16 no longer tracks clone auto-transcription as active because clone transcript inference now lives in the shared clone-profile creation path. Earlier multi-backend E2E coverage is historical; the vNext supported generation family is Qwen-only.

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
  Result: the immediate controller-owned playback-state fix landed and the
  architecture cleanup landed. The later vNext Qwen-only decision superseded
  the remaining first-request Marvis tuning follow-up.
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
