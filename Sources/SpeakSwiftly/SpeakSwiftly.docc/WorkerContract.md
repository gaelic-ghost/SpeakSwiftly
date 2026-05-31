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
{"id":"req-1","op":"generate_speech","text":"Hello there"}
```

### Request Keys And Structure

For generation requests, the current worker keys are:

- `voice_profile`: omit it to use the runtime default voice profile, which falls back to `swift-signal`.
- `text_profile`: select a stored text-profile override for normalization.
- `request_context`: pass caller, purpose, source/topic, and path context for `TextForSpeech`.
- `qwen_pre_model_text_chunking`: set `true` to opt Qwen live playback into pre-model text chunking.

### RequestContext Fields

`request_context` uses the shared `TextForSpeech.RequestContext` shape with a
narrower SpeakSwiftly worker contract:

- `reqPurpose` is required. Valid values are `speech` and `audioFile`.
- Use `speech` for spoken output whether the generated audio is played locally,
  served by HTTP, or sent over LAN. Output destinations select transport; request
  purpose only describes how the text should be normalized.
- `source`, `topic`, `attributes`, `cwd`, and `repo_root` provide caller metadata and path context.
- `prefacePolicy` is optional and can override the default source/topic preface behavior.

### Removed And Deprecated Keys

Generation requests no longer accept:

- `source_format`
- `input_text_context`
- `text_format`
- `nested_source_format`

Removed request-context keys `app`, `agent`, and `project` are also rejected. These removed keys produce explicit invalid-request diagnostics instead of being ignored. Source code files already have extensions, and `TextForSpeech` detects text and source structure from request text and path context.

### Backend And Model Selection

Qwen resident model selection is part of the startup backend value:

- `qwen3_smol`, `qwen3_smol_4bit`, `qwen3_smol_5bit`, `qwen3_smol_6bit`, `qwen3_smol_8bit`, or `qwen3_smol_bf16` for the Qwen 0.6B resident model family.
- `qwen3_big`, `qwen3_big_4bit`, `qwen3_big_5bit`, `qwen3_big_6bit`, `qwen3_big_8bit`, or `qwen3_big_bf16` for the Qwen 1.7B resident model family.

### Qwen-Specific Features

- `qwen_pre_model_text_chunking: true` opts Qwen live playback into pre-model text chunking.
- When omitted, Qwen live playback remains single-pass.
- Prepared Qwen conditioning is stored per resident model repo so a profile can lazily accumulate conditioning for each selected Qwen model.
- Rerolling a profile regenerates every existing prepared Qwen conditioning artifact for that profile, plus the currently selected Qwen backend when applicable.

### Compatibility Aliases

Older generation-request aliases such as `profile_name` and `text_profile_id` are still accepted for compatibility.

Representative operations include:

- `generate_speech` for live playback work.
- `generate_audio_file` for retained file output.
- `generate_batch` for grouped retained artifacts.
- `create_voice_profile_from_description`, `create_voice_profile_from_audio`, `list_voice_profiles`, and related voice-management operations.
- `get_status`, `get_default_voice_profile`, `set_default_voice_profile`, `reload_models`, and `unload_models` for runtime control.
- `get_runtime_overview` for one service-health snapshot that includes resident state, queue state, playback telemetry, and storage paths.
- `list_generation_queue`, `clear_generation_queue`, and `cancel_generation` for generation-queue inspection and control.
- `list_playback_queue`, `clear_playback_queue`, and `cancel_playback` for playback-queue inspection and control.

The broad compatibility operations `clear_queue` and `cancel_request` still exist for hosts that intentionally want to affect any queued work, but new operators should prefer the queue-specific operations when the target queue is known.

The JSONL retained-output reads `get_generated_file`, `list_generated_files`, `get_generated_batch`, and `list_generated_batches` are transport compatibility operations. Native Swift callers should use `runtime.artifact(id:)`, `runtime.artifacts()`, `runtime.artifacts.list()`, `runtime.jobs.job(id:)`, and `runtime.jobs.list()` instead.

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

`get_runtime_overview` returns a `runtime_overview.storage` object for parent processes that need to verify which persisted state they are supervising. The storage snapshot reports the resolved state root, profile-store root, persisted configuration path, text-profile archive path, generated-file root, and generation-job root. By default, those paths live under the platform Application Support directory; `stateRootURL`, `--state-root`, and `SPEAKSWIFTLY_STATE_ROOT` intentionally move the whole storage family together. `SPEAKSWIFTLY_PROFILE_ROOT` remains accepted only as a deprecated compatibility alias for older hosts.

`upsert_system_voice_profile_from_description` is a development-time resource authoring operation. Start `SpeakSwiftlyTool` with `--system-profile-resource-root PATH` before using it; the tool inserts or updates the generated system profile under `PATH/profiles/` so the directory can be bundled with the `SpeakSwiftly` target. In this resource-authoring mode, `SpeakSwiftlyTool` starts with resident playback models unloaded and prepared Qwen conditioning remains lazy. Runtime startup seeds bundled system profiles from the package resource bundle into the writable profile store. Without `--system-profile-resource-root`, system-profile upserts are rejected instead of installing package-owned profiles into ordinary runtime state.

Resource authoring may leave `.profile-store.lock` under `PATH/profiles/`. The
lock coordinates profile-store writers and is not part of the generated profile
payload. Do not commit it with bundled system profiles; remove it only after the
authoring process exits and no SpeakSwiftly process is using that profile root.

## Choose Between Swift And JSONL

Use the typed Swift runtime when you want a native library surface, direct async streams, and focused concern handles like ``SpeakSwiftly/Runtime/generate`` or ``SpeakSwiftly/Runtime/playback``.

Use the worker contract when your host process is not Swift-native, when you want a narrow process boundary, or when you want to supervise the runtime as an external executable.
