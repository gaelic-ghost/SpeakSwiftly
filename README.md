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
- File-path-based audio exchange instead of large base64 payloads.
- A resident `Qwen3-TTS 0.6B` path that pre-warms on startup and stays alive for streaming cloned playback.
- An on-demand `Qwen3 VoiceDesign 1.7B` path for audio-file generation that loads only when needed and unloads after the request finishes.
- Structured progress events written to `stdout` during streaming generation, with human-readable diagnostics on `stderr`.

## Setup

This repository is a standard Swift package.

```bash
swift build
```

The future worker will also depend on a local or pinned `mlx-audio-swift` integration once that package wiring is added.

## Usage

The current scaffold only proves out the package, test baseline, and documentation shape.

```bash
swift run
```

Today, `swift run` prints a short bootstrap message to `stderr`. The long-lived worker loop and MLX integration are still to come.

## Command Reference

The intended first protocol is newline-delimited JSON over standard input and output.

Request shape:

```json
{"id":"req-1","op":"speak_stream","text":"Hello there","profile":"default","output_path":"/tmp/out.wav"}
```

Response and event shape:

```json
{"id":"req-1","event":"progress","stage":"warming_resident_model"}
{"id":"req-1","event":"progress","stage":"streaming_audio","written_frames":4096}
{"id":"req-1","ok":true,"output_path":"/tmp/out.wav"}
```

Planned operation families for the first implementation are:

- Resident `0.6B` startup warmup and streaming cloned playback.
- On-demand `1.7B` VoiceDesign file generation.
- Structured terminal success and failure responses.
- Human-friendly `stderr` logs that explain the most likely cause when something breaks.

## Development

Keep the package small and concrete.

- Prefer direct data flow over helper abstractions.
- Keep the executable as the boundary instead of inventing extra internal service layers.
- Treat `stdin` and `stdout` as the worker contract and `stderr` as operator-facing logging.
- Add new packages only when they clearly simplify the code. Extra dependencies and architecture layers are often unnecessary here and should get extra scrutiny before and after they are introduced.

## Verification

Use the package baseline checks after each meaningful change.

```bash
swift build
swift test
```

## License

No license has been added yet. Until a license is chosen and committed, this repository should be treated as all rights reserved.
