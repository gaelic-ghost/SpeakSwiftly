# CONTRIBUTING

Contribution guide and contributor-facing project notes for SpeakSwiftly. This document holds the deeper architecture, repository workflow, operator guidance, and verification detail that would make the public [README.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/README.md) too dense.

## Purpose

SpeakSwiftly is intentionally two things at once:

- a typed Swift runtime library through `SpeakSwiftlyCore`
- a long-lived JSONL worker executable through `SpeakSwiftly`

The repository tries to keep those two public surfaces aligned without forcing either one to become a compatibility wrapper over the other. Swift callers should get direct, readable APIs. Process-boundary callers should get stable JSONL operation names and predictable event semantics.

## Public Surface Split

The public-facing [README.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/README.md) should stay focused on:

- what the project is
- why it exists
- how to set it up
- how to use it
- what the public API surfaces are called
- how to perform baseline verification

This document should hold:

- deeper architecture and queueing details
- repository layout and development expectations
- contributor and integration guidance
- full wire examples and operational behavior notes
- extended verification and forensic workflows
- rationale for public naming and runtime control design

## Runtime Shape

The current intended runtime shape is:

- a long-lived executable owned by another process
- newline-delimited JSON over `stdin` and `stdout`
- resident backend selection between `qwen3` and `marvis`
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

Current resident runtime controls intentionally use Cocoa-style method names:

- `status(id:)`
- `switchSpeechBackend(to:id:)`
- `reloadModels(id:)`
- `unloadModels(id:)`

The intent behind this shape is:

- noun-driven and discoverable from `SpeakSwiftly.Runtime`
- explicit enough to read well at the call site
- aligned with the runtime concept being controlled, not the JSON transport name

### JSONL Wire API

The JSONL worker surface uses stable snake_case, verb-first operation names.

Use these naming rules for new wire operations:

- read one resource or snapshot: `get_*`
- read many resources or a queue snapshot: `list_*`
- create a new resource: `create_*`
- partially mutate a resource: `update_*`
- replace a whole resource payload: `replace_*`
- delete a resource: `delete_*`
- keep literal lifecycle or control verbs like `queue_*`, `set_*`, `reload_*`, `unload_*`, `pause`, `resume`, `clear_*`, `cancel_*`, `load_*`, `save_*`, and `reset_*` when the operation is not best described as CRUD

Current resident runtime controls on the wire are:

- `"get_status"`
- `"set_speech_backend"`
- `"reload_models"`
- `"unload_models"`

Current examples of the broader convention are:

- `get_generated_file`
- `list_generated_files`
- `get_active_text_profile`
- `list_text_profiles`
- `create_text_replacement`
- `replace_text_profile`
- `delete_voice_profile`

The wire shape is intentionally more literal and transport-oriented than the Swift surface, and it should stay mechanically consistent enough that a caller can often guess an operation name correctly before looking it up.

## Runtime Configuration

`SpeakSwiftly.Configuration` is the typed runtime-preference surface. Right now it stores the preferred resident `speechBackend`.

Default persisted configuration path:

- macOS default: `~/Library/Application Support/SpeakSwiftly/configuration.json`
- with `SPEAKSWIFTLY_PROFILE_ROOT=/custom/profiles`: `/custom/configuration.json`

Backend resolution precedence is:

1. explicit `speechBackend:` passed to `SpeakSwiftly.live(...)`
2. explicit `configuration:` passed to `SpeakSwiftly.live(...)`
3. `SPEAKSWIFTLY_SPEECH_BACKEND`
4. persisted `configuration.json`
5. fallback `.qwen3`

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

## Typed Swift Notes

The typed `SpeakSwiftly.Runtime` generation and profile helpers currently include:

- `speak(text:with:as:textProfileName:textContext:sourceFormat:id:)`
- `createProfile(named:from:vibe:voice:outputPath:id:)`
- `createClone(named:from:vibe:transcript:id:)`
- `generatedFile(id:requestID:)`
- `generatedFiles(id:)`
- `generateBatch(_:with:id:)`
- `generatedBatch(id:requestID:)`
- `generatedBatches(id:)`
- `generationJob(id:requestID:)`
- `generationJobs(id:)`

The typed text-normalization helpers live on `SpeakSwiftly.Normalizer`:

- `activeProfile()`
- `baseProfile()`
- `profile(named:)`
- `profiles()`
- `effectiveProfile(named:)`
- `persistenceURL()`
- `loadProfiles()`
- `saveProfiles()`
- `createProfile(id:named:replacements:)`
- `storeProfile(_:)`
- `useProfile(_:)`
- `removeProfile(named:)`
- `reset()`
- `addReplacement(_:)`
- `addReplacement(_:toStoredProfileNamed:)`
- `replaceReplacement(_:)`
- `replaceReplacement(_:inStoredProfileNamed:)`
- `removeReplacement(id:)`
- `removeReplacement(id:fromStoredProfileNamed:)`

`runtime.normalizer` remains available as a compatibility alias to the injected normalizer object when callers already have a runtime in hand.

## JSONL Reference

Representative request shapes:

```json
{"id":"req-1","op":"queue_speech_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1c","op":"queue_speech_live","text":"stderr: broken pipe","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}
{"id":"req-1d","op":"queue_speech_live","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}
{"id":"req-1e","op":"queue_speech_live","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}
{"id":"req-1f","op":"queue_speech_file","text":"Save this one for later playback.","profile_name":"default-femme"}
{"id":"req-1g","op":"queue_speech_batch","profile_name":"default-femme","items":[{"text":"First saved file."},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs"}]}
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
{"id":"req-6","op":"list_text_profiles"}
{"id":"req-7","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs"}
{"id":"req-8","op":"create_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}
{"id":"req-9","op":"replace_active_text_profile","text_profile":{"id":"ops","name":"Ops","replacements":[{"id":"ops-rule","text":"stdout","replacement":"standard output","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]}}
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
{"id":"req-1","event":"started","op":"queue_speech_live"}
{"id":"req-1","event":"progress","stage":"buffering_audio"}
{"id":"req-1","event":"progress","stage":"preroll_ready"}
{"id":"req-1","event":"progress","stage":"playback_finished"}
{"id":"req-1","ok":true}
{"id":"req-1f","ok":true,"generated_file":{"artifact_id":"req-1f-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"},"generation_job":{"job_id":"req-1f","job_kind":"file","state":"completed","items":[{"artifact_id":"req-1f-artifact-1","text":"Save this one for later playback.","text_profile_name":null,"text_context":null,"source_format":null}]}}
```

Raw JSONL callers should send absolute filesystem paths for path fields, or include `cwd` when using relative paths. SpeakSwiftly resolves those paths against caller-provided context, not the worker launch directory.

## Runtime Behavior Notes

Current live-playback behavior:

- `queue_speech_live` loads the stored profile first, then routes resident generation through the active backend. `qwen3` uses stored profile reference audio and transcript, while `marvis` uses stored profile vibe to select the already-warm built-in preset voice.
- Live playback stays a single-speaker path on one worker. When one audible live request is already playing, later live requests can still be accepted and queued immediately, but their generation waits until the active live playback drains before the next live request starts.
- `queue_speech_file` follows that same backend-routing path, then saves the completed WAV under the generated-file store instead of scheduling playback.
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

Opt-in real-model e2e coverage:

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests
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

Long forensic playback probe:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithLongCodeHeavyRequest
```

Section-aware weird-text forensic probes:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithSegmentedWeirdTextRequest
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithReversedSegmentedWeirdTextRequest
```

Section-aware conversational prose probes:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithSegmentedConversationalProseRequest
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithReversedSegmentedConversationalProseRequest
```

If a real worker run fails with `default.metallib` or `mlx-swift_Cmlx.bundle` errors, the runtime was almost certainly launched from a plain SwiftPM build instead of a published Xcode-backed runtime directory. Re-publish the runtime and launch through the published `run-speakswiftly` script or stable alias.
