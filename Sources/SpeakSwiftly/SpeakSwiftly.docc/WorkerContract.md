# Worker Contract

Drive the long-lived worker executable through newline-delimited JSON when the typed Swift API is not the integration surface you want.

## Overview

SpeakSwiftly ships two public surfaces from the same package:

- The typed Swift runtime in ``SpeakSwiftly``.
- The JSONL worker executable product, `SpeakSwiftlyTool`.

The worker exists for hosts that want a simple process boundary instead of linking directly against the Swift library. Requests are written to standard input as one JSON object per line, and responses and runtime events are emitted on standard output using the same newline-delimited JSON shape.

## Start The Worker

Use the published runtime launcher when running the real worker locally:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
"$PWD/.local/xcode/current-debug/run-speakswiftly"
```

At startup the worker may emit status events while the resident backend warms.

## Send Requests

Every request includes an `id` and an `op`:

```json
{"id":"req-1","op":"generate_speech","text":"Hello there","profile_name":"default-femme"}
```

Representative operations include:

- `generate_speech` for live playback work.
- `generate_audio_file` for retained file output.
- `generate_batch` for grouped retained artifacts.
- `create_voice_profile`, `list_voice_profiles`, and related voice-management operations.
- `get_status`, `reload_models`, and `unload_models` for runtime control.

## Read Events And Results

The worker emits both status events and request-scoped events. For example:

```json
{"event":"worker_status","stage":"warming_resident_model","resident_state":"warming","speech_backend":"qwen3"}
{"id":"req-1","event":"queued","reason":"waiting_for_resident_models","queue_position":1}
{"id":"req-1","ok":true}
```

Status events describe the shared runtime. Request-scoped events and terminal payloads describe one submitted operation.

## Choose Between Swift And JSONL

Use the typed Swift runtime when you want a native library surface, direct async streams, and focused concern handles like ``SpeakSwiftly/Runtime/generate`` or ``SpeakSwiftly/Runtime/player``.

Use the worker contract when your host process is not Swift-native, when you want a narrow process boundary, or when you want to supervise the runtime as an external executable.
