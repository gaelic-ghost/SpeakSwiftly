# SpeakSwiftly

A thin Swift worker executable for long-lived local speech generation around `mlx-audio-swift`.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [Command Reference](#command-reference)
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
- A single FIFO queue for incoming requests.
- Requests accepted during resident-model preload, with structured status events that explain the model is still loading and when queued work begins processing.
- Structured progress and lifecycle events written to `stdout`, with human-readable diagnostics on `stderr`.

## Setup

This repository is a standard Swift package with `mlx-audio-swift` wired in as the model/runtime dependency.

```bash
swift build
```

The executable intentionally leans on the existing `mlx-audio-swift` API surface and keeps its own scope focused on process ownership, queueing, playback, and profile storage.

## Usage

The current scaffold proves out the package, dependency wiring, test baseline, and documentation shape.

```bash
swift run
```

Today, `swift run` prints a short bootstrap message to `stderr`. The long-lived worker loop, profile store, playback path, and MLX integration are still to come.

## Command Reference

The intended first protocol is newline-delimited JSON over standard input and output.

Example request shapes:

```json
{"id":"req-1","op":"speak_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-2","op":"create_profile","profile_name":"bright-guide","text":"Hello there","voice_description":"A warm, bright, feminine narrator voice.","output_path":"/tmp/bright-guide.wav"}
{"id":"req-3","op":"remove_profile","profile_name":"bright-guide"}
```

Example response and event shapes:

```json
{"event":"status","stage":"warming_resident_model"}
{"id":"req-1","event":"queued","stage":"waiting_for_resident_model"}
{"event":"status","stage":"resident_model_ready"}
{"id":"req-1","event":"started","stage":"beginning_request"}
{"id":"req-1","event":"progress","stage":"buffering_audio"}
{"id":"req-1","event":"progress","stage":"playback_finished"}
{"id":"req-1","ok":true}
{"id":"req-2","ok":true,"profile_name":"bright-guide","profile_path":"/path/to/profile"}
```

Planned operation families for the first implementation are:

- Resident `0.6B` startup warmup and live playback with named stored profiles.
- On-demand `1.7B` VoiceDesign profile creation.
- Immutable profile storage, selection, listing, and removal.
- FIFO request handling with preload-aware queue status.
- Structured terminal success and failure responses.
- Human-friendly `stderr` logs that explain the most likely cause when something breaks.

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

## License

No license has been added yet. Until a license is chosen and committed, this repository should be treated as all rights reserved.
