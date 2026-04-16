# SpeakSwiftly

Local text-to-speech for Swift apps and local toolchains, with a typed Swift API and a long-lived JSONL worker executable.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [API Notes](#api-notes)
- [Command Reference](#command-reference)
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
- resident backend switching between `qwen3`, `qwen3_custom_voice`, and `marvis`
- resident model unload and reload controls
- retained generated-file and generated-batch artifacts

For contributor-facing architecture notes, repository workflow, runtime behavior details, and extended verification paths, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Setup

SpeakSwiftly is a standard Swift package with two direct dependencies:

- [`TextForSpeech`](https://github.com/gaelic-ghost/TextForSpeech)
- [`mlx-audio-swift`](https://github.com/gaelic-ghost/mlx-audio-swift)

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

If that SwiftPM lane hits the current vendored `mlx-audio-swift` parser failure in
`EnglishG2P.swift`, switch to the Xcode-backed validation path in
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
    speechBackend: .qwen3CustomVoice,
    qwenConditioningStrategy: .preparedConditioning
)
try configuration.save(to: URL(fileURLWithPath: "/tmp/speakswiftly-configuration.json"))

let runtime = await SpeakSwiftly.liftoff(configuration: configuration)
```

For Qwen backends, `qwenConditioningStrategy` controls whether the runtime keeps using raw `refAudio` and `refText` on each request or persists reusable prepared conditioning on the voice profile.

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

The typed Swift API and the JSONL worker deliberately use different naming styles:

- Swift keeps Cocoa-style method names that read naturally at the call site.
- JSONL keeps snake_case, verb-first operation names.
- JSONL read-one operations use `get_*`.
- JSONL collection and queue reads use `list_*`.
- JSONL CRUD-style writes use `create_*`, `replace_*`, `update_*`, and `delete_*` where those verbs fit the real semantics.
- JSONL lifecycle and control operations keep literal verbs like `generate_*`, `set_*`, `reload_*`, `unload_*`, `pause`, `resume`, `clear_*`, `cancel_*`, `load_*`, `save_*`, and `reset_*` when the operation is not best modeled as CRUD.

Resident runtime controls currently map like this:

| Typed Swift API | JSONL `op` | Notes |
| --- | --- | --- |
| `status(id:)` | `"get_status"` | Returns the current `stage`, `resident_state`, and `speech_backend`. |
| `switchSpeechBackend(to:id:)` | `"set_speech_backend"` | Requires a `"speech_backend"` field on the JSONL request. |
| `reloadModels(id:)` | `"reload_models"` | Re-warms the currently selected resident backend. |
| `unloadModels(id:)` | `"unload_models"` | Drops resident models from memory and parks later resident-dependent generation until residency returns. |

## Command Reference

The worker protocol is newline-delimited JSON over standard input and output.

Representative request shapes:

```json
{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1f","op":"generate_audio_file","text":"Save this one for later playback.","profile_name":"default-femme"}
{"id":"req-batch","op":"generate_batch","profile_name":"default-femme","items":[{"text":"First saved file."},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs"}]}
{"id":"req-rename","op":"update_voice_profile_name","profile_name":"default-femme","new_profile_name":"guide-femme"}
{"id":"req-reroll","op":"reroll_voice_profile","profile_name":"guide-femme"}
{"id":"req-text-style","op":"get_text_profile_style"}
{"id":"req-set-text-style","op":"set_text_profile_style","text_profile_style":"compact"}
{"id":"req-status","op":"get_status"}
{"id":"req-generated-file","op":"get_generated_file","artifact_id":"req-1f-artifact-1"}
{"id":"req-generated-files","op":"list_generated_files"}
{"id":"req-switch","op":"set_speech_backend","speech_backend":"marvis"}
{"id":"req-reload","op":"reload_models"}
{"id":"req-unload","op":"unload_models"}
```

Representative response and event shapes:

```json
{"event":"worker_status","stage":"warming_resident_model","resident_state":"warming","speech_backend":"qwen3"}
{"event":"worker_status","stage":"resident_model_ready","resident_state":"ready","speech_backend":"qwen3"}
{"id":"req-unload","ok":true,"status":{"event":"worker_status","stage":"resident_models_unloaded","resident_state":"unloaded","speech_backend":"qwen3"},"speech_backend":"qwen3"}
{"id":"req-after-unload","event":"queued","reason":"waiting_for_resident_models","queue_position":1}
{"id":"req-reload","ok":true,"status":{"event":"worker_status","stage":"resident_model_ready","resident_state":"ready","speech_backend":"qwen3"},"speech_backend":"qwen3"}
```

Raw JSONL callers should send absolute filesystem paths for path fields, or include `cwd` when using relative paths. The typed Swift helpers populate caller working-directory context automatically.

For fuller wire examples, queueing behavior, and operator-facing runtime notes, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Development

Use this repository as the source-of-truth development home for SpeakSwiftly. Keep the README focused on product and usage information, and keep contributor-facing architecture notes, repository workflow, and deep operational guidance in [CONTRIBUTING.md](CONTRIBUTING.md).

For package-focused development, prefer:

```bash
sh scripts/repo-maintenance/validate-all.sh
swift build
swift test
swiftformat --lint --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

`validate-all.sh` is the shared formatting-and-guidance gate. The sample pre-commit hook runs it locally, the release script runs it before tagging work by default, and CI now calls the same script before package build and test steps.

For real runtime verification and published local worker workflows, use the scripts under `scripts/repo-maintenance/` as described in [CONTRIBUTING.md](CONTRIBUTING.md).

## Verification

Baseline package verification:

```bash
swift build
swift test
```

If the current vendored `mlx-audio-swift` parser issue blocks that SwiftPM lane,
use the Xcode-backed validation fallback documented in
[CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/maintainers/validation-lanes.md](docs/maintainers/validation-lanes.md).

Real MLX-backed runtime verification starts by publishing the Xcode-backed runtime:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
```

Extended e2e, trace-capture, and deep-trace workflows are documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
