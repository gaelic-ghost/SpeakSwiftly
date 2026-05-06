# SpeakSwiftlyTool Public API Adapter Plan

This note records the settled direction for moving the bundled executable
surface out of the core library runtime and into the `SpeakSwiftlyTool` target.
It also records the implementation state of that migration.

## Decision

`SpeakSwiftlyTool` is the JSONL CLI and bundled-executable adapter for
`SpeakSwiftly`.

The tool should consume the same typed Swift library API that package consumers
use. It should not keep a privileged path through runtime internals merely
because it lives in the same package.

The `SpeakSwiftly` library owns speech generation, playback, voice profiles,
normalization, jobs, artifacts, runtime state, and typed observation. The
`SpeakSwiftlyTool` executable owns process-boundary concerns: stdin, stdout,
stderr, JSONL request parsing, JSONL response encoding, operation-name
compatibility, worker launch arguments, and bundled-executable behavior.

## Current State

The migration is implemented on the branch that introduced this document.

- `SpeakSwiftly.Tool` is the narrow request-ID-preserving adapter surface used
  by `SpeakSwiftlyTool`.
- Raw JSONL request structs, operation-name decoding, compatibility aliases, and
  best-effort ID extraction live in the `SpeakSwiftlyTool` target.
- JSONL success and failure encoding live in the `SpeakSwiftlyTool` target.
- The runtime publishes typed worker-output events for the tool to encode.
- The runtime no longer exposes `accept(line:)` as the worker ingestion path and
  no longer owns a stdout JSONL fallback.
- Worker-contract tests attach the same tool JSONL encoder used by the
  executable instead of relying on a parallel runtime encoder.

## Namespace Rule

When the tool needs a capability that is real and useful but does not yet have
an obvious long-term public home, add it under a temporary package-facing public
namespace instead of reaching into runtime internals.

Preferred temporary homes:

- `SpeakSwiftly.Tool` for capabilities that exist primarily to support the
  bundled executable or JSONL worker contract.
- `SpeakSwiftly.Dev` for maintainer and diagnostic operations that may later
  move into a more specific public handle.

These namespaces are allowed as conscious staging areas. They should not become
permanent junk drawers. `SpeakSwiftly.Tool` is intentionally narrow in this
migration: it preserves external request IDs and worker-contract operations for
the executable. Future cleanup can redistribute members into `Generate`,
`Playback`, `Voices`, `Normalizer`, `Jobs`, `Artifacts`, or `Runtime` when the
ownership becomes obvious.

## Target Shape

The runtime executable should continue to start as a newline-delimited JSON
worker when launched with today's `SpeakSwiftlyTool` command path. Existing
runtime publishing, launch wrappers, E2E tests, and external JSONL hosts should
not need a command-line mode change for the first migration.

Inside the executable, the flow is now:

1. `SpeakSwiftlyTool` reads one JSON object per line from stdin.
2. `SpeakSwiftlyTool` decodes the JSONL worker operation into a tool-owned
   command value.
3. `SpeakSwiftlyTool` calls `SpeakSwiftly.Tool`, the narrow typed adapter
   surface returned by `runtime.tool`.
4. The runtime emits typed request and worker-output events.
5. `SpeakSwiftlyTool` maps typed Swift output events back to the existing JSONL
   worker response contract.
6. `SpeakSwiftlyTool` writes JSONL responses to stdout and structured logs to
   stderr.

The core library no longer exposes or requires `accept(line:)` as the primary
worker ingestion path.

## Boundary Rules

- Do not move raw JSONL worker operation names into public Swift handle methods.
- Do not require Swift library consumers to understand the JSONL `op` strings.
- Do not let `SpeakSwiftlyTool` call private runtime queues or stores directly
  when a typed public operation can express the same work.
- Add a public `Tool` or `Dev` method before reaching through internal runtime
  types for a tool-only need.
- Preserve the JSONL worker contract while changing the implementation path.
- Keep the typed runtime API and the JSONL worker contract documented as two
  separate integration surfaces.

## Public API Coverage

Most worker operations already map to typed handles:

| JSONL operation family | Public Swift target |
| --- | --- |
| `generate_speech`, `generate_audio_file`, `generate_batch` | `runtime.generate` |
| `list_generation_queue`, `clear_generation_queue`, `cancel_generation` | `runtime.generate`, `runtime.jobs`, or cross-queue `Runtime` controls |
| `list_playback_queue`, `clear_playback_queue`, `cancel_playback`, playback pause/resume | `runtime.playback` |
| generated-file and retained-job reads | `runtime.artifacts` and `runtime.jobs` |
| voice-profile create/list/rename/reroll/delete | `runtime.voices` |
| text-profile style, profile, replacement, and persistence operations | `runtime.normalizer` |
| request snapshots and streams | `runtime.request(id:)`, `runtime.updates(for:)`, and `runtime.synthesisUpdates(for:)` |
| generation, playback, and runtime observation | `runtime.generate`, `runtime.playback`, and runtime observation APIs |

Gaps filled during migration:

- Tool-owned request IDs. `SpeakSwiftly.Tool` now exposes request-ID-preserving
  methods so JSONL callers keep stable response IDs without using
  `Runtime.accept(line:)`.
- Runtime control snapshots and configuration mutations. The tool adapter now
  covers default voice profile reads/writes, backend switching, model reload,
  model unload, queue clearing, cancellation, status, and overview operations.
- Completion-to-JSON response mapping. Public completion models stay typed; the
  JSON envelope shape belongs to `ToolJSONLOutput`.
- Structured logs and worker status events. The runtime exposes typed output
  events; JSON stdout encoding and tool output-error reporting are tool-owned.

## Operation Inventory

This inventory records the coverage used to move JSONL request handling into
`SpeakSwiftlyTool`. The current branch covers each operation through
`SpeakSwiftly.Tool`, preserving caller-provided request IDs while leaving the
long-term typed handle names available for future redistribution.

### Generation and Artifacts

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `generate_speech` | `.queueSpeech(..., jobType: .live)` | `runtime.generate.speech(...)` | Implemented through `SpeakSwiftly.Tool.speech(...)` |
| `generate_audio_file` | `.queueSpeech(..., jobType: .file)` | `runtime.generate.audio(...)` | Implemented through `SpeakSwiftly.Tool.audio(...)` |
| `generate_batch` | `.queueBatch` | `runtime.generate.batch(...)` | Implemented through `SpeakSwiftly.Tool.batch(...)` |
| `get_generated_file` | `.generatedFile` | `runtime.artifact(id:)` | Implemented through `SpeakSwiftly.Tool.artifact(...)` |
| `list_generated_files` | `.generatedFiles` | `runtime.artifacts.list()` | Implemented through `SpeakSwiftly.Tool.artifacts(...)` |
| `get_generated_batch` | `.generatedBatch` | `runtime.jobs` or `runtime.artifacts` | Implemented through `SpeakSwiftly.Tool.generatedBatch(...)` |
| `list_generated_batches` | `.generatedBatches` | `runtime.jobs` or `runtime.artifacts` | Implemented through `SpeakSwiftly.Tool.generatedBatches(...)` |
| `expire_generation_job` | `.expireGenerationJob` | `runtime.jobs.expire(id:)` | Implemented through `SpeakSwiftly.Tool.expireGenerationJob(...)` |
| `get_generation_job` | `.generationJob` | `runtime.jobs.job(id:)` | Implemented through `SpeakSwiftly.Tool.generationJob(...)` |
| `list_generation_jobs` | `.generationJobs` | `runtime.jobs.list()` | Implemented through `SpeakSwiftly.Tool.generationJobs(...)` |
| `list_generation_queue` | `.listQueue(..., .generation)` | `runtime.jobs.generationQueue()` and `runtime.generate.snapshot()` | Implemented through `SpeakSwiftly.Tool.generationQueue(...)` |
| `clear_generation_queue` | `.clearQueue(..., .generation)` | `runtime.jobs.clearQueue()` or `runtime.clearQueue(.generation)` | Implemented through `SpeakSwiftly.Tool.clearQueue(..., queueType: .generation)` |
| `cancel_generation` | `.cancelRequest(..., .generation)` | `runtime.jobs.cancel(_:)` or `runtime.cancel(.generation, requestID:)` | Implemented through `SpeakSwiftly.Tool.cancelRequest(..., queueType: .generation)` |

### Playback

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `list_playback_queue` | `.listQueue(..., .playback)` | `runtime.playback.snapshot()` | Implemented through `SpeakSwiftly.Tool.playbackQueue(...)` |
| `playback_pause` | `.playback(..., .pause)` | `runtime.playback.pause()` | Implemented through `SpeakSwiftly.Tool.pausePlayback(...)` |
| `playback_resume` | `.playback(..., .resume)` | `runtime.playback.resume()` | Implemented through `SpeakSwiftly.Tool.resumePlayback(...)` |
| `get_playback_state` | `.playback(..., .state)` | `runtime.playback.snapshot()` | Implemented through `SpeakSwiftly.Tool.playbackState(...)` |
| `clear_playback_queue` | `.clearQueue(..., .playback)` | `runtime.playback.clearQueue()` or `runtime.clearQueue(.playback)` | Implemented through `SpeakSwiftly.Tool.clearQueue(..., queueType: .playback)` |
| `cancel_playback` | `.cancelRequest(..., .playback)` | `runtime.playback.cancelRequest(_:)` or `runtime.cancel(.playback, requestID:)` | Implemented through `SpeakSwiftly.Tool.cancelRequest(..., queueType: .playback)` |

### Voice Profiles

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `create_voice_profile_from_description` | `.createProfile(..., author: .user)` | `runtime.voices.create(design:from:vibe:voiceDescription:outputPath:)` | Implemented through `SpeakSwiftly.Tool.createVoiceProfile(design:...)` |
| `create_system_voice_profile_from_description` | `.createProfile(..., author: .system)` | `runtime.voices.create(builtInDesign:from:vibe:voiceDescription:seed:outputPath:)` | Implemented through `SpeakSwiftly.Tool.createBuiltInVoiceProfile(...)` |
| `create_voice_profile_from_audio` | `.createClone` | `runtime.voices.create(clone:from:vibe:transcript:)` | Implemented through `SpeakSwiftly.Tool.createVoiceProfile(clone:...)` |
| `list_voice_profiles` | `.listProfiles` | `runtime.voices.list()` | Implemented through `SpeakSwiftly.Tool.voiceProfiles(...)` |
| `update_voice_profile_name` | `.renameProfile` | `runtime.voices.rename(_:to:)` | Implemented through `SpeakSwiftly.Tool.renameVoiceProfile(...)` |
| `reroll_voice_profile` | `.rerollProfile` | `runtime.voices.reroll(_:)` | Implemented through `SpeakSwiftly.Tool.rerollVoiceProfile(...)` |
| `delete_voice_profile` | `.removeProfile` | `runtime.voices.delete(named:)` | Implemented through `SpeakSwiftly.Tool.deleteVoiceProfile(...)` |

### Text Normalization

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `get_active_text_profile` | `.textProfileActive` | `runtime.normalizer.profiles.getActive()` | Existing; tool response encoder must add style and persistence path fields |
| `get_text_profile` | `.textProfile` | `runtime.normalizer.profiles.get(id:)` | Existing; tool response encoder must preserve nil-on-missing behavior if that remains part of the contract |
| `list_text_profiles` | `.textProfiles` | `runtime.normalizer.profiles.list()` | Existing |
| `get_active_text_profile_style` | `.activeTextProfileStyle` | `runtime.normalizer.style.getActive()` | Existing |
| `list_text_profile_styles` | `.textProfileStyleOptions` | `runtime.normalizer.style.list()` | Existing |
| `get_effective_text_profile` | `.textProfileEffective` | `runtime.normalizer.profiles.getEffective()` | Existing |
| `get_text_profile_persistence` | `.textProfilePersistence` | `runtime.normalizer.persistence.url()` | Existing |
| `load_text_profiles` | `.loadTextProfiles` | `runtime.normalizer.persistence.load()` | Existing |
| `save_text_profiles` | `.saveTextProfiles` | `runtime.normalizer.persistence.save()` | Existing |
| `set_active_text_profile_style` | `.setActiveTextProfileStyle` | `runtime.normalizer.style.setActive(to:)` | Existing |
| `create_text_profile` | `.createTextProfile` | `runtime.normalizer.profiles.create(name:)` | Existing |
| `update_text_profile_name` | `.renameTextProfile` | `runtime.normalizer.profiles.rename(profile:to:)` | Existing |
| `set_active_text_profile` | `.setActiveTextProfile` | `runtime.normalizer.profiles.setActive(id:)` | Existing |
| `delete_text_profile` | `.deleteTextProfile` | `runtime.normalizer.profiles.delete(id:)` | Existing |
| `factory_reset_text_profiles` | `.factoryResetTextProfiles` | `runtime.normalizer.profiles.factoryReset()` | Existing |
| `reset_text_profile` | `.resetTextProfile` | `runtime.normalizer.profiles.reset(id:)` | Existing |
| `create_text_replacement` | `.addTextReplacement` | `runtime.normalizer.profiles.addReplacement(...)` | Existing |
| `replace_text_replacement` | `.replaceTextReplacement` | `runtime.normalizer.profiles.patchReplacement(...)` | Existing |
| `delete_text_replacement` | `.removeTextReplacement` | `runtime.normalizer.profiles.removeReplacement(...)` | Existing |

### Runtime and Resident Models

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `get_status` | `.status` | `runtime.snapshot()` | Implemented through `SpeakSwiftly.Tool.status(...)` |
| `get_runtime_overview` | `.overview` | `runtime.snapshot()` plus storage/profile summary APIs | Implemented through `SpeakSwiftly.Tool.overview(...)` |
| `get_default_voice_profile` | `.defaultVoiceProfile` | `runtime.defaultVoiceProfile` | Implemented through `SpeakSwiftly.Tool.defaultVoiceProfile(...)` |
| `set_default_voice_profile` | `.setDefaultVoiceProfile` | `runtime.setDefaultVoiceProfile(_:)` | Implemented through `SpeakSwiftly.Tool.setDefaultVoiceProfile(...)` |
| `set_speech_backend` | `.switchSpeechBackend` | `runtime.switchSpeechBackend(to:)` | Implemented through `SpeakSwiftly.Tool.switchSpeechBackend(...)` |
| `reload_models` | `.reloadModels` | `runtime.reloadModels()` | Implemented through `SpeakSwiftly.Tool.reloadModels(...)` |
| `unload_models` | `.unloadModels` | `runtime.unloadModels()` | Implemented through `SpeakSwiftly.Tool.unloadModels(...)` |
| `clear_queue` | `.clearQueue(..., nil)` | `runtime.clearQueue(_:)` for each queue | Implemented through `SpeakSwiftly.Tool.clearQueue(...)` |
| `cancel_request` | `.cancelRequest(..., nil)` | `runtime.cancel(_:requestID:)` for a specific queue | Implemented through `SpeakSwiftly.Tool.cancelRequest(...)` |

### Decoder and Encoder Ownership

`SpeakSwiftlyTool` now owns these transport-only pieces:

- Raw JSONL structs: `RawWorkerRequest`, `RawBatchItem`, and legacy replacement
  payload decoding.
- Operation-name decoding and aliases such as `profile_name`/`voice_profile`,
  `text_profile`/`text_profile_id`, and `batch_id`/`job_id` where they are part
  of the JSONL contract.
- Best-effort ID extraction for malformed JSONL failures.
- Success, failure, worker-log, and stdin-read-failure JSON encoding.

The library should keep typed runtime concepts that are not JSONL-specific:

- `WorkerRequest` or its replacement as the internal runtime command model while
  generation scheduling still depends on that shape.
- `RequestKind`, `RequestEvent`, `RequestState`, `RequestUpdate`,
  `RequestSnapshot`, `SynthesisEvent`, and `SynthesisUpdate`.
- Typed `Generate`, `Playback`, `Runtime`, `Voices`, `Normalizer`, `Jobs`, and
  `Artifacts` handles and their public models.

## Implementation Moves

1. Added `SpeakSwiftly.Tool` as a narrow adapter handle returned by
   `runtime.tool`.
2. Added request-ID-preserving `Tool` methods for generation, artifacts, jobs,
   voice profiles, text profiles, resident-model controls, playback controls,
   queue clear, and cancellation.
3. Moved JSONL raw decoding into `SpeakSwiftlyTool`.
4. Moved JSONL response encoding into `SpeakSwiftlyTool`.
5. Removed the runtime-owned stdout JSONL fallback.

## Migration Slices

### Slice 1: Tool Adapter Inventory

Create an operation matrix that lists every current JSONL `op`, the public API
call it should use, and any missing `Tool` or `Dev` API required to preserve the
worker contract.

Status: implemented in the `docs: plan tool public api adapter` slice. The
operation inventory above remains the branch-local map between JSONL operations,
typed public targets, and the adapter methods used by `SpeakSwiftlyTool`.

Validation:

```bash
swift test --filter WorkerProtocolTests
swift test --filter LibrarySurfaceTests
```

### Slice 2: Public Tool Namespace

Add `SpeakSwiftly.Tool` and/or `SpeakSwiftly.Dev` as small public namespaces for
the migration gaps. Start with explicit request-ID submission and runtime
control operations that do not fit existing concern handles yet.

Keep the namespace narrow and documented as an adapter staging surface.

Status: implemented in the `api: add tool adapter staging surface` slice.
`SpeakSwiftly.Tool` now covers the request-ID-preserving operations the JSONL
worker contract needs. No `SpeakSwiftly.Dev` namespace was needed for this
migration.

Validation:

```bash
swift build
swift test --filter LibrarySurfaceTests
```

### Slice 3: Move JSONL Request Decoding To `SpeakSwiftlyTool`

Move raw request structs, operation-name decoding, compatibility aliases, and
best-effort ID extraction into the executable target. The decoded command should
call public API methods instead of `Runtime.accept(line:)`.

`WorkerProtocolTests` should either move to a tool-target test surface or become
tests for the tool-owned JSONL command decoder.

Status: implemented in the `api: move jsonl decoding into tool` slice. The raw
JSONL request structs and operation decoder now live under `Sources/SpeakSwiftlyTool`.
`SpeakSwiftlyTool` decodes each stdin line into `ToolRequest` and submits through
`runtime.tool`. The library runtime no longer exposes `accept(line:)`; tests that
still need JSONL-shaped inputs use a test-only helper that exercises the tool
decoder.

Validation:

```bash
swift test --filter WorkerProtocolTests
swift test --filter WorkerRuntimeQueueingTests
```

### Slice 4: Move JSONL Response Encoding To `SpeakSwiftlyTool`

Move success and failure JSON envelope encoding into the executable target.
Runtime internals should return or publish typed results; the tool should encode
those results into the worker contract.

This is the riskiest slice because stdout/stderr behavior is part of the worker
contract and release runtime publication.

Status: implemented in the `tool: move jsonl output encoding into tool` and
`tool: remove runtime jsonl fallback` slices. The runtime now publishes
package-scoped typed worker-output events only. `SpeakSwiftlyTool` subscribes to
that typed output before startup, owns stdout JSONL encoding for the executable
path, and writes decode-failure responses directly from the tool. Tests that
assert worker-contract JSONL attach the same tool output encoder to the runtime
instead of relying on runtime-owned stdout encoding.

Validation:

```bash
swift test --filter WorkerProtocolTests
swift test --filter WorkerLoggingTests
swift test --filter WorkerRuntimeControlSurfaceTests
```

### Slice 5: Publish-Lane Verification

Run the executable publishing and worker verification lanes after the adapter
path owns JSONL input and output.

Status: pending for release closeout. Run the debug publish and verify lane, then
run the full E2E wrapper before tagging or releasing.

Validation:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
sh scripts/repo-maintenance/run-e2e-full.sh
```

## Done State

This migration is complete when:

- `SpeakSwiftlyTool` owns JSONL request parsing and response encoding.
- The library runtime no longer exposes `accept(line:)` as the tool ingestion
  path.
- The tool reaches runtime behavior through public typed API only.
- Temporary `SpeakSwiftly.Tool` or `SpeakSwiftly.Dev` APIs are documented and
  intentionally narrow.
- The existing `SpeakSwiftlyTool` worker contract remains compatible for hosts
  that communicate over newline-delimited JSON.
- Runtime publishing and full E2E validation pass through the new adapter path.
