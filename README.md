# SpeakSwiftly

A Swift speech worker and runtime package for long-lived local text-to-speech built on `mlx-audio-swift`.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [Command Reference](#command-reference)
- [Repository Layout](#repository-layout)
- [Development](#development)
- [Verification](#verification)
- [License](#license)

## Overview

SpeakSwiftly is a Swift Package Manager package built to be launched and owned by another process, such as a macOS app or a Python service. It keeps the MLX-backed speech runtime in one focused place while still exposing typed Swift APIs for callers that do not want to speak JSONL directly.

The package also ships two reusable library products:

- `SpeakSwiftlyCore` exposes the speech worker runtime as the namespaced `SpeakSwiftly` Swift API.
- `TextForSpeech` exposes the reusable text-normalization core as the namespaced `TextForSpeech` Swift API.

Library consumers can still submit raw JSONL lines through the process boundary, but they can also use the typed Swift surface directly: start a `SpeakSwiftly.Runtime`, observe `SpeakSwiftly.StatusEvent` updates from `statusEvents()`, consume per-request output through `SpeakSwiftly.RequestHandle.events`, and persist runtime preferences such as the resident speech backend through `SpeakSwiftly.Configuration`. Once the runtime has started, new `statusEvents()` subscribers receive an immediate snapshot of the current worker state before later transitions continue through the stream.

For example:

```swift
import SpeakSwiftlyCore
import TextForSpeech

let normalizer = SpeakSwiftly.Normalizer()
try await normalizer.storeProfile(
    TextForSpeech.Profile(
        id: "logs",
        name: "Logs",
        replacements: [
            TextForSpeech.Replacement("stderr", with: "standard error")
        ]
    )
)

let runtime = await SpeakSwiftly.live(normalizer: normalizer)
await runtime.start()

let handle = await runtime.speak(
    text: "Hello there.",
    with: "default-femme",
    as: .live,
    textProfileName: "logs",
    textContext: TextForSpeech.Context(
        cwd: "/Users/galew/Workspace/SpeakSwiftly",
        repoRoot: "/Users/galew/Workspace/SpeakSwiftly"
    )
)

for try await event in handle.events {
    print(event)
}
```

Use `sourceFormat` when the whole input is source code instead of mixed prose with embedded code:

```swift
import SpeakSwiftlyCore
import TextForSpeech

let sourceHandle = await runtime.speak(
    text: "struct WorkerRuntime { let sampleRate: Int }",
    with: "default-femme",
    as: .live,
    sourceFormat: .swift
)
```

Text shaping is its own typed surface too. `SpeakSwiftly.Normalizer` is a first-class object that owns text-profile state and persistence, and `SpeakSwiftly.Runtime` can consume an injected normalizer for speech work. `runtime.normalizer` still exists as a compatibility alias to the injected normalizer, but it is no longer the primary API to build around.

Runtime preferences have a matching typed surface:

```swift
import SpeakSwiftlyCore

let configuration = SpeakSwiftly.Configuration(speechBackend: .marvis)
try configuration.saveDefault()

let runtime = await SpeakSwiftly.live(configuration: configuration)
```

### Motivation

The point of this package is to keep the MLX and Apple-runtime concerns in one small Swift worker without forcing a larger app or service to reimplement `mlx-audio-swift` behavior. The worker should stay intentionally thin. Extra wrappers, managers, bridges, coordinators, or protocol layers would be very easy to over-add here and would risk overcomplicating a tool that is meant to be a boring process boundary.

The first intended runtime shape is:

- A long-lived executable owned by another process.
- Newline-delimited JSON over `stdin` and `stdout`.
- A resident `Qwen3-TTS 0.6B` path that pre-warms on startup and stays alive for live streamed playback from this process.
- An on-demand `Qwen3 VoiceDesign 1.7B` path that creates stored voice profiles from generated audio plus the source text used to create them.
- A second on-demand clone path that imports caller-provided reference audio, requires an explicit profile `vibe`, targets around 10 seconds of clear source speech, infers a transcript when needed through `MLXAudioSTT`, and stores the result as a reusable named voice profile.
- Immutable named voice profiles stored by this package and selected by name for `0.6B` playback requests.
- A persisted runtime configuration file that can remember the preferred resident speech backend across launches.
- Resident backend switching only between `qwen3` and `marvis`.
- Marvis resident warmup that keeps both built-in prompt voices hot and routes requests by stored profile vibe: `.femme` and `.androgenous` use `conversational_a`, while `.masc` uses `conversational_b`.
- A single-consumer priority queue for incoming requests, with waiting live playback work preferred over waiting non-playback work.
- Requests accepted during resident-model preload, with structured status events that explain the model is still loading and when queued work begins processing.
- Structured progress and lifecycle events written to `stdout`, with structured JSONL operator diagnostics on `stderr`.

## Setup

This repository is a standard Swift package with [`mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift) wired in as the model and runtime dependency.

Library consumers can depend on the package directly from GitHub:

```swift
.package(url: "https://github.com/gaelic-ghost/SpeakSwiftly.git", from: "0.9.2")
```

Then add the `SpeakSwiftlyCore` product to the target that will own the runtime. If the caller also wants direct access to text-profile primitives, add [`TextForSpeech`](https://github.com/gaelic-ghost/TextForSpeech.git) separately too.

```bash
swift build
```

The executable intentionally leans on the existing `mlx-audio-swift` API surface and keeps its own scope focused on process ownership, queueing, playback, and profile storage.

For real MLX-backed runs, use the repo-maintenance runtime publisher instead of relying on the SwiftPM command-line executable. Upstream `mlx-swift` is explicit that command-line SwiftPM does not build the Metal shader bundle, while `xcodebuild` does, and command-line tools need that bundle visible at runtime.

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/publish-runtime.sh --configuration Release
```

That command publishes stable local Xcode-backed runtime directories here:

- Debug: [`.local/xcode/Debug`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/Debug)
- Release: [`.local/xcode/Release`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/Release)
- Stable aliases: [`.local/xcode/current-debug`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/current-debug) and [`.local/xcode/current-release`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/current-release)

Each published runtime includes:

- the `SpeakSwiftly` executable
- a `run-speakswiftly` launcher that sets `DYLD_FRAMEWORK_PATH` for the matching published runtime directory
- the bundled `mlx-swift_Cmlx.bundle/.../default.metallib`
- a metadata manifest at [`.local/xcode/SpeakSwiftly.debug.json`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/SpeakSwiftly.debug.json) or [`.local/xcode/SpeakSwiftly.release.json`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/SpeakSwiftly.release.json) with the executable, launcher, bundle, metallib, and stable alias paths

### Runtime Configuration

`SpeakSwiftly.Configuration` is the public typed runtime-preference surface. Right now it stores the resident `speechBackend`, and it is designed to widen as more user-facing runtime settings are added.

The default persisted configuration path is:

- macOS default: `~/Library/Application Support/SpeakSwiftly/configuration.json`
- with `SPEAKSWIFTLY_PROFILE_ROOT=/custom/profiles`: `/custom/configuration.json`

Backend resolution follows one rule everywhere:

1. explicit `speechBackend:` passed to `SpeakSwiftly.live(...)`
2. explicit `configuration:` passed to `SpeakSwiftly.live(...)`
3. `SPEAKSWIFTLY_SPEECH_BACKEND`
4. persisted `configuration.json`
5. fallback `.qwen3`

That means environment overrides are still useful for one-off runs, while persisted configuration is the stable “remember my preference” path.

## Usage

Use `swift run` only for fast package-local development that does not need the real MLX Metal runtime. For the real worker executable, publish the runtime first, then launch it through the published runtime launcher or the stable alias.

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug

"$PWD/.local/xcode/current-debug/run-speakswiftly"
```

At startup the worker begins preloading the resident `0.6B` model and emits JSONL status events on `stdout`.

If you want to force a one-off backend without changing the persisted configuration, set `SPEAKSWIFTLY_SPEECH_BACKEND` to `qwen3` or `marvis` before launching the worker.

## Command Reference

The intended first protocol is newline-delimited JSON over standard input and output.

Example request shapes:

```json
{"id":"req-1","op":"queue_speech_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1c","op":"queue_speech_live","text":"stderr: broken pipe","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}
{"id":"req-1d","op":"queue_speech_live","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}
{"id":"req-1e","op":"queue_speech_live","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}
{"id":"req-1f","op":"queue_speech_file","text":"Save this one for later playback.","profile_name":"default-femme"}
{"id":"req-1g","op":"queue_speech_batch","profile_name":"default-femme","items":[{"text":"First saved file."},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs"}]}
{"id":"req-1h","op":"generated_file","artifact_id":"req-1f-artifact-1"}
{"id":"req-1i","op":"generated_files"}
{"id":"req-1j","op":"generated_batch","batch_id":"req-1g"}
{"id":"req-1k","op":"generated_batches"}
{"id":"req-1l","op":"generation_job","job_id":"req-1f"}
{"id":"req-1m","op":"generation_jobs"}
{"id":"req-1n","op":"expire_generation_job","job_id":"req-1g"}
{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello there","vibe":"femme","voice_description":"A warm, bright, feminine narrator voice.","output_path":"/tmp/bright-guide.wav"}
{"id":"req-3","op":"list_profiles"}
{"id":"req-4","op":"remove_profile","profile_name":"bright-guide"}
{"id":"req-5","op":"text_profile_active"}
{"id":"req-6","op":"text_profiles"}
{"id":"req-7","op":"create_text_profile","text_profile_id":"logs","text_profile_display_name":"Logs"}
{"id":"req-8","op":"add_text_replacement","text_profile_name":"logs","replacement":{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}}
{"id":"req-9","op":"use_text_profile","text_profile":{"id":"ops","name":"Ops","replacements":[{"id":"ops-rule","text":"stdout","replacement":"standard output","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]}}
```

Example response and event shapes:

```json
{"event":"worker_status","stage":"warming_resident_model"}
{"id":"req-1","event":"queued","reason":"waiting_for_resident_model","queue_position":1}
{"id":"req-2","event":"queued","reason":"waiting_for_active_request","queue_position":2}
{"event":"worker_status","stage":"resident_model_ready"}
{"id":"req-1","event":"started","op":"queue_speech_live"}
{"id":"req-1","event":"progress","stage":"buffering_audio"}
{"id":"req-1","event":"progress","stage":"preroll_ready"}
{"id":"req-1","event":"progress","stage":"playback_finished"}
{"id":"req-1","ok":true}
{"id":"req-1f","ok":true}
{"id":"req-1f","event":"started","op":"queue_speech_file"}
{"id":"req-1f","event":"progress","stage":"generating_file_audio"}
{"id":"req-1f","event":"progress","stage":"writing_generated_file"}
{"id":"req-1f","ok":true,"generated_file":{"artifact_id":"req-1f-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"},"generation_job":{"job_id":"req-1f","job_kind":"file","state":"completed","items":[{"artifact_id":"req-1f-artifact-1","text":"Save this one for later playback.","text_profile_name":null,"text_context":null,"source_format":null}]}}
{"id":"req-1g","ok":true}
{"id":"req-1g","event":"started","op":"queue_speech_batch"}
{"id":"req-1g","ok":true,"generated_batch":{"batch_id":"req-1g","profile_name":"default-femme","text_profile_name":null,"speech_backend":"marvis","state":"completed","items":[{"artifact_id":"req-1g-artifact-1","text":"First saved file.","text_profile_name":null,"text_context":null,"source_format":null},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs","text_context":null,"source_format":null}],"artifacts":[{"artifact_id":"req-1g-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:01Z","file_path":"/tmp/generated-files/7265712d31672d61727469666163742d31/generated.wav"},{"artifact_id":"custom-batch-artifact","profile_name":"default-femme","text_profile_name":"logs","sample_rate":24000,"created_at":"2026-04-07T18:22:02Z","file_path":"/tmp/generated-files/637573746f6d2d62617463682d6172746966616374/generated.wav"}]}}
{"id":"req-1h","ok":true,"generated_file":{"artifact_id":"req-1f-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"}}
{"id":"req-1i","ok":true,"generated_files":[{"artifact_id":"req-1f-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:00Z","file_path":"/tmp/generated-files/7265712d31662d61727469666163742d31/generated.wav"}]}
{"id":"req-1j","ok":true,"generated_batch":{"batch_id":"req-1g","profile_name":"default-femme","text_profile_name":null,"speech_backend":"marvis","state":"completed","items":[{"artifact_id":"req-1g-artifact-1","text":"First saved file.","text_profile_name":null,"text_context":null,"source_format":null},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs","text_context":null,"source_format":null}],"artifacts":[{"artifact_id":"req-1g-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:01Z","file_path":"/tmp/generated-files/7265712d31672d61727469666163742d31/generated.wav"},{"artifact_id":"custom-batch-artifact","profile_name":"default-femme","text_profile_name":"logs","sample_rate":24000,"created_at":"2026-04-07T18:22:02Z","file_path":"/tmp/generated-files/637573746f6d2d62617463682d6172746966616374/generated.wav"}]}}
{"id":"req-1k","ok":true,"generated_batches":[{"batch_id":"req-1g","profile_name":"default-femme","text_profile_name":null,"speech_backend":"marvis","state":"completed","items":[{"artifact_id":"req-1g-artifact-1","text":"First saved file.","text_profile_name":null,"text_context":null,"source_format":null},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs","text_context":null,"source_format":null}],"artifacts":[{"artifact_id":"req-1g-artifact-1","profile_name":"default-femme","text_profile_name":null,"sample_rate":24000,"created_at":"2026-04-07T18:22:01Z","file_path":"/tmp/generated-files/7265712d31672d61727469666163742d31/generated.wav"},{"artifact_id":"custom-batch-artifact","profile_name":"default-femme","text_profile_name":"logs","sample_rate":24000,"created_at":"2026-04-07T18:22:02Z","file_path":"/tmp/generated-files/637573746f6d2d62617463682d6172746966616374/generated.wav"}]}]}
{"id":"req-1n","ok":true,"generation_job":{"job_id":"req-1g","job_kind":"batch","state":"expired","expires_at":"2026-04-07T18:40:00Z","items":[{"artifact_id":"req-1g-artifact-1","text":"First saved file.","text_profile_name":null,"text_context":null,"source_format":null},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs","text_context":null,"source_format":null}],"artifacts":[{"artifact_id":"req-1g-artifact-1","kind":"audio_wav","created_at":"2026-04-07T18:22:01Z","file_path":"/tmp/generated-files/7265712d31672d61727469666163742d31/generated.wav","sample_rate":24000,"profile_name":"default-femme","text_profile_name":null},{"artifact_id":"custom-batch-artifact","kind":"audio_wav","created_at":"2026-04-07T18:22:02Z","file_path":"/tmp/generated-files/637573746f6d2d62617463682d6172746966616374/generated.wav","sample_rate":24000,"profile_name":"default-femme","text_profile_name":"logs"}]}}
{"id":"req-2","ok":true,"profile_name":"bright-guide","profile_path":"/path/to/profile"}
{"id":"req-3","ok":true,"profiles":[{"profile_name":"bright-guide","vibe":"femme","created_at":"2026-04-01T12:00:00Z","voice_description":"A warm, bright, feminine narrator voice.","source_text":"Hello there"}]}
{"id":"req-6","ok":true,"text_profiles":[{"id":"logs","name":"Logs","replacements":[{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]}],"text_profile_path":"/path/to/text-profiles.json"}
{"id":"req-9","ok":true,"text_profile":{"id":"ops","name":"Ops","replacements":[{"id":"ops-rule","text":"stdout","replacement":"standard output","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]},"text_profile_path":"/path/to/text-profiles.json"}
{"id":"req-10","ok":false,"code":"profile_not_found","message":"Profile 'ghost' was not found in the SpeakSwiftly profile store."}
```

Queued events are only emitted for requests that will actually wait. Once the resident model is ready, waiting live playback requests are scheduled ahead of waiting non-playback work, but active work is never interrupted.

`queue_speech_live` is the wire-level live playback operation. The worker acknowledges queue acceptance immediately through the request stream, then emits the usual `started`, `progress`, and terminal success or failure events later as playback advances.

`queue_speech_file` uses the same resident generation queue, but it never enters the playback queue. It acknowledges queue acceptance immediately, renders and saves a managed WAV artifact under the runtime store, then emits a terminal success payload with `generated_file` metadata plus the persisted file-job record. The file job id stays equal to the request id, while the saved artifact now gets its own durable `artifact_id`.

`queue_speech_batch` is the caller-facing many-files surface. One batch submission creates one batch job, resolves one durable artifact id per item up front, renders each file through the same resident generation path, and finishes with a `generated_batch` payload that lists the saved artifacts for that batch.

`generated_file`, `generated_files`, `generated_batch`, `generated_batches`, `generation_job`, `generation_jobs`, `expire_generation_job`, `text_profile_*`, `load_text_profiles`, `save_text_profiles`, and `*_text_replacement` are immediate control operations. They do not wait for resident-model warmup and do not enter the serialized speech-generation queue.

Current operation families are:

- Resident `0.6B` startup warmup and live playback with named stored profiles.
- Resident `0.6B` startup warmup and generated-file rendering with persisted file jobs, batch jobs, managed artifact metadata, and reconnectable fetch/list reads.
- On-demand `1.7B` VoiceDesign profile creation.
- On-demand clone profile creation from caller-provided reference audio, with a required `vibe`, a documented target of around 10 seconds of clear source speech, and optional transcript inference.
- Immutable profile storage, selection, listing, and removal.
- Immediate text-profile inspection, persistence, and replacement editing with JSONL and typed-library parity.
- Playback-prioritized request handling with preload-aware queue status.
- Structured terminal success and failure responses.
- Structured JSONL `stderr` logs that explain the most likely cause when something breaks and include request timing context.

The test suite is organized to mirror the source tree:

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

The package also includes `TextForSpeech` coverage for normalization context, profile primitives, persistence, and effective-profile behavior.

The typed text-profile helpers live on top-level `SpeakSwiftly.Normalizer` instances:

```swift
let normalizer = SpeakSwiftly.Normalizer(
    persistenceURL: profilesURL
)

try await normalizer.loadProfiles()
try await normalizer.addReplacement(
    TextForSpeech.Replacement("stderr", with: "standard error")
)

let runtime = await SpeakSwiftly.live(normalizer: normalizer)
```

Current `SpeakSwiftly.Normalizer` helpers are:

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

The current typed generation and profile helpers on `SpeakSwiftly.Runtime` are:

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

Current live-playback behavior is:

- `queue_speech_live` loads the stored profile first, then routes resident generation through the active backend. `qwen3` uses the stored profile reference audio and transcript, while `marvis` uses the stored profile vibe to select the already-warm built-in preset voice.
- `queue_speech_file` follows that same backend-routing path, then saves the completed WAV under the generated-file store instead of scheduling playback.
- Marvis resident warmup keeps both `conversational_a` and `conversational_b` loaded at once because the model is small enough that per-request preset switching does not need another preload cycle.
- Profile `vibe` currently drives Marvis routing like this: `.femme` -> `conversational_a`, `.androgenous` -> `conversational_a`, `.masc` -> `conversational_b`.
- The resident `0.6B` model streams generated chunks at the current `0.18` cadence.
- The resident and profile-generation paths now pass explicit local generation parameters instead of relying on whatever default values the current `mlx-audio-swift` dependency tip happens to expose, which helps keep short utterances from drifting back into runaway generation behavior.
- Playback is now owned by a real `PlaybackController` actor in `Sources/SpeakSwiftly/Playback/PlaybackController.swift`, while the lower-level AVFoundation engine driver stays internal to the playback feature instead of living in `Runtime/`.
- The local `AVAudioEngine` and `AVAudioPlayerNode` are prepared as part of resident-model warmup and then reused across requests instead of being recreated for each utterance.
- Real playback uses adaptive duration-based thresholds instead of the older fixed chunk gate. Compact requests seed around `360 ms` of startup audio, balanced requests around `520 ms`, and extended requests much higher, with later cadence and rebuffer signals able to raise those targets further during playback.
- Requests emit `buffering_audio` when the first non-empty chunk arrives and `preroll_ready` when the startup buffer has been satisfied and audio has been scheduled into the hot player path.
- The worker keeps an adaptive queue-floor policy during playback. Compact requests seed around `140 ms` of low-water buffer, balanced requests around `220 ms`, and extended requests much higher, with repeated slow cadence, rebuffers, or starvation able to push those thresholds upward.
- The worker records queue-depth summaries, chunk-arrival gaps, scheduling gaps, rebuffer durations, callback counts, chunk-boundary shape metrics, and process / MLX memory snapshots so playback health can be diagnosed without guessing from one or two timestamps.
- The worker logs low-queue warnings below 100 ms, chunk-gap warnings, scheduling-gap warnings, rebuffer start/resume events, rebuffer-thrash warnings, explicit starvation events, and a buffer-shape summary when chunk boundaries look suspicious.
- After generation finishes, playback drain uses a dynamic timeout based on queued audio plus padding, with a minimum of 5 seconds, so the worker does not fail long buffered requests with the same cutoff used for short ones.
- If drain completion times out, the request fails with `audio_playback_timeout` and the worker stays alive for later requests.
- For short forensic captures, set `SPEAKSWIFTLY_PLAYBACK_TRACE=1` to emit chunk-level trace JSONL events such as `playback_trace_chunk_received`, `playback_trace_buffer_scheduled`, and `playback_trace_buffer_played_back`. Leave that mode off for normal runs.

Current generated-file behavior is:

- File jobs use the request id as the durable job id, not the artifact id.
- Single-file generation currently resolves its saved artifact id as `<jobID>-artifact-1`.
- Batch generation resolves one saved artifact id per item, using the caller-provided `artifact_id` when present and `<batchID>-artifact-N` otherwise.
- Saved artifacts live in the runtime-managed generated-file store, not at a caller-provided output path.
- `generated_file` returns one stored artifact by `artifact_id`.
- `generated_files` returns the current artifact summaries known to the store.
- `generated_batch` returns one caller-facing batch projection backed by a batch job.
- `generated_batches` returns the current caller-facing batch projections backed by persisted batch jobs.
- `generation_job` and `generation_jobs` expose the lower-level persisted job records directly, including their resolved generation items and artifact references.
- `expire_generation_job` performs manual retention cleanup for one completed or failed generation job, removes any persisted artifact files it still owns, and leaves the job record behind in the `expired` state with `expires_at` stamped.
- Expired batch reads stay inspectable through `generated_batch` and `generated_batches`, but they return an empty `artifacts` list because the saved files are intentionally gone.
- Expired file and batch jobs keep their artifact references inside `generation_job` and `generation_jobs` so operators can still see what existed before cleanup ran.
- `list_profiles` ignores stray files, partial directories, generated-artifact directories, and one-off corrupt profile entries so one bad entry does not poison the whole voice-profile surface.

Current `stderr` observability is JSONL with fields such as:

- `event`
- `level`
- `ts`
- `request_id`
- `op`
- `profile_name`
- `queue_depth`
- `elapsed_ms`
- `details`

That log stream currently covers resident-model preload, request accept / queue / start / success / failure, playback milestones, queue-depth warnings, scheduling and chunk-gap warnings, rebuffer durations, starvation events, buffer-shape summaries, optional chunk-level playback tracing, profile-store operations, and process / MLX memory fields such as resident size, physical footprint, active MLX memory, cache memory, and peak MLX memory at key playback checkpoints.

For text-shape forensics, the worker also logs narrow per-shape counts such as markdown headers, fenced code blocks, inline code spans, markdown links, URLs, file paths, identifier families, and repeated-letter runs. Playback threshold seeding itself remains length-based up front; those forensic counters are there to help explain difficult prompt shapes after the fact.

## Repository Layout

SpeakSwiftly is intended to be the source-of-truth standalone repository for this package.

The package source tree is organized by responsibility:

- `Sources/SpeakSwiftly/API` contains the public package-facing library surface.
- `Sources/SpeakSwiftly/Generation` contains generation and voice-profile logic.
- `Sources/SpeakSwiftly/Normalization` contains `SpeakSwiftly.Normalizer` and text-normalization logic.
- `Sources/SpeakSwiftly/Playback` contains the playback subsystem, including the real `PlaybackController` type and playback operations.
- `Sources/SpeakSwiftly/Runtime` contains worker-runtime internals such as protocol decoding, request orchestration, lifecycle, and emission.

The preferred ownership model is:

- This repository remains the primary development home for [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly).
- The larger [`speak-to-user`](https://github.com/gaelic-ghost/speak-to-user) repository consumes `SpeakSwiftly` as a Git submodule under `packages/SpeakSwiftly`.
- Feature work happens here first, and the consuming repository updates its submodule pointer when it is ready to adopt a newer revision.

That arrangement keeps the package history, tags, and releases independent while still letting the larger repository pin an exact commit.

Older adjacent consumers such as [`speak-to-user-mcp`](https://github.com/gaelic-ghost/speak-to-user-mcp) and [`speak-to-user-server`](https://github.com/gaelic-ghost/speak-to-user-server) should now point at one shared published runtime directory instead of relying on tag-triggered copy hooks or raw DerivedData guesses. The preferred local development shape is to publish `SpeakSwiftly` once here and then point those hosts at the stable runtime directory so the executable and MLX bundle stay together.

When `speak-to-user` is using this package, the expected package path is:

```text
../speak-to-user/packages/SpeakSwiftly
```

The standalone checkout remains the preferred day-to-day development workspace. The submodule checkout in `speak-to-user` is primarily for integration and consumption.

## Development

Keep the package small and concrete.

- Prefer direct data flow over helper abstractions.
- Keep the executable as the boundary instead of inventing extra internal service layers.
- Let `mlx-audio-swift` own model loading and generation whenever its existing surface is sufficient.
- Treat `stdin` and `stdout` as the worker contract and `stderr` as operator-facing logging.
- Keep stored profiles simple and inspectable: profile metadata, source text, and reference audio on disk.
- Add new packages only when they clearly simplify the code. Extra dependencies and architecture layers are often unnecessary here and should get extra scrutiny before and after they are introduced.

## Verification

Use the package baseline checks after each meaningful change.

```bash
swift build
swift test
```

Real MLX-backed validation should use a published Xcode-backed worker runtime. A reproducible local command is:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
```

You can verify a published local runtime directly with:

```bash
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Release
```

Opt-in real-model e2e coverage is available for five main workflows, and the harness now publishes and launches the shared Debug runtime automatically through the published manifest and stable alias at [`.local/xcode/current-debug`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/current-debug):

- VoiceDesign profile creation, then silent playback, then audible playback.
- Clone profile creation from caller-provided reference audio plus transcript, then silent playback, then audible playback.
- Clone profile creation from caller-provided reference audio with transcript inference, then silent playback, then audible playback. That third lane also checks that the inferred transcript stays meaningfully close to the known spoken source text used to generate the reference audio fixture inside the sandbox.
- Marvis voice-design profile creation for femme, masc, and androgenous vibes, followed by audible live playback across all three profiles on one resident Marvis worker so the full backend routing and playback path is exercised end to end.
- Generated batch submission, then `generated_batch` and `generated_batches` reads against the real worker with saved artifact files verified on disk.

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

If you want that full suite to force real audible playback even for lanes that usually request silent playback, add the audible env flag:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_AUDIBLE_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

Real-model e2e worker runs now retain durable artifacts under [`.local/e2e-runs`](/Users/galew/Workspace/SpeakSwiftly/.local/e2e-runs). Each run writes `stdout.jsonl`, `stderr.jsonl`, and a compact `summary.json` so playback, runtime-memory, and runtime-CPU evidence can be inspected after the test finishes.

If you want chunk-level playback trace logs during that real run, add the trace env flag:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests
```

If you want the long forensic playback probe with code fences, file paths, and oddly spelled words, add the forensic env flag as well:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithLongCodeHeavyRequest
```

If you want the section-aware weird-text forensic probes, these opt-in commands exercise the normal and reversed section-order variants with chunk-level trace enabled:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithSegmentedWeirdTextRequest
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithReversedSegmentedWeirdTextRequest
```

If you want matched section-aware conversational prose probes for comparison against the code-heavy runs, these opt-in commands exercise the forward and reversed prose variants with chunk-level trace enabled:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithSegmentedConversationalProseRequest
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_FORENSIC_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter SpeakSwiftlyE2ETests/forensicSpeakLiveRunsEndToEndWithReversedSegmentedConversationalProseRequest
```

The real-model e2e coverage uses a shared profile convention named `testing-profile` with the voice description `A generic, warm, masculine, slow speaking voice.` Each workflow still runs inside its own isolated profile root, but using the same profile shape keeps downstream app e2e coverage aligned with this package.

If a real worker run fails with a message about `default.metallib` or `mlx-swift_Cmlx.bundle`, the executable was almost certainly launched from a plain SwiftPM build instead of a published Xcode-backed runtime directory. Re-publish the runtime, verify it with `verify-runtime.sh`, then launch through the published `run-speakswiftly` script or the stable alias.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
