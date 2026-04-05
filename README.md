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

let runtime = await SpeakSwiftly.live()
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

Text shaping is part of the typed runtime surface too. `SpeakSwiftly.Runtime` can read the active, base, stored, and effective text profiles, persist changes through the adjacent `TextForSpeech` runtime, and incrementally add, replace, or remove text replacements without rebuilding whole profile values for each small edit.

### Motivation

The point of this package is to keep the MLX and Apple-runtime concerns in one small Swift worker without forcing a larger app or service to reimplement `mlx-audio-swift` behavior. The worker should stay intentionally thin. Extra wrappers, managers, bridges, coordinators, or protocol layers would be very easy to over-add here and would risk overcomplicating a tool that is meant to be a boring process boundary.

The first intended runtime shape is:

- A long-lived executable owned by another process.
- Newline-delimited JSON over `stdin` and `stdout`.
- A resident `Qwen3-TTS 0.6B` path that pre-warms on startup and stays alive for live streamed playback from this process.
- An on-demand `Qwen3 VoiceDesign 1.7B` path that creates stored voice profiles from generated audio plus the source text used to create them.
- Immutable named voice profiles stored by this package and selected by name for `0.6B` playback requests.
- A single-consumer priority queue for incoming requests, with waiting live playback work preferred over waiting non-playback work.
- Requests accepted during resident-model preload, with structured status events that explain the model is still loading and when queued work begins processing.
- Structured progress and lifecycle events written to `stdout`, with structured JSONL operator diagnostics on `stderr`.

## Setup

This repository is a standard Swift package with [`mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift) wired in as the model and runtime dependency.

Library consumers can depend on the package directly from GitHub:

```swift
.package(url: "https://github.com/gaelic-ghost/SpeakSwiftly.git", from: "0.9.0")
```

Then add the `SpeakSwiftlyCore` product to the target that will own the runtime. If the caller also wants direct access to text-profile primitives, add [`TextForSpeech`](https://github.com/gaelic-ghost/TextForSpeech.git) separately too.

```bash
swift build
```

The executable intentionally leans on the existing `mlx-audio-swift` API surface and keeps its own scope focused on process ownership, queueing, playback, and profile storage.

For real MLX-backed runs, use `xcodebuild` instead of relying on the SwiftPM command-line executable. Upstream `mlx-swift` is explicit that command-line SwiftPM does not build the Metal shader bundle, while `xcodebuild` does, and command-line tools need that bundle visible at runtime.

```bash
xcodebuild build \
  -scheme SpeakSwiftly \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/.derived" \
  -clonedSourcePackagesDirPath /tmp/SpeakSwiftly-xcodebuild-spm
```

## Usage

Use `swift run` only for fast package-local development that does not need the real MLX Metal runtime. For the real worker executable, build with `xcodebuild` and run the product from the Xcode build directory with `DYLD_FRAMEWORK_PATH` pointing at that same products directory.

```bash
xcodebuild build \
  -scheme SpeakSwiftly \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/.derived" \
  -clonedSourcePackagesDirPath /tmp/SpeakSwiftly-xcodebuild-spm

DYLD_FRAMEWORK_PATH="$PWD/.derived/Build/Products/Debug" \
  "$PWD/.derived/Build/Products/Debug/SpeakSwiftly"
```

At startup the worker begins preloading the resident `0.6B` model and emits JSONL status events on `stdout`.

## Command Reference

The intended first protocol is newline-delimited JSON over standard input and output.

Example request shapes:

```json
{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1c","op":"speak_live","text":"stderr: broken pipe","profile_name":"default-femme","text_profile_name":"logs","cwd":"/Users/galew/Workspace/SpeakSwiftly","repo_root":"/Users/galew/Workspace/SpeakSwiftly","text_format":"cli_output"}
{"id":"req-1b","op":"speak_live_background","text":"Hello there","profile_name":"default-femme"}
{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"A warm, bright, feminine narrator voice.","output_path":"/tmp/bright-guide.wav"}
{"id":"req-3","op":"list_profiles"}
{"id":"req-4","op":"remove_profile","profile_name":"bright-guide"}
```

Example response and event shapes:

```json
{"event":"worker_status","stage":"warming_resident_model"}
{"id":"req-1","event":"queued","reason":"waiting_for_resident_model","queue_position":1}
{"id":"req-1b","ok":true}
{"id":"req-2","event":"queued","reason":"waiting_for_active_request","queue_position":2}
{"event":"worker_status","stage":"resident_model_ready"}
{"id":"req-1","event":"started","op":"speak_live"}
{"id":"req-1b","event":"started","op":"speak_live_background"}
{"id":"req-1","event":"progress","stage":"buffering_audio"}
{"id":"req-1","event":"progress","stage":"preroll_ready"}
{"id":"req-1","event":"progress","stage":"playback_finished"}
{"id":"req-1","ok":true}
{"id":"req-2","ok":true,"profile_name":"bright-guide","profile_path":"/path/to/profile"}
{"id":"req-3","ok":true,"profiles":[{"profile_name":"bright-guide","created_at":"2026-04-01T12:00:00Z","voice_description":"A warm, bright, feminine narrator voice.","source_text":"Hello there"}]}
{"id":"req-9","ok":false,"code":"profile_not_found","message":"Profile 'ghost' was not found in the SpeakSwiftly profile store."}
```

Queued events are only emitted for requests that will actually wait. Once the resident model is ready, waiting live playback requests are scheduled ahead of waiting non-playback work, but active work is never interrupted.

`speak_live_background` uses the same playback path as `speak_live`, but it acknowledges success as soon as the request has been accepted into the worker queue. That gives an owner process a queue-and-return path without changing the blocking semantics of `speak_live`. The background request still emits the usual `started` and `progress` events later, and it can still emit a later failure response if playback breaks after the enqueue acknowledgment.

Current operation families are:

- Resident `0.6B` startup warmup and live playback with named stored profiles.
- Queue-and-return live playback via `speak_live_background` for callers that want enqueue acknowledgment instead of waiting for playback completion.
- On-demand `1.7B` VoiceDesign profile creation.
- Immutable profile storage, selection, listing, and removal.
- Playback-prioritized request handling with preload-aware queue status.
- Structured terminal success and failure responses.
- Structured JSONL `stderr` logs that explain the most likely cause when something breaks and include request timing context.

The test suite is organized to mirror the source responsibilities:

- `WorkerProtocolTests.swift`
- `ProfileStoreTests.swift`
- `WorkerRuntimeTests.swift`
- `ModelClientsTests.swift`
- `SpeakSwiftlyE2ETests.swift`

The package also includes `TextForSpeech` coverage for normalization context, profile primitives, persistence, and effective-profile behavior.

The current typed text-profile helpers on `SpeakSwiftly.Runtime` are:

- `activeTextProfile()`
- `baseTextProfile()`
- `textProfile(named:)`
- `textProfiles()`
- `effectiveTextProfile(named:)`
- `createTextProfile(id:named:replacements:)`
- `storeTextProfile(_:)`
- `useTextProfile(_:)`
- `removeTextProfile(named:)`
- `resetTextProfile()`
- `addTextReplacement(_:)`
- `addTextReplacement(_:toStoredTextProfileNamed:)`
- `replaceTextReplacement(_:)`
- `replaceTextReplacement(_:inStoredTextProfileNamed:)`
- `removeTextReplacement(id:)`
- `removeTextReplacement(id:fromStoredTextProfileNamed:)`

Current live-playback behavior is:

- `speak_live` loads the stored profile and reference audio first.
- The resident `0.6B` model streams generated chunks at the current `0.18` cadence.
- The resident and profile-generation paths now pass explicit local generation parameters instead of relying on whatever default values the current `mlx-audio-swift` dependency tip happens to expose, which helps keep short utterances from drifting back into runaway generation behavior.
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

The preferred ownership model is:

- This repository remains the primary development home for [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly).
- The larger [`speak-to-user`](https://github.com/gaelic-ghost/speak-to-user) repository consumes `SpeakSwiftly` as a Git submodule under `packages/SpeakSwiftly`.
- Feature work happens here first, and the consuming repository updates its submodule pointer when it is ready to adopt a newer revision.

That arrangement keeps the package history, tags, and releases independent while still letting the larger repository pin an exact commit.

The local release workflow also has one adjacent-repo integration step now: the adjacent [`speak-to-user-mcp`](https://github.com/gaelic-ghost/speak-to-user-mcp) checkout includes a repo-managed hook installer at `scripts/install-speakswiftly-release-hook.sh` and a tag handler at `scripts/handle-adjacent-speakswiftly-release-tag.sh`. When that hook is installed there, a new local `SpeakSwiftly` release tag created here refreshes the cached worker runtime in `../speak-to-user-mcp` so the day-to-day MCP consumer stays aligned with the latest tagged standalone release.

Today that adjacent-repo refresh is intentionally narrow:

- It updates the cached binary used by [`speak-to-user-mcp`](https://github.com/gaelic-ghost/speak-to-user-mcp).
- It does not yet fan out to every other neighboring local repository that may also consume a cached `SpeakSwiftly` binary.
- Other adjacent consumers such as [`speak-to-user-server`](https://github.com/gaelic-ghost/speak-to-user-server) still need an explicit follow-up expansion of that release propagation workflow.

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

Real MLX-backed validation should use an Xcode-built worker product. A reproducible local command is:

```bash
xcodebuild build \
  -scheme SpeakSwiftly \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/.derived" \
  -clonedSourcePackagesDirPath /tmp/SpeakSwiftly-xcodebuild-spm
```

Opt-in real-model e2e coverage is available for the on-demand `1.7B` path, the resident `0.6B` path with silent playback, and the resident `0.6B` path through the real local `AVAudioEngine` playback stack. The harness builds and launches that Xcode-backed worker automatically:

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

The real-model e2e coverage uses a shared profile convention named `testing-profile` with the voice description `A generic, warm, masculine, slow speaking voice.` Each test still runs inside its own isolated profile root, but using the same profile shape keeps downstream app e2e coverage aligned with this package.

The default shared per-user profile store now also includes a real `testing-profile` created through the worker itself, so downstream apps can reuse the same clone profile outside the isolated e2e sandbox.

If a real worker run fails with a message about `default.metallib` or `mlx-swift_Cmlx.bundle`, the executable was almost certainly launched from a plain SwiftPM build instead of an Xcode-built products directory. Rebuild with `xcodebuild`, then run the executable with `DYLD_FRAMEWORK_PATH` pointed at the matching Xcode build products directory.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
