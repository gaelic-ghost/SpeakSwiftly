# CONTRIBUTING

Contributor-facing project notes for SpeakSwiftly. This document holds the deeper architecture, repository workflow, operator guidance, and verification detail that would make the public [README.md](README.md) too dense.

## Purpose

SpeakSwiftly is intentionally two things at once:

- a typed Swift runtime library through `SpeakSwiftlyCore`
- a long-lived JSONL worker executable through `SpeakSwiftly`

The repository tries to keep those two public surfaces aligned without forcing either one to become a compatibility wrapper over the other. Swift callers should get direct, readable APIs. Process-boundary callers should get stable JSONL operation names and predictable event semantics.

Keep the doc split clean:

- [README.md](README.md) should stay focused on setup, usage, public API names, and baseline verification
- this document should hold architecture notes, repository workflow, operator behavior, full wire examples, and extended verification paths

## Runtime Shape

The current intended runtime shape is:

- a long-lived executable owned by another process
- newline-delimited JSON over `stdin` and `stdout`
- resident backend selection between `qwen3`, `qwen3_custom_voice`, and `marvis`
- stored voice profiles selected by name
- text-normalization profiles that can be edited independently
- persisted runtime configuration for the preferred resident backend
- structured progress, queue, and status events on `stdout`
- structured operator diagnostics on `stderr`

Resident runtime state is now explicitly observable as:

- `speech_backend`
- `resident_state`
- `stage`

That split matters:

- `speech_backend` says which backend family is selected
- `resident_state` says whether resident models are loaded, warming, unloaded, or failed
- `stage` is the worker-status event label currently emitted on the wire

## Naming Conventions

### Swift Library API

The typed Swift surface uses Cocoa-style method names and one root runtime object:

- `SpeakSwiftly.liftoff(configuration:)` is the single startup entry point
- `SpeakSwiftly.liftoff(...)` returns `SpeakSwiftly.Runtime`
- `runtime.generate`
- `runtime.player`
- `runtime.voices`
- `runtime.normalizer`
- `runtime.jobs`
- `runtime.artifacts`

Those concern handles should stay lightweight views over shared runtime state, not separate subsystems with their own lifecycle or duplicated ownership.

Current typed-surface conventions:

- `SpeakSwiftly.Configuration` carries startup inputs such as `speechBackend`, `qwenConditioningStrategy`, and an optional `textNormalizer`
- live playback and file rendering are separate generation calls, with `Generate.speech(...)` and `Generate.audio(...)`
- generation-queue inspection lives under `Jobs`
- playback-queue inspection lives under `Player.list(...)`
- resident runtime controls use `status(id:)`, `switchSpeechBackend(to:id:)`, `reloadModels(id:)`, and `unloadModels(id:)`
- decode/result model memberwise initializers should stay internal unless callers have a concrete need to construct those values themselves
- `BatchItem` remains public only because batch submission is still intentionally caller-authored at that layer

Treat this as a durable building-block cleanup, not as a compatibility layer. Do not preserve legacy public shims for the old `live(...)`, job-multiplexed generation, or mismatched queue-query placement unless Gale explicitly asks for that compromise.

`SpeakSwiftly.Name` is the intended semantic name type for stable operator-facing resource names in the library surface.

For voice-profile creation, the intended Swift shape is one overloaded `Voices.create(...)` entry point:

- `create(design named: Name, from: String, vibe: SpeakSwiftly.Vibe, voice: String, outputPath: String?)`
- `create(clone named: Name, from: URL, vibe: SpeakSwiftly.Vibe, transcript: String?)`

### JSONL Wire API

The JSONL worker surface uses stable snake_case, verb-first operation names.

Use these naming rules for new wire operations:

- read one resource or snapshot: `get_*`
- read many resources or a queue snapshot: `list_*`
- create a new resource: `create_*`
- partially mutate a resource: `update_*`
- replace a whole resource payload: `replace_*`
- delete a resource: `delete_*`
- keep literal lifecycle or control verbs like `generate_*`, `set_*`, `reload_*`, `unload_*`, `pause`, `resume`, `clear_*`, `cancel_*`, `load_*`, `save_*`, and `reset_*` when the operation is not best described as CRUD

Current resident runtime controls on the wire are:

- `"get_status"`
- `"set_speech_backend"`
- `"reload_models"`
- `"unload_models"`

Current examples of the broader convention are:

- `get_generated_file`
- `list_generated_files`
- `get_active_text_profile`
- `get_text_profile_style`
- `list_text_profiles`
- `list_text_replacements`
- `set_text_profile_style`
- `create_text_replacement`
- `clear_text_replacements`
- `update_voice_profile_name`
- `reroll_voice_profile`
- `replace_text_profile`
- `delete_voice_profile`

The wire shape is intentionally more literal and transport-oriented than the Swift surface, and it should stay mechanically consistent enough that a caller can often guess an operation name correctly before looking it up.

## Runtime Configuration

`SpeakSwiftly.Configuration` is the typed runtime-startup surface. It now carries the preferred resident `speechBackend`, the Qwen conditioning strategy, and an optional startup `textNormalizer`.

The current prepared-conditioning integration depends on a temporary frozen `mlx-audio-swift` fork pin while the matching `Qwen3TTS` API is being upstreamed. Keep that pin exact and intentional; do not loosen it back to a moving branch dependency.

Default persisted configuration path:

- macOS production default: `~/Library/Application Support/SpeakSwiftly/configuration.json`
- macOS debug and package-test default: `~/Library/Application Support/SpeakSwiftly-Debug/configuration.json`
- with `SPEAKSWIFTLY_PROFILE_ROOT=/custom/profiles`: `/custom/configuration.json`

The same namespace split applies to the default profile store and `text-profiles.json`, so debug builds, local package tests, and production runs do not reuse the same local storage root unless you explicitly point them at one with `SPEAKSWIFTLY_PROFILE_ROOT`.

Backend resolution precedence is:

1. explicit `configuration.speechBackend` passed to `SpeakSwiftly.liftoff(...)`
2. `SPEAKSWIFTLY_SPEECH_BACKEND`
3. persisted `configuration.json`
4. fallback `.qwen3`

Qwen conditioning strategy values are:

- `.legacyRaw`: keep passing raw `refAudio` and `refText` into the resident Qwen model on every request
- `.preparedConditioning`: prepare Qwen reference conditioning once, persist it on the profile, cache it in memory after load, and reuse it on later requests

The runtime currently reads `qwenConditioningStrategy` only from the explicit or persisted `SpeakSwiftly.Configuration` surface. There is no separate environment-variable override for that setting.

## Queueing and Resident Controls

SpeakSwiftly now has a clearer scheduler contract around resident state:

- generation work requires resident models
- resident-control barriers mutate resident state
- immediate control reads do not enter the serialized generation queue

Current resident-control barriers are:

- backend switching
- model reload
- model unload

The important behavior is:

- accepted generation work can be parked while resident models are unavailable
- resident-control barriers can still run when they are the operations that restore residency
- unloading resident models does not deadlock the queue
- parked work resumes in accepted order after residency returns

Current parked queue reason for resident-dependent work while unloaded:

- `waiting_for_resident_models`

Current resident-status stages:

- `warming_resident_model`
- `resident_model_ready`
- `resident_models_unloaded`
- `resident_model_failed`

## JSONL Reference

Representative request shapes:

```json
{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1c","op":"generate_speech","text":"stderr: broken pipe","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}
{"id":"req-1d","op":"generate_speech","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}
{"id":"req-1e","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}
{"id":"req-1f","op":"generate_audio_file","text":"Save this one for later playback.","profile_name":"default-femme"}
{"id":"req-1g","op":"generate_batch","profile_name":"default-femme","items":[{"text":"First saved file."},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs"}]}
{"id":"req-1h","op":"get_generated_file","artifact_id":"req-1f-artifact-1"}
{"id":"req-1i","op":"list_generated_files"}
{"id":"req-1j","op":"get_generated_batch","batch_id":"req-1g"}
{"id":"req-1k","op":"list_generated_batches"}
{"id":"req-1l","op":"get_generation_job","job_id":"req-1f"}
{"id":"req-1m","op":"list_generation_jobs"}
{"id":"req-1n","op":"expire_generation_job","job_id":"req-1g"}
{"id":"req-2","op":"create_voice_profile_from_description","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"A warm, bright, feminine narrator voice.","output_path":"/tmp/bright-guide.wav"}
{"id":"req-3","op":"list_voice_profiles"}
{"id":"req-4","op":"delete_voice_profile","profile_name":"bright-guide"}
{"id":"req-5","op":"get_active_text_profile"}
{"id":"req-6","op":"get_text_profile_style"}
{"id":"req-7","op":"set_text_profile_style","text_profile_style":"compact"}
{"id":"req-8","op":"list_text_profiles"}
{"id":"req-8a","op":"list_text_replacements","text_profile_name":"logs"}
{"id":"req-9","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs"}
{"id":"req-10","op":"create_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}
{"id":"req-10a","op":"clear_text_replacements","text_profile_name":"logs"}
{"id":"req-11","op":"replace_active_text_profile","text_profile":{"id":"ops","name":"Ops","replacements":[{"id":"ops-rule","text":"stdout","replacement":"standard output","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]}}
{"id":"req-status","op":"get_status"}
{"id":"req-switch","op":"set_speech_backend","speech_backend":"marvis"}
{"id":"req-reload","op":"reload_models"}
{"id":"req-unload","op":"unload_models"}
```

Representative response and event shapes:

```json
{"event":"worker_status","stage":"warming_resident_model","resident_state":"warming","speech_backend":"qwen3"}
{"id":"req-1","event":"queued","reason":"waiting_for_resident_model","queue_position":1}
{"id":"req-2","event":"queued","reason":"waiting_for_active_request","queue_position":2}
{"event":"worker_status","stage":"resident_model_ready","resident_state":"ready","speech_backend":"qwen3"}
{"id":"req-unload","ok":true,"status":{"event":"worker_status","stage":"resident_models_unloaded","resident_state":"unloaded","speech_backend":"qwen3"},"speech_backend":"qwen3"}
{"id":"req-after-unload","event":"queued","reason":"waiting_for_resident_models","queue_position":1}
{"id":"req-reload","ok":true,"status":{"event":"worker_status","stage":"resident_model_ready","resident_state":"ready","speech_backend":"qwen3"},"speech_backend":"qwen3"}
{"id":"req-1","event":"started","op":"generate_speech"}
{"id":"req-1","event":"progress","stage":"buffering_audio"}
{"id":"req-1","event":"progress","stage":"preroll_ready"}
{"id":"req-1","event":"progress","stage":"playback_finished"}
{"id":"req-1","ok":true}
{"id":"req-1f","ok":true,"generated_file":{"artifact_id":"req-1f-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"},"generation_job":{"job_id":"req-1f","job_kind":"file","state":"completed","items":[{"artifact_id":"req-1f-artifact-1","text":"Save this one for later playback.","text_profile_name":null,"text_context":null,"source_format":null}]}}
```

Raw JSONL callers should send absolute filesystem paths for path fields, or include `cwd` when using relative paths. SpeakSwiftly resolves those paths against caller-provided context, not the worker launch directory.

When JSONL naming changes, update this file and `README.md` in the same pass so the public contract stays aligned across both docs.

## Runtime Behavior Notes

Current live-playback behavior:

- `generate_speech` loads the stored profile first, then routes resident generation through the active backend. `qwen3` uses stored profile reference audio and transcript, while `marvis` uses stored profile vibe to select the already-warm built-in preset voice.
- The built-in text style is a separate persisted runtime setting from the active custom text profile. JSONL callers can inspect it with `get_text_profile_style` and update it with `set_text_profile_style`.
- Live playback stays a single-speaker path on one worker. When one audible live request is already playing, later live requests can still be accepted and queued immediately, but their generation waits until the active live playback drains before the next live request starts.
- `generate_audio_file` follows that same backend-routing path, then saves the completed WAV under the generated-file store instead of scheduling playback.
- Marvis resident warmup keeps both `conversational_a` and `conversational_b` loaded at once because the model is small enough that preset switching does not need another preload cycle.
- Profile `vibe` currently drives Marvis routing like this: `.femme` -> `conversational_a`, `.androgenous` -> `conversational_a`, `.masc` -> `conversational_b`.
- Resident generation currently streams chunks at the `0.18` cadence.
- Playback uses adaptive duration-based startup and low-water thresholds rather than a fixed one-chunk gate.

Current generated-file behavior:

- file jobs use the request id as the durable job id, not the artifact id
- single-file generation resolves its saved artifact id as `<jobID>-artifact-1`
- batch generation resolves one saved artifact id per item, using caller-provided `artifact_id` when present and `<batchID>-artifact-N` otherwise
- saved artifacts live in the runtime-managed generated-file store, not at a caller-provided output path
- expired batch reads stay inspectable through `get_generated_batch` and `list_generated_batches`, but return an empty `artifacts` list because the saved files are intentionally gone
- expired file and batch jobs keep artifact references inside `get_generation_job` and `list_generation_jobs` so operators can still see what existed before cleanup

## Repository Layout

The package source tree is organized by responsibility:

- `Sources/SpeakSwiftly/API` contains the public package-facing library surface
- `Sources/SpeakSwiftly/Generation` contains generation and voice-profile logic
- `Sources/SpeakSwiftly/Normalization` contains `SpeakSwiftly.Normalizer` and text-normalization logic
- `Sources/SpeakSwiftly/Playback` contains the playback subsystem
- `Sources/SpeakSwiftly/Runtime` contains worker-runtime internals such as protocol decoding, request orchestration, lifecycle, and emission

The test suite mirrors the source tree:

- `Tests/SpeakSwiftlyTests/API/LibrarySurfaceTests.swift`
- `Tests/SpeakSwiftlyTests/Generation/ModelClientsTests.swift`
- `Tests/SpeakSwiftlyTests/Generation/ProfileStoreTests.swift`
- `Tests/SpeakSwiftlyTests/Runtime/WorkerProtocolTests.swift`
- `Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimeQueueingTests.swift`
- `Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimeGenerationTests.swift`
- `Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimePlaybackTests.swift`
- `Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimeControlSurfaceTests.swift`
- `Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimeShutdownTests.swift`
- `Tests/SpeakSwiftlyTests/E2E/SpeakSwiftlyE2ETests.swift`

## Repository Workflow

This repository is the source-of-truth development home for SpeakSwiftly.

The intended ownership model is:

- this repository remains the primary development home for [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly)
- the larger [`speak-to-user`](https://github.com/gaelic-ghost/speak-to-user) repository consumes SpeakSwiftly as a Git submodule under `packages/SpeakSwiftly`
- feature work lands here first, and the consuming repository updates its submodule pointer when it is ready to adopt a newer revision

Older adjacent consumers such as [`speak-to-user-mcp`](https://github.com/gaelic-ghost/speak-to-user-mcp) and [`speak-to-user-server`](https://github.com/gaelic-ghost/speak-to-user-server) should point at one shared published runtime directory instead of relying on copy hooks or raw DerivedData guesses.

## Development Guidance

Keep the package small and concrete.

- prefer direct data flow over helper abstractions
- keep the executable as the boundary instead of inventing extra internal service layers
- let `mlx-audio-swift` own model loading and generation whenever its existing surface is sufficient
- treat `stdin` and `stdout` as the worker contract and `stderr` as operator-facing logging
- keep stored profiles simple and inspectable: profile metadata, source text, and reference audio on disk
- add new packages only when they clearly simplify the code

## Verification

Baseline package verification:

```bash
swift build
swift test
```

Publish and verify a real Xcode-backed runtime:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Release
```

Refresh the vendored MLX shader bundle after an `mlx-audio-swift` or `mlx-swift` upgrade:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Release
sh scripts/repo-maintenance/update-vendored-mlx-bundle.sh
```

Opt-in real-model e2e coverage. The root `SpeakSwiftlyE2ETests` suite is serialized on purpose, so the full e2e surface always runs one request flow at a time.

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

One-shot qwen resident `generate_speech` verification:

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests/QwenWorkflowSuite/voiceDesignSilentThenAudible
```

Prepared-conditioning qwen verification. This boots the worker in `prepared_conditioning` mode, confirms the first request persists a stored Qwen conditioning artifact on the profile, then restarts the worker and confirms the second request reloads that stored artifact instead of rebuilding it from raw reference inputs:

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests/QwenWorkflowSuite/preparedConditioningPersistsAndReloadsAcrossWorkerRestart
```

Opt-in MLX-backed persistence unit coverage. The plain SwiftPM runner does not ship the Metal bundle needed for direct MLX tensor persistence round-trips, so these tests stay out of the default `swift test` pass and should be run only when you explicitly want that narrow coverage:

```bash
SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1 swift test --filter preparedQwenConditioning
```

Force audible playback in the e2e suite:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_AUDIBLE_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

Retained real-model run artifacts live under `.local/e2e-runs`.

Chunk-level trace during e2e:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests
```

Long deep-trace playback probe:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 swift test --filter SpeakSwiftlyE2ETests/longCodeHeavy
```

Opt-in qwen resident benchmark comparison:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1 swift test --filter SpeakSwiftlyE2ETests/QwenBenchmarkSuite
```

Run multiple comparison samples per backend:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS=3 swift test --filter SpeakSwiftlyE2ETests/QwenBenchmarkSuite
```

Each benchmark run persists a timestamped JSON summary under `.local/benchmarks` and refreshes `.local/benchmarks/qwen-resident-benchmark-latest.json` for quick inspection.

Section-aware weird-text deep-trace probes:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/segmentedWeirdText
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/reversedSegmentedWeirdText
```

Section-aware conversational prose deep-trace probes:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/segmentedConversationalProse
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/reversedSegmentedConversationalProse
```

If a real worker run fails with `default.metallib` or `mlx-swift_Cmlx.bundle` errors, the runtime was almost certainly launched from a plain SwiftPM build instead of a published Xcode-backed runtime directory. Re-publish the runtime and launch through the published `run-speakswiftly` script or stable alias.

The library target also vendors one copy of `mlx-swift_Cmlx.bundle` under `Sources/SpeakSwiftly/Resources` so linked consumers can resolve the packaged MLX bundle and metallib through `SpeakSwiftly.SupportResources`. Keep that vendored bundle in sync with the pinned MLX dependency by refreshing it from the published Release runtime whenever the MLX stack changes.
