# CONTRIBUTING

Contributor-facing project notes for SpeakSwiftly. This document holds the deeper architecture, repository workflow, operator guidance, and verification detail that would make the public [README.md](README.md) too dense.

## Purpose

SpeakSwiftly is intentionally two things at once:

- a typed Swift runtime library through `SpeakSwiftly`
- a long-lived JSONL worker executable through `SpeakSwiftlyTool`

The repository tries to keep those two public surfaces aligned without forcing either one to become a compatibility wrapper over the other. Swift callers should get direct, readable APIs. Process-boundary callers should get stable JSONL operation names and predictable event semantics.

Keep the doc split clean:

- [README.md](README.md) should stay focused on setup, usage, public API names, and baseline verification
- this document should hold architecture notes, repository workflow, operator behavior, full wire examples, and extended verification paths
- the package-facing worker protocol article lives in [Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md](Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md), while this file keeps the deeper maintainer context behind it

## Formatting

SpeakSwiftly uses the checked-in [.swiftformat](.swiftformat) file as the repository source of truth for Swift formatting and the checked-in [.swiftlint.yml](.swiftlint.yml) file for a small set of non-formatting policy checks.

Use these commands from the package root:

```bash
sh scripts/repo-maintenance/install-hooks.sh
sh scripts/repo-maintenance/validate-all.sh
swiftformat --lint --config .swiftformat .
swiftformat --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

Use `install-hooks.sh` once per local clone to enable the repository-managed Git hooks through `core.hooksPath`. Use `validate-all.sh` when you want the shared repo-maintenance gate that backs the pre-commit hook, the release preflight, and CI. Use the first `swiftformat` command when you want to see formatting drift without rewriting files. Use the second `swiftformat` command when you intentionally want to apply formatting changes. Use the SwiftLint command for the smaller safety and maintainability checks that are intentionally left outside SwiftFormat.

Treat SwiftFormat as the primary style tool in this repository. Keep SwiftLint focused on non-formatting policy checks instead of duplicating formatter behavior.

The repository-managed `pre-commit` hook is now the intended local enforcement path. Run `sh scripts/repo-maintenance/install-hooks.sh` after cloning, and Git will use `scripts/repo-maintenance/hooks/pre-commit` for this clone. That hook applies `swiftformat`, restages tracked changes, and then runs the same validation entry point as release preflight and CI.

## Test Harness Probes

The `SpeakSwiftlyTesting` executable is a package-local smoke and investigation
harness. Keep it small, explicit, and honest about what each command measures.

The volume commands have separate jobs:

- `volume-probe` profiles one retained generated file and writes a versioned
  JSON artifact under `.local/volume-probes/`.
- `compare-volume` compares retained streamed output against direct Qwen decode
  only after it proves the analyzed spans are compatible.
- `compare-volume --matched-duration trim-to-shorter` is the explicit mode for
  trimming both outputs to the shorter sample count before comparing them.

Do not use `compare-volume` output for streamed-vs-direct conclusions unless the
artifact proves matched spans or explicitly records the trim mode. Keep
generated-code capture and replay investigations separate from waveform volume
probing; they answer different questions. The detailed volume measurement
contract lives in
[docs/maintainers/volume-probe-instrument-contract-2026-04-24.md](docs/maintainers/volume-probe-instrument-contract-2026-04-24.md).

## Runtime Shape

The current intended runtime shape is:

- a long-lived executable owned by another process
- newline-delimited JSON over `stdin` and `stdout`
- resident backend selection between `qwen3`, `chatterbox_turbo`, and `marvis`
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
- resident runtime controls use `status()`, `switchSpeechBackend(to:)`, `reloadModels()`, and `unloadModels()`
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
- `get_active_text_profile_style`
- `list_text_profile_styles`
- `list_text_profiles`
- `get_text_profile`
- `set_active_text_profile_style`
- `set_active_text_profile`
- `factory_reset_text_profiles`
- `create_text_replacement`
- `replace_text_replacement`
- `update_voice_profile_name`
- `reroll_voice_profile`
- `update_text_profile_name`
- `delete_voice_profile`

The wire shape is intentionally more literal and transport-oriented than the Swift surface, and it should stay mechanically consistent enough that a caller can often guess an operation name correctly before looking it up.

## Runtime Configuration

`SpeakSwiftly.Configuration` is the typed runtime-startup surface. It now carries the preferred resident `speechBackend`, the Qwen conditioning strategy, and an optional startup `textNormalizer`.

The current prepared-conditioning integration depends on `mlx-audio-swift` `69.2.1`, the latest tagged release on the `gaelic-ghost/mlx-audio-swift` fork's `main` branch. Keep this dependency version-based so downstream Xcode package consumers do not inherit a branch dependency.

Default persisted configuration path:

- macOS production default: `~/Library/Application Support/SpeakSwiftly/configuration.json`
- macOS debug and package-test default: `~/Library/Application Support/SpeakSwiftly-Debug/configuration.json`
- with `SPEAKSWIFTLY_PROFILE_ROOT=/custom`: `/custom/configuration.json`

The same namespace split applies to the default profile store and `text-profiles.json`, so debug builds, local package tests, and production runs do not reuse the same local storage root unless you explicitly point them at one with `SPEAKSWIFTLY_PROFILE_ROOT`.
For compatibility, SpeakSwiftly still recognizes the older trailing `.../profiles` form when it detects an existing legacy layout with adjacent `configuration.json` or `text-profiles.json` state.

Backend resolution precedence is:

1. explicit `configuration.speechBackend` passed to `SpeakSwiftly.liftoff(...)`
2. persisted `configuration.json`
3. `SPEAKSWIFTLY_SPEECH_BACKEND`
4. fallback `.qwen3`

Legacy serialized or environment `qwen3_custom_voice` backend values are still accepted and normalized onto `.qwen3` so existing runtime config and stored profile manifests keep loading cleanly after the backend collapse.

`chatterbox_turbo` is the current resident Chatterbox backend surface. It points at the 8-bit Chatterbox Turbo model, stays English-only for now, uses stored profile reference audio directly instead of creating a separate backend-native persisted conditioning artifact, and relies on runtime-owned text chunking for live playback because upstream Chatterbox synthesis is still one waveform per chunk rather than truly incremental.

The current Chatterbox end-to-end workflow coverage lives in `ChatterboxE2ETests`, with sequential design-profile, provided-transcript clone, and inferred-transcript clone checks. By default those live checks stay silent so the release lane remains safe to run on Gale's machine, and the same suite automatically switches to audible playback when `SPEAKSWIFTLY_AUDIBLE_E2E=1` is set.

Qwen conditioning strategy values are:

- `.legacyRaw`: keep passing raw `refAudio` and `refText` into the resident Qwen model on every request
- `.preparedConditioning`: prepare Qwen reference conditioning once, persist it on the profile, cache it in memory after load, and reuse it on later requests

The default runtime configuration now uses `.preparedConditioning`.

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

For generation requests, the worker now documents `voice_profile`, `text_profile`, `input_text_context`, and `request_context` as the current wire keys. Older generation-request aliases such as `profile_name` and `text_profile_id` are still accepted for compatibility, but new callers should prefer the newer names.

Representative request shapes:

```json
{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}
{"id":"req-1b","op":"generate_speech","text":"Explain the latest runtime status.","voice_profile":"default-femme","request_context":{"source":"status_panel","app":"SpeakSwiftlyOperator","project":"SpeakSwiftly","topic":"runtime"}}
{"id":"req-1c","op":"generate_speech","text":"stderr: broken pipe","voice_profile":"default-femme","text_profile":"logs","input_text_context":{"context":{"cwd":"./","repo_root":"./","text_format":"cli_output"}}}
{"id":"req-1d","op":"generate_speech","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","voice_profile":"default-femme","input_text_context":{"context":{"text_format":"markdown","nested_source_format":"swift_source"}}}
{"id":"req-1e","op":"generate_speech","text":"struct WorkerRuntime { let sampleRate: Int }","voice_profile":"default-femme","input_text_context":{"source_format":"swift_source"}}
{"id":"req-1e-qwen-chunked","op":"generate_speech","text":"First paragraph.\n\nSecond paragraph.","voice_profile":"default-femme","qwen_pre_model_text_chunking":true}
{"id":"req-1f","op":"generate_audio_file","text":"Save this one for later playback.","voice_profile":"default-femme"}
{"id":"req-1g","op":"generate_batch","voice_profile":"default-femme","items":[{"text":"First saved file."},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile":"logs","request_context":{"source":"batch_export","topic":"follow-up"}}]}
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
{"id":"req-6","op":"get_active_text_profile_style"}
{"id":"req-6a","op":"list_text_profile_styles"}
{"id":"req-7","op":"set_active_text_profile_style","text_profile_style":"compact"}
{"id":"req-8","op":"list_text_profiles"}
{"id":"req-8a","op":"get_text_profile","text_profile_id":"logs"}
{"id":"req-8b","op":"get_effective_text_profile"}
{"id":"req-8c","op":"get_text_profile_persistence"}
{"id":"req-9","op":"create_text_profile","profile_name":"Logs"}
{"id":"req-10","op":"create_text_replacement","text_profile_id":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}
{"id":"req-10a","op":"replace_text_replacement","text_profile_id":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}
{"id":"req-10b","op":"delete_text_replacement","text_profile_id":"logs","replacement_id":"logs-rule"}
{"id":"req-11","op":"set_active_text_profile","text_profile_id":"ops"}
{"id":"req-11a","op":"update_text_profile_name","text_profile_id":"ops","new_profile_name":"Operations"}
{"id":"req-11b","op":"reset_text_profile","text_profile_id":"ops"}
{"id":"req-11c","op":"delete_text_profile","text_profile_id":"ops"}
{"id":"req-11d","op":"factory_reset_text_profiles"}
{"id":"req-status","op":"get_status"}
{"id":"req-switch","op":"set_speech_backend","speech_backend":"chatterbox_turbo"}
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
{"id":"req-1f","ok":true,"generated_file":{"artifact_id":"req-1f-artifact-1","voice_profile":"default-femme","text_profile":null,"input_text_context":null,"request_context":{"source":"status_panel","app":"SpeakSwiftlyOperator","project":"SpeakSwiftly","topic":"runtime","attributes":{}},"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"},"generation_job":{"job_id":"req-1f","job_kind":"file","voice_profile":"default-femme","text_profile":null,"state":"completed","items":[{"artifact_id":"req-1f-artifact-1","text":"Save this one for later playback.","text_profile":null,"input_text_context":null,"request_context":null}]}}
```

Raw JSONL callers should send absolute filesystem paths for path fields, or include `cwd` when using relative paths. SpeakSwiftly resolves those paths against caller-provided context, not the worker launch directory.

When JSONL naming changes, update this file and `README.md` in the same pass so the public contract stays aligned across both docs.

## Runtime Behavior Notes

Current live-playback behavior:

- `generate_speech` loads the stored profile first, then routes resident generation through the active backend. `qwen3` uses stored profile reference audio and transcript, and Qwen live playback stays single-pass by default. A request can opt into SpeakSwiftly's pre-model Qwen text chunking with `qwen_pre_model_text_chunking: true`, which bounds long live requests by paragraph-group chunks before each model call. `chatterbox_turbo` uses stored profile reference audio with the resident model's built-in default conditioning as the no-clone fallback and now segments normalized text into speakable chunks for sequential live synthesis, and `marvis` uses stored profile vibe to select the already-warm built-in preset voice.
- The built-in text style is a separate persisted runtime setting from the active custom text profile. JSONL callers can inspect it with `get_active_text_profile_style`, inspect the available choices with `list_text_profile_styles`, and update it with `set_active_text_profile_style`.
- Live playback stays a single-speaker path on one worker. When one audible live request is already playing, later live requests can still be accepted and queued immediately, but their generation waits until the active live playback drains before the next live request starts.
- `generate_audio_file` follows that same backend-routing path, then saves the completed WAV under the generated-file store instead of scheduling playback. The Qwen pre-model text chunking flag applies only to live playback; generated audio files stay on the single-pass Qwen rendering path.
- Marvis defaults to `dual_resident_serialized`, which keeps both `conversational_a` and `conversational_b` resident while still allowing only one active Marvis generation at a time. Configuration can also switch to `single_resident_dynamic` if one reusable resident model is preferred over two always-warm voices.
- Profile `vibe` currently drives Marvis routing like this: `.femme` -> `conversational_a`, `.masc` -> `conversational_b`.
- Resident Qwen3 generation now uses the model's own language auto-detection and streams chunks at the `0.32` cadence. For live playback, Qwen request text is handed to the model in one pass unless the caller opts into pre-model text chunking for that request. Marvis now requests the upstream-aligned `0.5` streaming cadence, Chatterbox live synthesis also uses `0.5`, and the ordinary non-Qwen resident baseline stays `0.5`.
- Playback uses adaptive duration-based startup and low-water thresholds rather than a fixed one-chunk gate.

Current generated-file behavior:

- file jobs use the request id as the durable job id, not the artifact id
- single-file generation resolves its saved artifact id as `<jobID>-artifact-1`
- batch generation resolves one saved artifact id per item, using caller-provided `artifact_id` when present and `<batchID>-artifact-N` otherwise
- saved artifacts live in the runtime-managed generated-file store, not at a caller-provided output path
- expired batch reads stay inspectable through `get_generated_batch` and `list_generated_batches`, but return an empty `artifacts` list because the saved files are intentionally gone
- expired file and batch jobs keep artifact references inside `get_generation_job` and `list_generation_jobs` so operators can still see what existed before cleanup

## Playback Architecture

Playback is not only the audio-output layer. In the current runtime shape, playback is also one of the scheduler inputs that decides when later live generation work may proceed. That means maintainers should read the playback path as:

1. public request entry
2. runtime request acceptance and queueing
3. live generation handoff
4. playback execution
5. terminal request completion after playback drains

The public semantic entry point for audible playback is the Swift call `runtime.generate.speech(...)` or the wire op `generate_speech`. `runtime.player` is the control and inspection surface, not the request-creation surface.

The main code anchors are:

- [`Sources/SpeakSwiftly/API/Generation.swift`](Sources/SpeakSwiftly/API/Generation.swift)
- [`Sources/SpeakSwiftly/API/Playback.swift`](Sources/SpeakSwiftly/API/Playback.swift)
- [`Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift`](Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift)
- [`Sources/SpeakSwiftly/Runtime/WorkerRuntimeProcessing.swift`](Sources/SpeakSwiftly/Runtime/WorkerRuntimeProcessing.swift)
- [`Sources/SpeakSwiftly/Playback/PlaybackController.swift`](Sources/SpeakSwiftly/Playback/PlaybackController.swift)
- [`Sources/SpeakSwiftly/Playback/AudioPlaybackDriver.swift`](Sources/SpeakSwiftly/Playback/AudioPlaybackDriver.swift)

### Entry points

The main entry points into the playback layer are:

- typed Swift submission through `Generate.speech(...)`
- JSONL submission through `generate_speech`
- playback control reads and writes through `runtime.player` and the wire control ops such as `playback_pause`, `playback_resume`, `get_playback_state`, `list_playback_queue`, `clear_queue`, and `cancel_request`

The runtime accepts a live speech request as a generation request first. It then creates the playback-side job state that will receive streamed audio and complete only after playback finishes.

### Execution path

The current live path is:

1. `Generate.speech(...)` or `generate_speech` becomes `WorkerRequest.queueSpeech(..., jobType: .live)`.
2. `WorkerRuntime.accept(line:)` validates and accepts the request.
3. The runtime creates live playback job state and registers it with `PlaybackController`.
4. `handleQueueSpeechLiveGeneration(...)` runs resident generation and pushes streamed audio chunks into the playback-side continuation.
5. `PlaybackController` waits for enough playback-ready state, then hands audio to the type-erased playback driver.
6. `AudioPlaybackDriver` owns AVFoundation scheduling, buffering, route and engine recovery, and final playback drain.
7. Terminal request success is emitted only after local playback drain finishes, not when generation finishes producing samples.

That split is intentional. Generated audio completion and local playback completion are not the same event.

### Exit points

Playback currently exits through four surfaces:

- audible audio through `AVAudioEngine` and `AVAudioPlayerNode`
- typed request events and snapshots for Swift callers
- JSONL success, failure, and progress events on `stdout`
- operator-facing diagnostics and playback trace output on `stderr`

The key design point is that playback completion is a runtime event as well as an audio event. The worker does not treat "last chunk generated" as "request complete."

### Apple behavior we rely on

The playback implementation depends on documented Apple audio behavior and should stay aligned with it.

Primary references:

- [`AVAudioPlayerNode`](https://developer.apple.com/documentation/avfaudio/avaudioplayernode)
- [`.dataPlayedBack`](https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype/dataplayedback)
- [`AVAudioPlayerNode.stop()`](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/stop())

Important documented constraints:

- `.dataPlayedBack` is the completion callback type that reflects actual downstream playback completion rather than only buffer consumption by the player node.
- `AVAudioPlayerNode.stop()` clears scheduled buffers and resets the player timeline.
- Apple warns against stopping the player from a completion callback because that can deadlock.

Those constraints are why the runtime keeps explicit drain and shutdown logic outside the raw callback body and why playback completion is tracked as a separate runtime concern.

### Current strengths

The playback architecture is strongest at the edges:

- the public surface is clear: generation submits playback work, `Player` controls and inspects it
- dependency injection is real: the runtime can swap playback implementations through `WorkerDependencies`
- platform audio details are mostly boxed into `AudioPlaybackDriver`
- tests can exercise runtime playback behavior without needing real hardware in every case

This is the separation of concerns to preserve:

- `API/` owns public typed surfaces
- `Runtime/` owns request acceptance, queueing, lifecycle, and terminal semantics
- `PlaybackController` owns playback job coordination and playback-facing state
- `AudioPlaybackDriver` owns AVFoundation, engine state, route changes, and drain mechanics

### Recently landed cleanup

The first playback-architecture cleanup pass landed on `2026-04-15` in three steps:

- live playback now keeps one runtime-owned `LiveSpeechRequestState` from request acceptance through terminal playback completion instead of reconstructing request identity late
- playback execution mechanics now live in `PlaybackExecutionState` and `LiveSpeechPlaybackState`, which keeps streamed audio, continuations, sample rate, and task ownership playback-local
- generation scheduling now depends on a narrow playback admission signal for concurrent-generation gating, while richer playback telemetry remains part of runtime overview and diagnostics for operators

That means the current model is flatter than the earlier `PlaybackJob` design:

- runtime owns request identity, normalization context, and deep-trace metadata
- playback owns execution state and hardware-facing playback coordination
- scheduling consumes an explicit admission decision instead of reaching directly into the full playback telemetry surface for lane gating

### Current pressure points

The weakest part of the current architecture is the middle, where one live request spans generation, playback, scheduling, and terminal completion at the same time.

The main maintainership pain points today are:

- live requests are represented in both generation and playback bookkeeping
- runtime bridge code is still spread across both `Runtime/` and `Playback/`, which makes ownership harder to scan than it should be
- live requests still span both generation and playback bookkeeping, even though the coordination path is now much easier to follow than before milestones 23 through 25 landed
- the public playback state is intentionally thin, while runtime overview still exposes richer buffering telemetry, so maintainers need to stay clear about which surface is operator telemetry and which surface is scheduling policy
- backend-specific playback tuning work, especially around first-request Marvis behavior, still needs to stay visibly policy-driven instead of slowly becoming hidden controller coupling again

None of that means the design is bad. It means the existing public shape has held up well enough that the next cleanup should focus on flattening the internal coordination path instead of adding more layers.

### Refactor map

The first staged playback refactor sequence has now landed:

1. Flatten live request coordination.
   Landed. One runtime-owned `LiveSpeechRequestState` now survives from request acceptance through playback completion.

2. Split playback execution ownership.
   Landed. Playback-local execution state now lives in `PlaybackExecutionState` and `LiveSpeechPlaybackState` instead of staying mixed into the runtime-owned request record.

3. Narrow the playback-to-scheduler boundary.
   Landed. Generation scheduling now consumes a smaller playback admission signal, while richer playback telemetry stays available for operator-facing diagnostics and runtime overview.

4. Rehome runtime bridge code.
   Still open. Playback implementation files are cleaner than before, but some runtime-owned bridge logic still lives under `Playback/` and should move only if doing so makes ownership easier to scan rather than just reshuffling files.

5. Keep the public playback state intentionally thin unless a real user-facing need appears.
   Reviewed. The current outcome is to keep `PlaybackState` thin and keep richer buffering and rebuffer telemetry in runtime overview instead of widening the enum prematurely.

The active roadmap milestones for this work are:

- `Milestone 22`: Marvis MLX generation-path investigation and playback tuning

The current Milestone 22 operating decisions are:

1. Smoother audible Marvis playback is more important than squeezing first audio to the earliest possible moment.
2. Marvis generation is now intentionally serialized in `SpeakSwiftly`.
3. All live Marvis playback now uses one conservative startup profile tuned to current MLX throughput.
4. The next Marvis work should bias toward upstream investigation, throughput diagnosis, and simpler policy verification instead of rebuilding local queue choreography.

The important current Milestone 22 readout is:

- the old overlap-heavy Marvis policy is gone
- the default resident policy is now `dual_resident_serialized`, with `single_resident_dynamic` available as the simpler alternate resident strategy
- the repo now has a dedicated Marvis resident-policy benchmark for the same `femme -> masc -> femme` three-request switch pattern
- the current cadence now matches the upstream `0.5` Marvis streaming path
- audible Marvis still rebuffers even under serialized generation
- the remaining issue now looks more like raw Marvis-on-MLX throughput than local overlap policy
- the next meaningful investigation is comparing the `mlx-audio-swift` Marvis generation path against Marvis's own reference implementation surface instead of adding more local queue complexity

## Repository Layout

The package source tree is organized by responsibility:

- `Sources/SpeakSwiftly/API` contains the public package-facing library surface
- `Sources/SpeakSwiftly/Generation` contains generation and voice-profile logic
- `Sources/SpeakSwiftly/Normalization` contains `SpeakSwiftly.Normalizer` and text-normalization logic
- `Sources/SpeakSwiftly/Playback` contains the playback subsystem
- `Sources/SpeakSwiftly/Runtime` contains worker-runtime internals such as protocol decoding, request orchestration, lifecycle, and emission

Within `Runtime`, prefer focused companion files over a single catch-all runtime implementation. `WorkerRuntime.swift`, `WorkerRuntimeLifecycle.swift`, `WorkerRuntimeScheduling.swift`, `WorkerRuntimeProcessing.swift`, and their `+...` companions should each own one clear responsibility boundary instead of regrowing into another monolith.

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
- `Tests/SpeakSwiftlyTests/E2E/Support/SpeakSwiftlyE2EPolicy.swift`
- `Tests/SpeakSwiftlyTests/E2E/Support/SpeakSwiftlyE2ETags.swift`
- `Tests/SpeakSwiftlyTests/E2E/Support/SpeakSwiftlyE2ETestSupport.swift`

## Repository Workflow

This repository is the source-of-truth development home for SpeakSwiftly.

The intended ownership model is:

- this repository remains the primary development home for [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly)
- the larger [`speak-to-user`](https://github.com/gaelic-ghost/speak-to-user) repository consumes SpeakSwiftly as a Git submodule under `packages/SpeakSwiftly`
- feature work lands here first, and the consuming repository updates its submodule pointer when it is ready to adopt a newer revision

Older adjacent hosts such as [`speak-to-user-mcp`](https://github.com/gaelic-ghost/speak-to-user-mcp) and [`speak-to-user-server`](https://github.com/gaelic-ghost/speak-to-user-server) should launch one deterministic Xcode build root instead of relying on copy hooks or ad hoc raw DerivedData guesses. Linked Swift package consumers should resolve the vendored `mlx-swift_Cmlx.bundle` through the package resource bundle.

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

The current `mlx-audio-swift` `69.2.1` fork release restores the ordinary
SwiftPM lane for this repository, including the worker-backed `QuickE2ETests`
path. Treat plain `swift build` and `swift test` as the default verification
story again.

For MLX-backed package tests, the plain `swift test` lane now works because the
`SpeakSwiftlyTests` target carries a bundled `default.metallib` resource and
the shared test bootstrap stages that file into the exact SwiftPM runtime probe
paths MLX checks under `.build/...` before the first `MLXArray` is created.
Do not escalate to Xcode just because a package test uses MLX.

If a future toolchain regression brings back the old `EnglishG2P.swift` parser
failure, treat that as a fallback-lane trigger instead of a fresh local
mystery. Do not keep retrying the same `swift build` / `swift test` commands.
Switch to the Xcode-backed package workspace lane documented below and in
[`docs/maintainers/validation-lanes.md`](docs/maintainers/validation-lanes.md).

Build and verify a real Xcode-backed standalone worker runtime:

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

Opt-in real-model e2e coverage. The e2e surface is split into top-level domain suites such as `QwenE2ETests`, `MarvisE2ETests`, and `DeepTraceE2ETests`, and each suite carries its own Swift Testing traits directly at the suite declaration.

Use the repo-maintenance wrappers first so the runner shape stays consistent and the machine never launches multiple top-level worker-backed suites at once:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite quick
sh scripts/repo-maintenance/run-e2e-full.sh
```

`run-e2e.sh` intentionally runs exactly one top-level suite per invocation. `run-e2e-full.sh` runs the default release-safe suite list sequentially: `QuickE2ETests`, `GeneratedFileE2ETests`, `GeneratedBatchE2ETests`, `ChatterboxE2ETests`, `MarvisE2ETests`, and `QwenE2ETests`.

For a deliberately small worker-backed smoke lane after narrow changes, run the dedicated quick suite:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite quick
```

One-shot qwen resident `generate_speech` verification:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen
```

Dedicated long-form qwen live-playback verification with one five-paragraph
request:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen-longform
```

Prepared-conditioning qwen verification. This boots the worker in `prepared_conditioning` mode, confirms the first request persists a stored Qwen conditioning artifact on the profile, then restarts the worker and confirms the second request reloads that stored artifact instead of rebuilding it from raw reference inputs:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen
SPEAKSWIFTLY_E2E=1 swift test --filter QwenE2ETests/preparedConditioningPersistsAndReloadsAcrossWorkerRestart
```

Opt-in MLX-backed persistence unit coverage. These tests are marked with a Swift Testing conditional-execution trait, so the default `swift test` lane skips them unless you explicitly enable `SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1` for the narrow MLX persistence round-trip coverage:

```bash
SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1 swift test --filter preparedQwenConditioning
```

Force audible playback in the e2e suite:

```bash
sh scripts/repo-maintenance/run-e2e-full.sh --audible
```

Retained real-model run artifacts live under `.local/e2e-runs`.

Chunk-level trace during e2e:

```bash
sh scripts/repo-maintenance/run-e2e-full.sh --playback-trace
```

Without `SPEAKSWIFTLY_PLAYBACK_TRACE=1`, the trace-capture suite is skipped during ordinary `SPEAKSWIFTLY_E2E=1` runs so the default full e2e lane stays release-safe.

For the targeted first-request Marvis tuning lane, prefer the plain SwiftPM
wrapper first:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite marvis --playback-trace
```

If a future toolchain regression blocks that ordinary path again, the older
Xcode-backed fallback still works: `xcodebuild build-for-testing`, then an
`.xctestrun` override that injects `SPEAKSWIFTLY_E2E=1` and
`SPEAKSWIFTLY_PLAYBACK_TRACE=1`, then `xcodebuild test-without-building`
against this exact test identifier. On current Xcode manifests, that override
lives under `TestConfigurations -> TestTargets -> EnvironmentVariables`.

```text
SpeakSwiftlyTests/MarvisE2ETests/`queued audible playback stays serialized and routes expected voices`()
```

The same fallback principle applies to release hardening and narrow package
validation when SwiftPM is blocked:

1. Run `xcodebuild build-for-testing` from the repo root with `-scheme SpeakSwiftly-Package`.
2. Reuse the generated `.xctestrun` file for one targeted `xcodebuild test-without-building` run at a time.
3. Prefer targeted reruns over broad shotgun retries so the failure surface stays readable.

GitHub Actions should follow that same fallback lane for package compilation and
tests only when the ordinary SwiftPM lane regresses again. Keep
`swift package dump-package` as the manifest sanity check. The normal CI story
should stay SwiftPM-first unless the parser failure returns.

The current CI split is:

- macOS Xcode-backed package validation:
  - `SpeakSwiftlyTests/WorkerRuntimePlaybackTests`
  - `SpeakSwiftlyTests/LibrarySurfaceTests`
  - `SpeakSwiftlyTests/ModelClientsTests`
- iOS Simulator compile-and-smoke validation:
  - `SpeakSwiftlyTests/LibrarySurfaceTests`
  - `SpeakSwiftlyTests/SupportResourcesTests`
  - `SpeakSwiftlyTests/ProfileStoreTests`

Keep the iOS lane library-first. The worker-driven e2e harness under
`Tests/SpeakSwiftlyTests/E2E/` is macOS-only because it launches the published
CLI worker process and does not model an app-hosted iOS runtime.

Long deep-trace playback probe:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite deep-trace --deep-trace
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 swift test --filter DeepTraceE2ETests/longCodeHeavy
```

Opt-in qwen resident benchmark comparison:

```bash
sh scripts/repo-maintenance/run-benchmark.sh --qwen
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1 swift test --filter QwenBenchmarkE2ETests
```

Without `SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1`, the benchmark suite is skipped during ordinary `SPEAKSWIFTLY_E2E=1` runs so the default full e2e lane stays release-safe.

Run multiple comparison samples per Qwen conditioning strategy:

```bash
sh scripts/repo-maintenance/run-benchmark.sh --qwen --iterations 3
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_ITERATIONS=3 swift test --filter QwenBenchmarkE2ETests
```

Each benchmark run persists a timestamped JSON summary under `.local/benchmarks` and refreshes `.local/benchmarks/qwen-resident-benchmark-latest.json` for quick inspection.

Opt-in backend-wide queued live benchmark comparison:

```bash
sh scripts/repo-maintenance/run-benchmark.sh
sh scripts/repo-maintenance/run-benchmark.sh --audible --iterations 3
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E=1 swift test --filter BackendBenchmarkE2ETests
```

The backend-wide suite runs the same two-request live benchmark scenario across
`qwen3`, `chatterbox_turbo`, and `marvis`. The second request is expected to
queue behind the first one; if it does not, the suite now fails so the queued
benchmark contract cannot silently drift into a non-queued workload.

The same suite also carries a Marvis-specific resident-policy benchmark that
compares `dual_resident_serialized` against `single_resident_dynamic` with a
three-request back-and-forth voice order: `femme`, `masc`, then `femme` again.

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E=1 SPEAKSWIFTLY_BACKEND_BENCHMARK_ITERATIONS=1 swift test --filter 'BackendBenchmarkE2ETests/compare marvis resident policies with three queued voice switches'
```

That benchmark writes its own retained summaries under `.local/benchmarks` and
refreshes one of these latest files:

- `.local/benchmarks/marvis-resident-policy-benchmark-latest.json`
- `.local/benchmarks/marvis-resident-policy-audible-benchmark-latest.json`

Section-aware weird-text deep-trace probes:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite deep-trace --deep-trace --playback-trace
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter DeepTraceE2ETests/segmentedWeirdText
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter DeepTraceE2ETests/reversedSegmentedWeirdText
```

Section-aware conversational prose deep-trace probes:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite deep-trace --deep-trace --playback-trace
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter DeepTraceE2ETests/segmentedConversationalProse
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter DeepTraceE2ETests/reversedSegmentedConversationalProse
```

If a real standalone worker run fails with `default.metallib` or
`mlx-swift_Cmlx.bundle` errors, the runtime was almost certainly launched from
a plain SwiftPM build instead of the deterministic Xcode-backed worker
directory. Rebuild the runtime and launch through
`.local/derived-data/runtime-<configuration>/run-speakswiftly`.

The library target also vendors one copy of `mlx-swift_Cmlx.bundle` under `Sources/SpeakSwiftly/Resources` so linked package consumers resolve the packaged MLX bundle and metallib through `SpeakSwiftly.SupportResources`. Keep the vendored bundle in sync with the pinned MLX dependency by refreshing it from the deterministic Release runtime whenever the MLX stack changes.
