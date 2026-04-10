# SpeakSwiftly

A Swift speech runtime package for long-lived local text-to-speech with a typed Swift API, a JSONL worker surface, and resident-model control for local MLX-backed speech workflows.

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

SpeakSwiftly is a Swift Package Manager repository that ships both an importable library product, `SpeakSwiftlyCore`, and a worker executable, `SpeakSwiftly`. The library gives Swift callers a typed runtime surface, while the executable gives non-Swift hosts a newline-delimited JSON protocol over `stdin` and `stdout`.

### Motivation

The project exists to keep MLX-backed speech generation, playback orchestration, and profile storage in one focused Swift runtime instead of forcing each host app or service to rebuild those behaviors itself. The public surface is meant to stay direct and predictable: typed Swift entry points for library consumers, stable JSONL operations for process-boundary callers, and clear runtime status for operators who need to understand what the resident speech backend is doing.

SpeakSwiftly currently supports:

- Typed Swift runtime APIs through `SpeakSwiftlyCore`
- A long-lived JSONL worker executable for non-Swift callers
- Stored voice profiles and text-normalization profiles
- Resident backend switching between `qwen3` and `marvis`
- Resident model unload and reload controls
- Managed generated-file and generated-batch artifacts

For deeper contributor-facing architecture notes, runtime behavior details, development guidance, and full verification workflows, see [CONTRIBUTING.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/CONTRIBUTING.md).

## Setup

SpeakSwiftly is a standard Swift package that depends on:

- [`TextForSpeech`](https://github.com/gaelic-ghost/TextForSpeech.git)
- [`mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift)

Library consumers can add the package directly from GitHub:

```swift
.package(url: "https://github.com/gaelic-ghost/SpeakSwiftly.git", from: "0.9.2")
```

Then add `SpeakSwiftlyCore` to the target that will own the runtime.

`SpeakSwiftlyCore` also carries a vendored `mlx-swift_Cmlx.bundle` resource so linked consumers can resolve the packaged MLX shader bundle and bundled `default.metallib` without spelunking through DerivedData.

For package-local validation:

```bash
swift build
```

For real MLX-backed local worker runs, publish the Xcode-backed runtime first:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
```

That produces stable local runtime launchers under `.local/xcode/current-debug` and `.local/xcode/current-release`.

## Usage

### Typed Swift Runtime

```swift
import SpeakSwiftlyCore
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

When the whole input is source code rather than prose with embedded code, use `sourceFormat`:

```swift
let sourceHandle = await runtime.generate.speech(
    text: "struct WorkerRuntime { let sampleRate: Int }",
    with: "default-femme",
    sourceFormat: .swift
)
```

The typed runtime is organized around stored concern handles that callers can keep and reuse:

- `runtime.generate`
- `runtime.player`
- `runtime.voices`
- `runtime.normalizer`
- `runtime.jobs`
- `runtime.artifacts`

When callers need to construct a standalone text normalizer, `SpeakSwiftly.Normalizer(...)` now throws if the persisted text-profile archive cannot be loaded or decoded. The worker runtime still uses a best-effort recovery path for unreadable archives so `SpeakSwiftly.liftoff()` can continue starting in operator-facing environments.

Runtime preferences have a matching typed surface:

```swift
import SpeakSwiftlyCore

let configuration = SpeakSwiftly.Configuration(speechBackend: .marvis)
try configuration.save(to: URL(fileURLWithPath: "/tmp/speakswiftly-configuration.json"))

let runtime = await SpeakSwiftly.liftoff(configuration: configuration)
```

If a host needs the packaged MLX bundle or the exact metallib path, use the support-resource surface:

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

At startup the worker begins preloading the resident model and emits JSONL status events on `stdout`.

### Consumer Test Harness

The package also ships a small executable consumer harness, `SpeakSwiftlyTesting`, for package-level smoke tests:

```bash
swift run SpeakSwiftlyTesting resources
swift run SpeakSwiftlyTesting status
swift run SpeakSwiftlyTesting smoke
```

`resources` prints the packaged bundle and metallib paths, `status` constructs the typed runtime and prints the first terminal status payload it sees, and `smoke` runs both checks in sequence.

## API Notes

The package currently publishes:

- `SpeakSwiftlyCore` as the typed Swift runtime library
- `SpeakSwiftly` as the worker executable

Key typed runtime entry points include:

- `runtime.generate.speech(text:with:textProfileName:textContext:sourceFormat:)`
- `runtime.generate.audio(text:with:textProfileName:textContext:sourceFormat:)`
- `runtime.generate.batch(_:with:)`
- `runtime.voices.create(design named:from:vibe:voice:outputPath:)`
- `runtime.voices.create(clone named:from:vibe:transcript:)`
- `runtime.voices.list()`
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

The typed Swift library and the JSONL worker surface intentionally use different naming styles:

- Swift keeps Cocoa-style method names that read naturally at the call site.
- JSONL keeps snake_case, verb-first operation names.
- JSONL read-one operations use `get_*`.
- JSONL collection and queue reads use `list_*`.
- JSONL CRUD-style writes use `create_*`, `replace_*`, and `delete_*`.
- JSONL lifecycle and control operations keep literal verbs like `queue_*`, `set_*`, `reload_*`, `unload_*`, `pause`, `resume`, `clear_*`, `cancel_*`, `load_*`, `save_*`, and `reset_*` when the operation is not best modeled as CRUD.

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
{"id":"req-1","op":"queue_speech_live","text":"Hello there","profile_name":"default-femme"}
{"id":"req-1f","op":"queue_speech_file","text":"Save this one for later playback.","profile_name":"default-femme"}
{"id":"req-batch","op":"queue_speech_batch","profile_name":"default-femme","items":[{"text":"First saved file."},{"artifact_id":"custom-batch-artifact","text":"Second saved file.","text_profile_name":"logs"}]}
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

For the full wire examples, detailed event flow, and operator-facing behavior notes, see [CONTRIBUTING.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/CONTRIBUTING.md).

## Development

Use this repository as the primary development home for SpeakSwiftly. Keep the public README focused on product and usage information, and put contributor-facing architecture notes, repository workflow, and deep operational guidance in [CONTRIBUTING.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/CONTRIBUTING.md).

For package-focused development, prefer:

```bash
swift build
swift test
```

For real runtime verification and published local worker workflows, use the scripts under `scripts/repo-maintenance/` as described in [CONTRIBUTING.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/CONTRIBUTING.md).

## Verification

Baseline package verification:

```bash
swift build
swift test
```

Real MLX-backed runtime verification starts by publishing the Xcode-backed runtime:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
```

Extended e2e, trace-capture, and deep-trace workflows are documented in [CONTRIBUTING.md](https://github.com/gaelic-ghost/SpeakSwiftly/blob/main/CONTRIBUTING.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
