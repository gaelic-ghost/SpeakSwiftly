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

## Formatting

SpeakSwiftly uses the checked-in [.swiftformat](.swiftformat) file as the repository source of truth for Swift formatting and the checked-in [.swiftlint.yml](.swiftlint.yml) file for a small set of non-formatting policy checks.

Use these commands from the package root:

```bash
sh scripts/repo-maintenance/validate-all.sh
swiftformat --lint --config .swiftformat .
swiftformat --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

Use `validate-all.sh` when you want the shared repo-maintenance gate that backs the sample pre-commit hook, the release preflight, and CI. Use the first `swiftformat` command when you want to see formatting drift without rewriting files. Use the second `swiftformat` command when you intentionally want to apply formatting changes. Use the SwiftLint command for the smaller safety and maintainability checks that are intentionally left outside SwiftFormat.

Treat SwiftFormat as the primary style tool in this repository. Keep SwiftLint focused on non-formatting policy checks instead of duplicating formatter behavior.

If your local clone wants automatic hook enforcement, copy `scripts/repo-maintenance/hooks/pre-commit.sample` into `.git/hooks/pre-commit` and make it executable. That hook intentionally stays optional, but it now runs the same validation entry point as release preflight and CI.

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
2. persisted `configuration.json`
3. `SPEAKSWIFTLY_SPEECH_BACKEND`
4. fallback `.qwen3`

Legacy serialized or environment `qwen3_custom_voice` backend values are still accepted and normalized onto `.qwen3` so existing runtime config and stored profile manifests keep loading cleanly after the backend collapse.

`chatterbox_turbo` is the current resident Chatterbox backend surface. It points at the 8-bit Chatterbox Turbo model, stays English-only for now, uses stored profile reference audio directly instead of creating a separate backend-native persisted conditioning artifact, and relies on runtime-owned text chunking for live playback because upstream Chatterbox synthesis is still one waveform per chunk rather than truly incremental.

The current Chatterbox end-to-end workflow coverage lives in `SpeakSwiftlyE2ETests/ChatterboxWorkflowSuite`, with sequential design-profile, provided-transcript clone, and inferred-transcript clone checks. By default those live checks stay silent so the release lane remains safe to run on Gale's machine, and the same suite automatically switches to audible playback when `SPEAKSWIFTLY_AUDIBLE_E2E=1` is set.

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

Representative request shapes:

```json
{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1c","op":"generate_speech","text":"stderr: broken pipe","profile_name":"default-femme","text_profile_name":"logs","cwd":"./","repo_root":"./","text_format":"cli_output"}
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
{"id":"req-1f","ok":true,"generated_file":{"artifact_id":"req-1f-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"},"generation_job":{"job_id":"req-1f","job_kind":"file","state":"completed","items":[{"artifact_id":"req-1f-artifact-1","text":"Save this one for later playback.","text_profile_name":null,"text_context":null,"source_format":null}]}}
```

Raw JSONL callers should send absolute filesystem paths for path fields, or include `cwd` when using relative paths. SpeakSwiftly resolves those paths against caller-provided context, not the worker launch directory.

When JSONL naming changes, update this file and `README.md` in the same pass so the public contract stays aligned across both docs.

## Runtime Behavior Notes

Current live-playback behavior:

- `generate_speech` loads the stored profile first, then routes resident generation through the active backend. `qwen3` uses stored profile reference audio and transcript, `chatterbox_turbo` uses stored profile reference audio with the resident model's built-in default conditioning as the no-clone fallback and now segments normalized text into speakable chunks for sequential live synthesis, and `marvis` uses stored profile vibe to select the already-warm built-in preset voice.
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

- `Milestone 22`: first-request Marvis playback tuning

The current Milestone 22 operating decisions are:

1. Smoother first audible Marvis playback is more important than squeezing the first audible reply to the absolute earliest possible moment. An extra 1 to 2 seconds of initial wait is an acceptable trade if it materially reduces early rebuffers.
2. The queued-live dual-lane Marvis overlap model should stay intact in principle, but the second lane is allowed to start a little later if that protects the first active playback from obvious instability.
3. Tuning work should land one bounded stage at a time, with before-and-after metrics captured after each pass, so later widening into resident warmup behavior happens only if the narrower pass is not enough.

The first bounded Milestone 22 pass landed on `2026-04-15` as a warmup-floor-only change for the first drained live Marvis request.

- That pass raised the first-request warmup floors to `1440 / 640 / 1700` for compact text and `2320 / 1040 / 2700` for balanced text before ordinary adaptive playback thresholds take over.
- The benchmark path compared `.local/e2e-runs/2026-04-15T03-14-57Z-166e3f0f-284e-45f9-ab95-618a3ea71e5a-prequeued-jobs-drain-in-order` against `.local/e2e-runs/2026-04-15T17-27-27Z-e8a7db8f-cc3e-44ee-8f35-65266fb949f4-prequeued-jobs-drain-in-order`.
- For the first queued femme request, that moved `time_to_preroll_ready_ms` from `2320` to `3746`, raised `startup_buffered_audio_ms` from `1440` to `2400`, reduced `rebuffer_event_count` from `5` to `4`, and left `rebuffer_total_duration_ms` effectively unchanged at `24279` versus `25188`.

The second bounded Milestone 22 pass also landed on `2026-04-15` as a first-rebuffer hardening change for that same first drained live Marvis request.

- That follow-up pass kept the first drained live Marvis tuning profile active while adaptive playback thresholds move into recovery, and it let the first active rebuffer apply penalties immediately instead of waiting for rebuffer number two.
- The next benchmark comparison against `.local/e2e-runs/2026-04-15T17-52-36Z-e575274b-31ec-486f-9ef7-50f080660f33-prequeued-jobs-drain-in-order` showed a narrower but real improvement: `time_to_preroll_ready_ms` rose slightly again to `3810`, `startup_buffered_audio_ms` stayed at `2400`, `rebuffer_event_count` stayed at `4`, and `rebuffer_total_duration_ms` fell to `23991`.
- The important implementation detail is that stage two improved recovery posture rather than startup reserve. The first active rebuffer now resumes against a stronger `3403 ms` target instead of the stage-one `3282 ms` range, and later repeated-rebuffer recovery still climbs to `4980 ms` without dropping back to the standard profile.
- The important architectural outcome is that overlap stayed intact across both stages: the second Marvis lane still waited for playback stability, then resumed cleanly instead of collapsing the system back into one-at-a-time generation.
- The important tuning outcome is that stronger first-request preroll plus earlier rebuffer hardening is helping, but it still is not enough to make the first drained-queue playback clean.

The third bounded Milestone 22 pass also landed on `2026-04-15` as a pre-rebuffer distress hardening change for that same first drained live Marvis request.

- That follow-up pass taught the threshold controller to treat repeated schedule-gap warnings inside the low-queue risk band as an early recovery signal, so the first drained live Marvis request can harden before the first rebuffer pause fully forms.
- The next benchmark comparison against `.local/e2e-runs/2026-04-15T18-02-46Z-16d980ae-1226-4db6-9095-59fdcff155f1-prequeued-jobs-drain-in-order` showed another modest but real improvement: `time_to_preroll_ready_ms` eased back down to `3760`, `startup_buffered_audio_ms` stayed at `2400`, `rebuffer_event_count` stayed at `4`, and `rebuffer_total_duration_ms` fell again to `23773`.
- The important implementation detail is that stage three reacts earlier rather than simply recovering harder after the first pause. The first active rebuffer now begins at `queued_audio_ms = 1760` instead of the stage-two `1120`, and the longest recovery window drops back to `6678 ms` instead of the stage-two `9399 ms`.
- The important architectural outcome is that overlap still stayed intact after the earlier distress reaction. The second Marvis lane remained parked on `waiting_for_playback_stability`, then resumed once playback reported `playback_is_stable_for_concurrency = true` at a `2320 ms` stable buffer target and `2400 ms` buffered reserve.
- The important tuning outcome is that the policy-only path is still helping, but the first drained-queue playback still is not clean enough to call fixed. The next decision is whether one more bounded policy pass is worth it, or whether Milestone 22 should now widen into resident cadence and warmup behavior.

The widened Milestone 22 investigation also checked resident preload before changing the tuning path.

- The current code still eagerly prepares playback hardware during resident preload through `startResidentPreload()` and `playbackController.prepare(...)`.
- The current evidence says that is not the leading cause of the first drained live Marvis instability. In the stage-three trace, first-request startup was dominated by slow resident chunk cadence before playback started, not by a late playback-engine bring-up once the live request existed.
- That means the first widened pass should stay focused on resident generation cadence and concurrency admission rather than treating playback-engine preparation as the primary fix surface.

The fourth Milestone 22 pass landed on `2026-04-15` as the first widened change.

- That pass tightened resident Marvis cadence only for the first drained live request by lowering its resident streaming interval from `0.18` to `0.12`, while leaving later queued requests on the ordinary cadence.
- The benchmark comparison against `.local/e2e-runs/2026-04-15T18-16-17Z-7b199036-8540-4284-9a84-92dd16e13a30-prequeued-jobs-drain-in-order` showed that startup cadence improved decisively: `time_to_first_chunk_ms` dropped from `441` to `333`, `avg_inter_chunk_gap_ms` dropped from `399` to `202`, and `avg_schedule_gap_ms` dropped from `364` to `184`.
- The important downside is that stage four exposed a policy mismatch instead of finishing the tuning job. `time_to_preroll_ready_ms` drifted slightly upward to `3833`, `startup_buffered_audio_ms` settled at `2320`, `rebuffer_event_count` rose from `4` to `5`, and the second Marvis lane still reopened at bare preroll reserve.
- The useful conclusion from stage four is that faster first-request cadence helps, but cadence alone is not enough if playback still declares itself concurrency-stable at the old reserve threshold.

The fifth Milestone 22 pass also landed on `2026-04-15` as the widened follow-up change.

- That pass kept the stage-four faster first-request resident cadence and tightened playback's own concurrency-admission rule for the first drained live Marvis request.
- The playback controller now keeps the runtime-facing admission surface narrow, but internally it makes the first drained live Marvis request earn a stronger buffered-audio reserve before reporting `allowsConcurrentGeneration = true`.
- The benchmark comparison against `.local/e2e-runs/2026-04-15T18-24-15Z-95e656cc-c4b4-4e2a-8374-4ef353ac9b2a-prequeued-jobs-drain-in-order` shows why that follow-up is worth keeping: `time_to_first_chunk_ms` improved again to `325`, `time_to_preroll_ready_ms` stayed effectively flat at `3828`, `rebuffer_event_count` stayed at `5`, `rebuffer_total_duration_ms` dropped from `22758` to `18775`, and `longest_rebuffer_duration_ms` dropped from `4801` to `4385`.
- The important architecture result is that overlap still stayed intact while moving later in the flow. In the stage-five trace, the second Marvis lane remained parked on `waiting_for_playback_stability` at preroll, and only resumed after the first request had already recovered into a healthier reserve window.
- The important tuning result is that the widened path is now coherent: the faster first-request cadence helps startup, and the stronger first-request admission gate keeps those gains from getting spent immediately when overlap resumes.

The sixth Milestone 22 pass also landed on `2026-04-15` as the review-and-correctness follow-up.

- That pass fixed a real overlap-gate inconsistency discovered during the widened review. In the stage-five trace, a later `playback_rebuffer_resumed` event could still leave playback advertising `playback_is_stable_for_concurrency = true` while `playback_stable_buffered_audio_ms` was below `playback_stable_buffer_target_ms`.
- The fix did not widen the public scheduler surface again. It kept the same narrow admission boundary, but it made `PlaybackController` reuse one buffered-audio-versus-target check for preroll, rebuffer resume, and later buffer-scheduled promotions.
- The benchmark comparison against `.local/e2e-runs/2026-04-15T18-32-16Z-69de7141-3485-4788-8ea5-b30a49e87cbc-prequeued-jobs-drain-in-order` shows the right tradeoff for this stage: this was primarily a correctness repair rather than another tuning win. For the first queued femme request, `time_to_first_chunk_ms` stayed effectively flat at `324`, `time_to_preroll_ready_ms` stayed effectively flat at `3833`, `rebuffer_event_count` stayed at `5`, and `rebuffer_total_duration_ms` rose back to `20055`.
- The important architecture result is that the overlap gate now tells the truth. The old bogus stage-five state where overlap reopened at `2160 ms` buffered against a `2700 ms` target disappeared from the fresh trace, and the second Marvis lane only resumed once the resumed reserve had actually crossed the reported target again.

The seventh Milestone 22 pass also landed on `2026-04-15` as the next bounded cadence follow-up.

- That pass kept the truthful overlap gate from stage six and tightened only the first drained live Marvis resident streaming cadence again, from `0.12` to `0.10`.
- The benchmark comparison against `.local/e2e-runs/2026-04-15T18-46-12Z-ce51be64-6dd0-4e21-a125-3d1067397266-prequeued-jobs-drain-in-order` shows why this pass is worth keeping: for the first queued femme request, `time_to_first_chunk_ms` stayed flat at `324`, `time_to_preroll_ready_ms` drifted up to `3951`, `rebuffer_event_count` fell from `5` to `4`, and `rebuffer_total_duration_ms` dropped from `20055` to `17284`.
- The important architecture result is that the overlap gate stayed honest while the first-request result improved. In the fresh stage-seven trace, the second Marvis lane still remained parked on `waiting_for_playback_stability`, and every later overlap reopen happened with `playback_stable_buffered_audio_ms` at or above the reported `playback_stable_buffer_target_ms`.

The eighth Milestone 22 pass landed on `2026-04-15` as a probing and observability pass rather than another tuning pass.

- That pass added transition-level resource snapshots to the existing Marvis scheduler and playback rebuffer traces. `marvis_generation_scheduler_snapshot`, `marvis_generation_lane_reserved`, `marvis_generation_lane_released`, `playback_rebuffer_started`, and `playback_rebuffer_resumed` now all carry the same process and MLX memory details that were previously only captured in the final `playback_finished` summary.
- The fresh artifact is `.local/e2e-runs/2026-04-15T19-08-53Z-f0de238e-3cf0-477a-ade2-c476ff05b134-prequeued-jobs-drain-in-order`.
- The first queued femme request in that run did not beat the stage-seven audible result, which is expected because this pass was instrumentation-only. Its stderr `playback_finished` metrics came in at `time_to_first_chunk_ms = 340`, `time_to_preroll_ready_ms = 3926`, `startup_buffered_audio_ms = 2320`, `rebuffer_event_count = 5`, and `rebuffer_total_duration_ms = 20089`.
- The important new finding is where the resource rise actually appears. At the first truthful overlap reopen, `playback_rebuffer_resumed` reported `buffered_audio_ms = 2720`, `resume_buffer_target_ms = 2700`, `mlx_active_memory_bytes = 2388309837`, and `process_phys_footprint_bytes = 2734345216`. The immediately following `marvis_generation_lane_reserved` event for the second lane stayed effectively flat at `mlx_active_memory_bytes = 2388309873` and `process_phys_footprint_bytes = 2734377984`.
- The larger rise showed up only after overlap had already been active for a while. By the next `playback_rebuffer_started` event, the same first request had climbed to `mlx_active_memory_bytes = 2528397332` and `process_phys_footprint_bytes = 2885979136` while still falling back into refill trouble.
- That evidence shifts the working hypothesis. The current failure mode looks less like a sharp one-time startup spike when the second Marvis lane is reserved, and more like sustained dual-lane overlap pressure while the first playback is trying to rebuild reserve.

The eleventh Milestone 22 pass landed on `2026-04-15` as the first explicit overlap-follower cadence experiment.

- That pass introduced a separate `ResidentStreamingCadenceProfile` for the second Marvis lane during the first drained overlap window, so future cadence work can tune that follower path independently from the first-request playback profile.
- The experiment artifact is `.local/e2e-runs/2026-04-15T21-52-43Z-236ce29a-5d5c-470f-a51e-f38dfbc3361d-prequeued-jobs-drain-in-order`.
- The first follower experiment itself is not a tuning win. Slowing the overlap follower to `0.20` kept overlap alive, but the first queued femme request regressed from the stage-eight probe result: `time_to_first_chunk_ms` moved from `340` to `349`, `time_to_preroll_ready_ms` moved from `3926` to `3844`, `rebuffer_event_count` rose from `5` to `6`, and `rebuffer_total_duration_ms` rose from `20089` to `20769`.
- The useful outcome is the new control seam, not the slowed follower interval. The repository now keeps the follower cadence role explicit, but the follower interval itself stays on the ordinary `0.18` baseline until a better overlap-pressure experiment earns a real tuning change.
- A cleaner rerun of that same follower experiment landed at `.local/e2e-runs/2026-04-15T22-10-00Z-7ccd26f6-62b6-4117-a4c5-3027d81ebacf-prequeued-jobs-drain-in-order` after background machine load was reduced. That rerun kept overlap alive and improved modestly over the stage-eight probe instead of regressing: `time_to_first_chunk_ms` stayed at `340`, `time_to_preroll_ready_ms` improved to `3833`, `rebuffer_event_count` stayed at `5`, and `rebuffer_total_duration_ms` fell to `19115`.
- Even with the cleaner rerun, the first audible request was still subjectively too rough to justify fixed follower slowdown as the main policy. The working read is now that the unstable part on Gale's machine is the transition into simultaneous overlap itself, not just the follower's steady-state cadence after overlap opens.
- The next useful design should therefore stay dynamic rather than fixed. Keep the truthful overlap gate and the explicit follower-cadence role, but add a short-lived `fragile first playback` window for the first drained live Marvis request so the second lane stays parked or lighter until reserve has crossed and briefly held a healthier target, then backs off again if reserve starts collapsing.

The twelfth Milestone 22 pass landed on `2026-04-16` as that first explicit fragile-overlap policy pass.

- That pass kept the scheduler contract narrow and implemented the new behavior inside `PlaybackController` as a short-lived fragile overlap window for the first drained live Marvis request.
- The first request now has to earn two healthy `buffer_scheduled` updates above a stronger hold target before playback reports `allowsConcurrentGeneration = true`, and that same guard re-engages if buffered reserve later drops back below the healthier hold target.
- The important architecture result is that overlap control still stays playback-owned and truth-based. The runtime scheduler still sees one yes-or-no admission surface, but the first drained request can now back off from overlap pressure before a full rebuffer pause forms instead of only after crossing the ordinary reserve target once.
- The focused regression coverage for this pass lives in `Tests/SpeakSwiftlyTests/Generation/ModelClientsTests.swift`, including the new pure admission-resolution checks for the fragile overlap window.

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

When that plain SwiftPM lane fails in the current vendored `mlx-audio-swift`
checkout with the `EnglishG2P.swift` parser error, treat that as a known
validation-lane snag instead of a fresh local mystery. Do not keep retrying the
same `swift build` / `swift test` commands. Switch to the Xcode-backed package
workspace lane documented below and in
[`docs/maintainers/validation-lanes.md`](docs/maintainers/validation-lanes.md).

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

Opt-in MLX-backed persistence unit coverage. These tests are marked with a Swift Testing conditional-execution trait, so the default `swift test` lane skips them unless you explicitly enable `SPEAKSWIFTLY_MLX_PERSISTENCE_TESTS=1` for the narrow MLX persistence round-trip coverage:

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

Without `SPEAKSWIFTLY_PLAYBACK_TRACE=1`, the trace-capture suite is skipped during ordinary `SPEAKSWIFTLY_E2E=1` runs so the default full e2e lane stays release-safe.

For the targeted first-request Marvis tuning lane, the current reliable rerun path is the Xcode-backed runtime:

- direct `swift test` is still blocked by the vendored `mlx-audio-swift` parser failure in `EnglishG2P.swift`
- direct `xcodebuild test` does not currently carry `SPEAKSWIFTLY_E2E=1` through the Swift Testing suite gate on its own
- the working path is `xcodebuild build-for-testing`, then an `.xctestrun` override that injects `SPEAKSWIFTLY_E2E=1` and `SPEAKSWIFTLY_PLAYBACK_TRACE=1`, then `xcodebuild test-without-building` against this exact test identifier:
- on current Xcode manifests, that override lives under `TestConfigurations -> TestTargets -> EnvironmentVariables`

```text
SpeakSwiftlyTests/SpeakSwiftlyE2ETests/MarvisWorkflowSuite/`prequeued jobs drain in order`()
```

The same fallback principle applies to release hardening and narrow package
validation when SwiftPM is blocked:

1. Run `xcodebuild build-for-testing` from the repo root with `-scheme SpeakSwiftly-Package`.
2. Reuse the generated `.xctestrun` file for one targeted `xcodebuild test-without-building` run at a time.
3. Prefer targeted reruns over broad shotgun retries so the failure surface stays readable.

GitHub Actions should follow that same fallback lane for package compilation and
tests. Keep `swift package dump-package` as the manifest sanity check, but use
the repo-root Xcode-backed package lane for CI build-and-test coverage until
the vendored parser failure is gone.

Long deep-trace playback probe:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_DEEP_TRACE_E2E=1 swift test --filter SpeakSwiftlyE2ETests/longCodeHeavy
```

Opt-in qwen resident benchmark comparison:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1 swift test --filter SpeakSwiftlyE2ETests/QwenBenchmarkSuite
```

Without `SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1`, the benchmark suite is skipped during ordinary `SPEAKSWIFTLY_E2E=1` runs so the default full e2e lane stays release-safe.

Run multiple comparison samples per Qwen conditioning strategy:

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
