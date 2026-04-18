# SpeakSwiftly

Local text-to-speech for Swift apps and local toolchains, with a typed Swift API and a long-lived JSONL worker executable.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [API Notes](#api-notes)
- [Development](#development)
- [Verification](#verification)
- [License](#license)

## Overview

SpeakSwiftly ships two public surfaces from one Swift package:

- `SpeakSwiftly`, an importable Swift library for apps and tools that want a typed runtime
- `SpeakSwiftlyTool`, a long-lived worker executable that speaks newline-delimited JSON over `stdin` and `stdout`

That split keeps Swift callers on a readable library surface while still giving non-Swift hosts a stable process boundary.

### Motivation

This repository exists to make local TTS ownership straightforward. The package is meant to be easy to embed in Swift code, easy to drive from another process, and explicit about runtime state, queueing, and stored voice resources.

SpeakSwiftly currently includes:

- a typed runtime rooted at `SpeakSwiftly.liftoff(...)`
- a JSONL worker surface for non-Swift hosts
- stored voice profiles and text-normalization profiles
- resident backend switching between `qwen3`, `chatterbox_turbo`, and `marvis`
- resident model unload and reload controls
- retained generated-file and generated-batch artifacts

For contributor-facing architecture notes, repository workflow, runtime behavior details, and extended verification paths, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Setup

SpeakSwiftly is a standard Swift package with two direct dependencies:

- [`TextForSpeech`](https://github.com/gaelic-ghost/TextForSpeech)
- [`mlx-audio-swift`](https://github.com/gaelic-ghost/mlx-audio-swift)

The package manifest currently declares:

- `macOS 15+`
- `iOS 17+`

That platform widening is library-first. The typed `SpeakSwiftly` library now
enters the package graph for both platforms, while the long-lived worker and the
release-grade MLX verification flow are still maintained as macOS-first
surfaces.

Library consumers can add the package from GitHub:

```swift
    .package(url: "https://github.com/gaelic-ghost/SpeakSwiftly.git", from: "3.0.0")
```

Then add `SpeakSwiftly` to the target that will own the runtime.

`SpeakSwiftly` also carries a vendored `mlx-swift_Cmlx.bundle` resource so linked consumers can resolve the packaged MLX shader bundle and bundled `default.metallib` without digging through DerivedData.

For package-local validation:

```bash
swift build
```

The current `mlx-audio-swift` `69.2.0` fork pin restores the ordinary SwiftPM
build and test path. If a future toolchain regression brings back the old
`EnglishG2P.swift` parser failure, use the documented fallback lane in
[CONTRIBUTING.md](CONTRIBUTING.md) instead of repeatedly retrying the same
plain `swift build` / `swift test` commands.

For real MLX-backed worker runs, publish the Xcode-backed runtime first:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
```

That publishes stable runtime launchers under `.local/xcode/current-debug` and `.local/xcode/current-release`.

## Usage

### Typed Swift Runtime

```swift
import SpeakSwiftly
import TextForSpeech

let runtime = await SpeakSwiftly.liftoff()
await runtime.start()

let handle = await runtime.generate.speech(
    text: "Hello there.",
    with: "default-femme"
)

for try await event in handle.events {
    print(event)
}
```

When the input is source code rather than prose with embedded snippets, pass `sourceFormat`:

```swift
let sourceHandle = await runtime.generate.speech(
    text: "struct WorkerRuntime { let sampleRate: Int }",
    with: "default-femme",
    sourceFormat: .swift
)
```

The runtime is organized around stored concern handles that callers can keep and reuse:

- `runtime.generate`
- `runtime.player`
- `runtime.voices`
- `runtime.normalizer`
- `runtime.jobs`
- `runtime.artifacts`

`runtime.normalizer.profiles` includes replacement-rule inspection and bulk-clear helpers, so hosts can inspect or reset the active or stored text-profile rules without dropping down to raw JSONL.

When callers need a standalone text normalizer, `SpeakSwiftly.Normalizer(...)` throws if the persisted text-profile archive cannot be loaded or decoded. The worker runtime still uses a best-effort recovery path so `SpeakSwiftly.liftoff()` can continue starting in operator-facing environments.

Runtime preferences have a matching typed surface:

```swift
import SpeakSwiftly

let configuration = SpeakSwiftly.Configuration(
    speechBackend: .qwen3,
    qwenConditioningStrategy: .preparedConditioning
)
try configuration.save(to: URL(fileURLWithPath: "/tmp/speakswiftly-configuration.json"))

let runtime = await SpeakSwiftly.liftoff(configuration: configuration)
```

For Qwen generation, `qwenConditioningStrategy` controls whether the runtime keeps using raw `refAudio` and `refText` on each request or persists reusable prepared conditioning on the voice profile. The default configuration now uses `.preparedConditioning`, and legacy serialized `qwen3_custom_voice` backend values are normalized onto `qwen3` during load.

`chatterbox_turbo` uses the resident 8-bit Chatterbox Turbo model, is currently English-only, and reuses the stored profile reference audio when one is available. When no profile-specific clone audio is needed, the resident model falls back to Chatterbox Turbo's built-in default conditioning. For live playback, SpeakSwiftly now segments normalized text into speakable chunks up front and synthesizes those chunks sequentially, so Chatterbox can start feeding completed audio into playback without waiting for one full-request waveform.

If a host needs the packaged MLX bundle or metallib path directly, use the support-resource surface:

```swift
let mlxBundleURL = try SpeakSwiftly.SupportResources.mlxBundleURL()
let defaultMetallibURL = try SpeakSwiftly.SupportResources.defaultMetallibURL()
```

### Worker Executable

Launch the published runtime through the stable launcher:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
"$PWD/.local/xcode/current-debug/run-speakswiftly"
```

At startup the worker begins warming the resident backend and emits JSONL status events on `stdout`.

### Consumer Test Harness

The package also ships a small executable consumer harness, `SpeakSwiftlyTesting`, for package-level smoke checks:

```bash
swift run SpeakSwiftlyTesting resources
swift run SpeakSwiftlyTesting status
swift run SpeakSwiftlyTesting smoke
```

`resources` prints the packaged bundle and metallib paths, `status` constructs the typed runtime and prints the first terminal status payload it sees, and `smoke` runs both checks in sequence.

## API Notes

The package publishes:

- `SpeakSwiftly` as the typed Swift runtime library
- `SpeakSwiftlyTool` as the worker executable product
- `SpeakSwiftlyTesting` as the package-local smoke-test harness

Key typed runtime entry points include:

- `runtime.generate.speech(text:with:textProfileName:textContext:sourceFormat:)`
- `runtime.generate.audio(text:with:textProfileName:textContext:sourceFormat:)`
- `runtime.generate.batch(_:with:)`
- `runtime.voices.create(design named:from:vibe:voice:outputPath:)`
- `runtime.voices.create(clone named:from:vibe:transcript:)`
- `runtime.voices.list()`
- `runtime.voices.rename(_:to:)`
- `runtime.voices.reroll(_:)`
- `runtime.voices.delete(named:)`
- `runtime.player.list()`
- `runtime.player.pause()`
- `runtime.player.resume()`
- `runtime.player.state()`
- `runtime.player.clearQueue()`
- `runtime.player.cancelRequest(_:)`
- `runtime.jobs.expire(id:)`
- `runtime.jobs.generationQueue()`
- `runtime.jobs.job(id:)`
- `runtime.jobs.list()`
- `runtime.artifacts.file(id:)`
- `runtime.artifacts.files()`
- `runtime.artifacts.batch(id:)`
- `runtime.artifacts.batches()`
- `SpeakSwiftly.SupportResources.bundle`
- `SpeakSwiftly.SupportResources.mlxBundleURL()`
- `SpeakSwiftly.SupportResources.defaultMetallibURL()`
- `runtime.status()`
- `runtime.switchSpeechBackend(to:)`
- `runtime.reloadModels()`
- `runtime.unloadModels()`

Resident runtime controls currently map like this:

| Typed Swift API | JSONL `op` | Notes |
| --- | --- | --- |
| `status()` | `"get_status"` | Returns the current `stage`, `resident_state`, and `speech_backend`. |
| `switchSpeechBackend(to:)` | `"set_speech_backend"` | Requires a `"speech_backend"` field on the JSONL request. |
| `reloadModels()` | `"reload_models"` | Re-warms the currently selected resident backend. |
| `unloadModels()` | `"unload_models"` | Drops resident models from memory and parks later resident-dependent generation until residency returns. |

For the full JSONL worker contract, request and event examples, naming rules, and queue semantics, see:

- [WorkerContract DocC article](Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Development

Use this repository as the source-of-truth development home for SpeakSwiftly. Keep the README focused on product and usage information, and keep contributor-facing architecture notes, repository workflow, and deep operational guidance in [CONTRIBUTING.md](CONTRIBUTING.md).

For package-focused development, prefer:

```bash
swift build
swift test
```

For formatter, lint, maintainer workflow, published runtime, and deeper operator guidance, use [CONTRIBUTING.md](CONTRIBUTING.md).

## Verification

Baseline package verification:

```bash
swift build
swift test
```

For worker-backed end-to-end verification, prefer the repo-maintenance wrappers:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite quick
sh scripts/repo-maintenance/run-e2e-full.sh
```

If a future toolchain regression blocks the ordinary SwiftPM lane again, or if
you specifically need the Xcode-backed package, simulator, or real-runtime
lanes, use [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/maintainers/validation-lanes.md](docs/maintainers/validation-lanes.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
