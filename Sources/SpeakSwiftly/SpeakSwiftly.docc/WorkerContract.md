# Worker Contract

Drive the long-lived worker executable through newline-delimited JSON when the typed Swift API is not the integration surface you want.

## Overview

SpeakSwiftly ships two public surfaces from the same package:

- The typed Swift runtime in ``SpeakSwiftly``.
- The JSONL worker executable product, `SpeakSwiftlyTool`.

The worker exists for hosts that want a simple process boundary instead of linking directly against the Swift library. Requests are written to standard input as one JSON object per line, and responses and runtime events are emitted on standard output using the same newline-delimited JSON shape.

## Start The Worker

Use the deterministic Xcode runtime launcher when running the standalone worker locally:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
"$PWD/.local/derived-data/runtime-debug/run-speakswiftly"
```

This Xcode-backed runtime is only for the standalone executable lane. Linked Swift package consumers use the package's bundled `mlx-swift_Cmlx.bundle` resource instead.

At startup the worker may emit status events while the resident backend warms.

## Send Requests

Every request includes an `id` and an `op`:

```json
{"id":"req-1","op":"generate_speech","text":"Hello there","voice_profile":"default-femme"}
```

For generation requests, the current worker keys are `voice_profile`, `text_profile`, `input_text_context`, and `request_context`. `input_text_context.context` uses the shared `TextForSpeech.InputContext` shape, while `request_context` uses the shared `TextForSpeech.RequestContext` shape. Qwen live playback can also opt into pre-model text chunking with `qwen_pre_model_text_chunking: true`; when omitted, Qwen live playback remains single-pass. Qwen resident model selection is a startup configuration concern, and prepared Qwen conditioning is stored per resident model repo so a profile can lazily accumulate conditioning for each selected Qwen model. Older generation-request aliases such as `profile_name` and `text_profile_id` are still accepted for compatibility.

Representative operations include:

- `generate_speech` for live playback work.
- `generate_audio_file` for retained file output.
- `generate_batch` for grouped retained artifacts.
- `create_voice_profile_from_description`, `create_voice_profile_from_audio`, `list_voice_profiles`, and related voice-management operations.
- `get_status`, `reload_models`, and `unload_models` for runtime control.
- `get_runtime_overview` for one service-health snapshot that includes resident state, queue state, playback telemetry, and storage paths.
- `list_generation_queue`, `clear_generation_queue`, and `cancel_generation` for generation-queue inspection and control.
- `list_playback_queue`, `clear_playback_queue`, and `cancel_playback` for playback-queue inspection and control.

The broad compatibility operations `clear_queue` and `cancel_request` still exist for hosts that intentionally want to affect any queued work, but new operators should prefer the queue-specific operations when the target queue is known.

`list_voice_profiles` treats profile directories independently. Stray files, partial directories, and unreadable manifests are skipped so the operation can still return healthy profiles while a separate cleanup or coordination pass deals with damaged entries.

## Read Events And Results

The worker emits both status events and request-scoped events. For example:

```json
{"event":"worker_status","stage":"warming_resident_model","resident_state":"warming","speech_backend":"qwen3"}
{"id":"req-1","event":"queued","reason":"waiting_for_resident_model","queue_position":1}
{"id":"req-1","ok":true}
```

Status events describe the shared runtime. Request-scoped events and terminal payloads describe one submitted operation.
During startup warmup, queued work uses `waiting_for_resident_model`. After an explicit unload, parked work uses `waiting_for_resident_models`.

`get_runtime_overview` returns a `runtime_overview.storage` object for parent processes that need to verify which persisted state they are supervising. The storage snapshot reports the resolved state root, profile-store root, persisted configuration path, text-profile archive path, generated-file root, and generation-job root. By default, those paths live under the platform Application Support directory; `stateRootURL` and `--state-root` intentionally move the whole storage family together.

## Choose Between Swift And JSONL

Use the typed Swift runtime when you want a native library surface, direct async streams, and focused concern handles like ``SpeakSwiftly/Runtime/generate`` or ``SpeakSwiftly/Runtime/player``.

Use the worker contract when your host process is not Swift-native, when you want a narrow process boundary, or when you want to supervise the runtime as an external executable.
