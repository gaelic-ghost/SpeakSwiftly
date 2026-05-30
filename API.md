# SpeakSwiftly API Reference

Use this reference to understand the public Swift package surface, the worker-facing JSONL contract, and the local verification paths for SpeakSwiftly.

## Table of Contents

- [Overview](#overview)
- [API Surface](#api-surface)
- [Authentication and Access](#authentication-and-access)
- [Requests and Responses](#requests-and-responses)
- [Errors](#errors)
- [Versioning and Compatibility](#versioning-and-compatibility)
- [Local Development and Verification](#local-development-and-verification)
- [Support and Ownership](#support-and-ownership)

## Overview

### Who This API Is For

This API is for Swift apps, command-line tools, agent runtimes, and local services that need on-device speech generation, playback, voice-profile management, retained audio artifacts, or text-normalized speech requests.

The main package consumer starts a `SpeakSwiftly.Runtime` through `SpeakSwiftly.liftoff(configuration:stateRootURL:)`, then works through typed concern handles such as `runtime.generate`, `runtime.playback`, `runtime.voices`, `runtime.normalizer`, `runtime.jobs`, and `runtime.artifacts`.

The package also owns an internal JSONL worker contract used by the runtime and documented in DocC for host and maintainer inspection.

### Stability Status

The Swift package API is active and source-facing. Public handles, request models, generation job models, playback snapshots, runtime snapshots, and text-profile models should be treated as the current supported package surface for this checkout.

The JSONL worker protocol is a lower-level implementation contract. Operation names are intentionally snake_case and verb-first, but app and server consumers should prefer the typed Swift API unless they are maintaining the worker boundary itself.

## API Surface

### Entry Points

Primary startup and runtime entry points:

- `SpeakSwiftly.liftoff(configuration:stateRootURL:)`
- `SpeakSwiftly.Configuration`
- `SpeakSwiftly.Runtime.shutdown()`

Runtime concern handles:

- `runtime.generate` for live speech, retained audio files, batches, and generation updates
- `runtime.playback` for playback state, pause, resume, queue clearing, and request cancellation
- `runtime.voices` for stored voice design, clone, list, rename, reroll, and delete operations
- `runtime.normalizer` for shared `TextForSpeech` style, custom-profile, persistence, and normalization operations
- `runtime.jobs` for generation queue inspection, queue clearing, cancellation, retained job lookup, and job expiry
- `runtime.artifacts` for retained generated audio artifact lookup
- `runtime.tool` for lower-level worker command access when a typed concern handle is not the right fit

The package also ships:

- `SpeakSwiftlyTool`, an executable target used for local package operations and command-plugin support
- `SpeakSwiftlyProbeTool`, an executable target for package probes and debugging
- `UpsertSystemVoiceProfile`, a SwiftPM command plugin that inserts or updates system voice-profile resources in a target package resource bundle
- `Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md`, the dense worker JSONL contract reference

### Protocols and Transports

The primary transport is an in-process Swift API. Callers import `SpeakSwiftly`, start a runtime with `await SpeakSwiftly.liftoff(...)`, and call asynchronous methods on runtime handles.

Runtime observation uses Swift concurrency streams:

- `Generate.updates()` returns an async stream of `SpeakSwiftly.GenerateUpdate` values
- `Playback.updates()` returns an async stream of `SpeakSwiftly.PlaybackUpdate` values
- `Runtime.updates()` returns an async stream of `SpeakSwiftly.RuntimeUpdate` values
- request handles expose request events and synthesis updates through asynchronous streams

The worker transport is newline-delimited JSON used internally between runtime code and worker execution. Maintainers should treat the DocC worker contract as the source of truth when changing operation names, request payloads, or response payloads.

## Authentication and Access

### Credentials

The Swift package API has no token, session, certificate, or network credential layer. Access is local to the process that imports and starts the package.

Voice generation and playback depend on local model resources and package resources. The package resource helpers expose locations for bundled system profiles, the MLX bundle, and the default Metal library when callers or maintainer tools need to inspect them.

### Permissions

Callers need normal local filesystem permissions for the runtime state root, profile store, generated artifacts, and any explicit output paths. Live playback also needs the operating system permissions and device availability required for local audio output.

The `UpsertSystemVoiceProfile` command plugin declares write access to the package directory because generated system voice profiles are durable package resources.

## Requests and Responses

### Request Shape

Common generation inputs include:

- `text`, the source text to synthesize
- `voiceProfile`, an optional `SpeakSwiftly.Name`; omitted values use the runtime default voice profile
- `textProfile`, an optional `SpeakSwiftly.TextProfileID`
- `requestContext`, optional caller metadata that can include source, topic, current directory, repository root, and attributes
- `qwenPreModelTextChunking`, an optional live-playback behavior switch for Qwen backends

Voice-profile creation accepts either a voice design request with source text, `SpeakSwiftly.Vibe`, and `voiceDescription`, or a clone request with a reference audio URL, `SpeakSwiftly.Vibe`, and an optional transcript.

Batch generation uses `[SpeakSwiftly.BatchItem]`, where each item carries text plus optional text-profile, source-format, and request-context metadata.

### Response Shape

Long-running operations return `SpeakSwiftly.RequestHandle`. A request handle carries the request ID, request kind, optional voice and request context, an event stream, a synthesis-update stream, and `completion()` for awaiting the terminal result.

State-oriented reads return snapshots:

- `GenerateSnapshot` for generation state, active generation requests, and queued generation requests
- `PlaybackSnapshot` for playback state, active playback request, queued playback requests, and buffer stability
- `RuntimeSnapshot` for runtime state, speech backend, resident model state, default voice profile, and storage

Retained file and batch generation produce `GenerationJob` and `GenerationArtifact` records.

### Data Models

Important API model families include:

- request models: `RequestHandle`, `RequestSnapshot`, `RequestEvent`, `RequestState`, `RequestCompletion`, and `SynthesisUpdate`
- generation models: `GenerateUpdate`, `GenerateSnapshot`, `GenerationJob`, `GenerationJobItem`, `GenerationArtifact`, and related job state enums
- playback models: `PlaybackUpdate`, `PlaybackSnapshot`, `PlaybackEvent`, and `PlaybackState`
- runtime models: `RuntimeUpdate`, `RuntimeSnapshot`, `RuntimeEvent`, `RuntimeState`, and `ResidentModelState`
- voice models: `SpeakSwiftly.Name`, `SpeakSwiftly.Vibe`, stored profile summaries, and profile request results
- text models: `TextProfileSummary`, `TextProfileDetails`, `TextProfileStyleOption`, `TextProfileID`, and `TextForSpeech` profile and replacement values

## Errors

### Error Shape

Request failures are reported through request events and terminal request completion. Worker-facing failures use structured error records with a code and a human-readable message.

Configuration loading can throw `SpeakSwiftly.Configuration.LoadError` when persisted configuration data is malformed or does not match the expected package schema. Resource lookup helpers can throw `SpeakSwiftly.SupportResources.LookupError` when bundled resources cannot be found.

### Common Failure Modes

- A voice profile cannot be found: check the selected `SpeakSwiftly.Name` and the runtime profile store.
- A generated artifact cannot be found: check the retained generation job ID, artifact ID, and artifact retention state.
- Live playback does not start: check playback device availability, runtime state, active request events, and whether playback is paused.
- Model resources fail to load: check the selected `SpeechBackend`, the package resource bundle, and the MLX or Metal resource path reported by the runtime.
- Text-profile operations fail: check the `TextProfileID`, stored profile state, and the `TextForSpeech` replacement shape.

## Versioning and Compatibility

### Supported Versions

This checkout builds as Swift language mode 6 with Swift tools version 6.3. The package declares a macOS 15 platform floor.

The package depends on `TextForSpeech` from `0.22.1`, `mlx-audio-swift` exact `0.100.0`, and `mlx-swift` from `0.30.6` in the current manifest.

### Breaking Changes

Breaking Swift API, worker operation, or persisted model changes should be reflected in package release notes, GitHub release tags, `README.md`, `CONTRIBUTING.md`, and the worker contract when the worker protocol changes.

For worker JSONL changes, update `Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md` in the same pass as the code so host integrations do not have to infer protocol drift from source.

## Local Development and Verification

### Runtime Configuration

Runtime startup can be shaped with `SpeakSwiftly.Configuration` and an explicit `stateRootURL`. Configuration includes speech backend selection, Qwen conditioning strategy, default voice profile, system profile resource roots, and an optional `SpeakSwiftly.Normalizer`.

When `stateRootURL` is omitted, the runtime uses the platform Application Support default. Hosts that need isolated persistent state should pass `stateRootURL` explicitly.

### Verification

Use the package commands from the repository root:

```bash
swift build
swift test
```

Use the repo-maintenance gate for the broader maintainer pass:

```bash
bash scripts/repo-maintenance/validate-all.sh
```

Use the worker contract when validating JSONL protocol changes:

```bash
open Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md
```

## Support and Ownership

Gale owns this package under `gaelic-ghost/SpeakSwiftly`. Use the repository issue tracker and the repo-local maintainer guidance in `AGENTS.md`, `CONTRIBUTING.md`, and `docs/maintainers/` when the API contract is unclear or broken.
