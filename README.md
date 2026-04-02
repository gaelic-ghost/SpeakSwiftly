# SpeakSwiftly

A thin Swift worker executable for long-lived local speech generation around `mlx-audio-swift`.

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

SpeakSwiftly is a small Swift Package Manager executable intended to be launched and owned by another process, such as a macOS app or a Python service.

### Motivation

The point of this package is to keep the MLX and Apple-runtime concerns in one small Swift worker without forcing a larger app or service to reimplement `mlx-audio-swift` behavior. The worker should stay intentionally thin. Extra wrappers, managers, bridges, coordinators, or protocol layers would be very easy to over-add here and would risk overcomplicating a tool that is meant to be a boring process boundary.

The first intended runtime shape is:

- A long-lived executable owned by another process.
- Newline-delimited JSON over `stdin` and `stdout`.
- A resident `Qwen3-TTS 0.6B` path that pre-warms on startup and stays alive for live streamed playback from this process.
- An on-demand `Qwen3 VoiceDesign 1.7B` path that creates stored voice profiles from generated audio plus the source text used to create them.
- Immutable named voice profiles stored by this package and selected by name for `0.6B` playback requests.
- A single-consumer priority queue for incoming requests, with waiting `speak_live` work preferred over waiting non-playback work.
- Requests accepted during resident-model preload, with structured status events that explain the model is still loading and when queued work begins processing.
- Structured progress and lifecycle events written to `stdout`, with human-readable diagnostics on `stderr`.

## Setup

This repository is a standard Swift package with `mlx-audio-swift` wired in as the model/runtime dependency.

```bash
swift build
```

The executable intentionally leans on the existing `mlx-audio-swift` API surface and keeps its own scope focused on process ownership, queueing, playback, and profile storage.

For real MLX-backed runs, use `xcodebuild` instead of relying on the SwiftPM command-line executable. Upstream `mlx-swift` is explicit that command-line SwiftPM does not build the Metal shader bundle, while `xcodebuild` does, and command-line tools need that bundle visible at runtime.

```bash
xcodebuild build -scheme SpeakSwiftly -destination 'platform=macOS'
```

## Usage

Use `swift run` only for fast package-local development that does not need the real MLX Metal runtime. For the real worker executable, build with `xcodebuild` and run the product from the Xcode build directory with `DYLD_FRAMEWORK_PATH` pointing at that same products directory.

```bash
DYLD_FRAMEWORK_PATH="$PWD/.derived/Build/Products/Debug" \
  "$PWD/.derived/Build/Products/Debug/SpeakSwiftly"
```

At startup the worker begins preloading the resident `0.6B` model and emits JSONL status events on `stdout`.

## Command Reference

The intended first protocol is newline-delimited JSON over standard input and output.

Example request shapes:

```json
{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"A warm, bright, feminine narrator voice.","output_path":"/tmp/bright-guide.wav"}
{"id":"req-3","op":"list_profiles"}
{"id":"req-4","op":"remove_profile","profile_name":"bright-guide"}
```

Example response and event shapes:

```json
{"event":"worker_status","stage":"warming_resident_model"}
{"id":"req-1","event":"queued","reason":"waiting_for_resident_model","queue_position":1}
{"id":"req-2","event":"queued","reason":"waiting_for_active_request","queue_position":2}
{"event":"worker_status","stage":"resident_model_ready"}
{"id":"req-1","event":"started","op":"speak_live"}
{"id":"req-1","event":"progress","stage":"buffering_audio"}
{"id":"req-1","event":"progress","stage":"playback_finished"}
{"id":"req-1","ok":true}
{"id":"req-2","ok":true,"profile_name":"bright-guide","profile_path":"/path/to/profile"}
{"id":"req-3","ok":true,"profiles":[{"profile_name":"bright-guide","created_at":"2026-04-01T12:00:00Z","voice_description":"A warm, bright, feminine narrator voice.","source_text":"Hello there"}]}
{"id":"req-9","ok":false,"code":"profile_not_found","message":"Profile 'ghost' was not found in the SpeakSwiftly profile store."}
```

Queued events are only emitted for requests that will actually wait. Once the resident model is ready, waiting `speak_live` requests are scheduled ahead of waiting non-playback work, but active work is never interrupted.

Current operation families are:

- Resident `0.6B` startup warmup and live playback with named stored profiles.
- On-demand `1.7B` VoiceDesign profile creation.
- Immutable profile storage, selection, listing, and removal.
- Playback-prioritized request handling with preload-aware queue status.
- Structured terminal success and failure responses.
- Human-friendly `stderr` logs that explain the most likely cause when something breaks.

## Repository Layout

SpeakSwiftly is intended to be the source-of-truth standalone repository for this package.

The preferred ownership model is:

- This repository remains the primary development home for `SpeakSwiftly`.
- A separate GitHub remote is created for this repository.
- The larger `speak-to-user` repository consumes `SpeakSwiftly` as a Git submodule under `packages/SpeakSwiftly`.
- Feature work happens here first, and the consuming repository updates its submodule pointer when it is ready to adopt a newer revision.

That arrangement keeps the package history, tags, and releases independent while still letting the larger repository pin an exact commit.

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
  -derivedDataPath /tmp/SpeakSwiftly-xcodebuild-dd \
  -clonedSourcePackagesDirPath /tmp/SpeakSwiftly-xcodebuild-spm
```

Opt-in real-model e2e coverage is available for the resident `0.6B` and on-demand `1.7B` paths, and the harness now builds and launches that Xcode-backed worker automatically:

```bash
SPEAKSWIFTLY_E2E=1 swift test --filter SpeakSwiftlyE2ETests
```

The real-model e2e coverage uses a shared profile convention named `testing-profile` with the voice description `A generic, warm, masculine, slow speaking voice.` Each test still runs inside its own isolated profile root, but using the same profile shape keeps downstream app e2e coverage aligned with this package.

The default shared per-user profile store now also includes a real `testing-profile` created through the worker itself, so downstream apps can reuse the same clone profile outside the isolated e2e sandbox.

If a real worker run fails with a message about `default.metallib` or `mlx-swift_Cmlx.bundle`, the executable was almost certainly launched from a plain SwiftPM build instead of an Xcode-built products directory. Rebuild with `xcodebuild`, then run the executable with `DYLD_FRAMEWORK_PATH` pointed at the matching Xcode build products directory.

## License

Apache License 2.0. See [LICENSE](LICENSE).
