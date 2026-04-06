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

Library consumers can still submit raw JSONL lines through the process boundary, but they can also use the typed Swift surface directly: start a `SpeakSwiftly.Runtime`, observe `SpeakSwiftly.StatusEvent` updates from `statusEvents()`, and consume per-request output through `SpeakSwiftly.RequestHandle.events`. Once the runtime has started, new `statusEvents()` subscribers receive an immediate snapshot of the current worker state before later transitions continue through the stream.

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

### Motivation

The point of this package is to keep the MLX and Apple-runtime concerns in one small Swift worker without forcing a larger app or service to reimplement `mlx-audio-swift` behavior. The worker should stay intentionally thin. Extra wrappers, managers, bridges, coordinators, or protocol layers would be very easy to over-add here and would risk overcomplicating a tool that is meant to be a boring process boundary.

The first intended runtime shape is:

- A long-lived executable owned by another process.
- Newline-delimited JSON over `stdin` and `stdout`.
- A resident `Qwen3-TTS 0.6B` path that pre-warms on startup and stays alive for live streamed playback from this process.
- An on-demand `Qwen3 VoiceDesign 1.7B` path that creates stored voice profiles from generated audio plus the source text used to create them.
- A second on-demand clone path that imports caller-provided reference audio, infers a transcript when needed through `MLXAudioSTT`, and stores the result as a reusable named voice profile.
- Immutable named voice profiles stored by this package and selected by name for `0.6B` playback requests.
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

Each published runtime includes:

- the `SpeakSwiftly` executable
- the bundled `mlx-swift_Cmlx.bundle/.../default.metallib`
- a metadata manifest at [`.local/xcode/SpeakSwiftly.debug.json`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/SpeakSwiftly.debug.json) or [`.local/xcode/SpeakSwiftly.release.json`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/SpeakSwiftly.release.json)

## Usage

Use `swift run` only for fast package-local development that does not need the real MLX Metal runtime. For the real worker executable, publish the runtime first, then run the product from the published runtime directory with `DYLD_FRAMEWORK_PATH` pointing at that same directory.

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug

DYLD_FRAMEWORK_PATH="$PWD/.local/xcode/Debug" \
  "$PWD/.local/xcode/Debug/SpeakSwiftly"
```

At startup the worker begins preloading the resident `0.6B` model and emits JSONL status events on `stdout`.

## Command Reference

The intended first protocol is newline-delimited JSON over standard input and output.

Example request shapes:

```json
{"id":"req-1","op":"queue_speech_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1c","op":"queue_speech_live","text":"stderr: broken pipe","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}
{"id":"req-1d","op":"queue_speech_live","text":"```swift\nlet sampleRate = profile?.sampleRate ?? 24000\n```","profile_name":"default-femme","text_format":"markdown","nested_source_format":"swift_source"}
{"id":"req-1e","op":"queue_speech_live","text":"struct WorkerRuntime { let sampleRate: Int }","profile_name":"default-femme","source_format":"swift_source"}
{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"A warm, bright, feminine narrator voice.","output_path":"/tmp/bright-guide.wav"}
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
{"id":"req-2","ok":true,"profile_name":"bright-guide","profile_path":"/path/to/profile"}
{"id":"req-3","ok":true,"profiles":[{"profile_name":"bright-guide","created_at":"2026-04-01T12:00:00Z","voice_description":"A warm, bright, feminine narrator voice.","source_text":"Hello there"}]}
{"id":"req-6","ok":true,"text_profiles":[{"id":"logs","name":"Logs","replacements":[{"id":"logs-rule","text":"stderr","replacement":"standard error","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]}],"text_profile_path":"/path/to/text-profiles.json"}
{"id":"req-9","ok":true,"text_profile":{"id":"ops","name":"Ops","replacements":[{"id":"ops-rule","text":"stdout","replacement":"standard output","match":"exact_phrase","phase":"before_built_ins","isCaseSensitive":false,"formats":[],"priority":0}]},"text_profile_path":"/path/to/text-profiles.json"}
{"id":"req-10","ok":false,"code":"profile_not_found","message":"Profile 'ghost' was not found in the SpeakSwiftly profile store."}
```

Queued events are only emitted for requests that will actually wait. Once the resident model is ready, waiting live playback requests are scheduled ahead of waiting non-playback work, but active work is never interrupted.

`queue_speech_live` is the wire-level live playback operation. The worker acknowledges queue acceptance immediately through the request stream, then emits the usual `started`, `progress`, and terminal success or failure events later as playback advances.

The `text_profile_*`, `load_text_profiles`, `save_text_profiles`, and `*_text_replacement` operations are immediate control operations. They do not wait for resident-model warmup and do not enter the serialized speech-generation queue.

Current operation families are:

- Resident `0.6B` startup warmup and live playback with named stored profiles.
- On-demand `1.7B` VoiceDesign profile creation.
- On-demand clone profile creation from caller-provided reference audio, with optional transcript inference.
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
- `Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimeTests.swift`
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

The current typed voice-profile creation helpers on `SpeakSwiftly.Runtime` are:

- `createProfile(named:from:voice:outputPath:id:)`
- `createClone(named:from:transcript:id:)`

Current live-playback behavior is:

- `queue_speech_live` loads the stored profile and reference audio first.
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

Opt-in real-model e2e coverage is available for three main sequential workflows, and the harness now publishes and launches the shared Debug runtime automatically at [`.local/xcode/Debug`](/Users/galew/Workspace/SpeakSwiftly/.local/xcode/Debug):

- VoiceDesign profile creation, then silent playback, then audible playback.
- Clone profile creation from caller-provided reference audio plus transcript, then silent playback, then audible playback.
- Clone profile creation from caller-provided reference audio with transcript inference, then silent playback, then audible playback. That third lane also checks that the inferred transcript stays meaningfully close to the known spoken source text used to generate the reference audio fixture inside the sandbox.

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

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

If a real worker run fails with a message about `default.metallib` or `mlx-swift_Cmlx.bundle`, the executable was almost certainly launched from a plain SwiftPM build instead of a published Xcode-backed runtime directory. Re-publish the runtime, then run the executable with `DYLD_FRAMEWORK_PATH` pointed at the matching published runtime directory.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
