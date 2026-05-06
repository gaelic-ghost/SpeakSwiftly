# SpeakSwiftlyTool Public API Adapter Plan

This note records the settled direction for moving the bundled executable
surface out of the core library runtime and into the `SpeakSwiftlyTool` target.

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
permanent junk drawers. After the tool migration is stable, redistribute
members into `Generate`, `Playback`, `Voices`, `Normalizer`, `Jobs`,
`Artifacts`, or `Runtime` when the ownership becomes obvious.

## Target Shape

The runtime executable should continue to start as a newline-delimited JSON
worker when launched with today's `SpeakSwiftlyTool` command path. Existing
runtime publishing, launch wrappers, E2E tests, and external JSONL hosts should
not need a command-line mode change for the first migration.

Inside the executable, the flow should become:

1. `SpeakSwiftlyTool` reads one JSON object per line from stdin.
2. `SpeakSwiftlyTool` decodes the JSONL worker operation into a tool-owned
   command value.
3. `SpeakSwiftlyTool` calls the public `SpeakSwiftly` API through a runtime and
   its concern handles.
4. `SpeakSwiftlyTool` awaits request completions or subscribes to runtime and
   request update streams as needed.
5. `SpeakSwiftlyTool` maps typed Swift results back to the existing JSONL
   worker response contract.
6. `SpeakSwiftlyTool` writes JSONL responses and logs to stdout and stderr.

The core library should no longer expose or require `accept(line:)` as the
primary worker ingestion path.

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

Likely gaps to fill during migration:

- Tool-owned request IDs. Public handle methods currently generate request IDs
  internally, while JSONL callers provide explicit IDs that must be preserved in
  responses. Add a `Tool` or `Dev` scoped way to submit with an explicit
  external request ID instead of keeping the internal `WorkerRequest` path.
- Runtime control snapshots and configuration mutations. Some JSONL operations
  such as default voice profile reads/writes, backend switching, model reload,
  and model unload may need clearer typed API homes.
- Completion-to-JSON response mapping. Public completion models should stay
  typed; the JSON envelope shape belongs in `SpeakSwiftlyTool`.
- Structured logs and worker status events. The runtime may continue to expose
  typed events, but JSON encoding and stderr formatting should be tool-owned.

## Operation Inventory

This inventory is the migration checklist for moving JSONL request handling into
`SpeakSwiftlyTool`. `Existing` means the operation already has a public typed API
that represents the same behavior, though the tool may still need an explicit
request-ID variant to preserve the JSONL contract. `Tool gap` means the behavior
is real and should be exposed through `SpeakSwiftly.Tool` before the executable
can leave `Runtime.accept(line:)` behind cleanly. `Dev gap` means the behavior is
diagnostic or maintainer-facing enough that `SpeakSwiftly.Dev` is the better
temporary staging home.

### Generation and Artifacts

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `generate_speech` | `.queueSpeech(..., jobType: .live)` | `runtime.generate.speech(...)` | Existing; needs explicit request-ID access and JSONL decoding in tool |
| `generate_audio_file` | `.queueSpeech(..., jobType: .file)` | `runtime.generate.audio(...)` | Existing; needs explicit request-ID access and JSONL decoding in tool |
| `generate_batch` | `.queueBatch` | `runtime.generate.batch(...)` | Existing; needs explicit request-ID access and batch item decoding in tool |
| `get_generated_file` | `.generatedFile` | `runtime.artifact(id:)` | Existing; needs explicit request-ID access |
| `list_generated_files` | `.generatedFiles` | `runtime.artifacts.list()` | Existing; needs explicit request-ID access |
| `get_generated_batch` | `.generatedBatch` | `runtime.jobs` or `runtime.artifacts` | Tool gap; batch lookup is public as a model but not yet a handle method |
| `list_generated_batches` | `.generatedBatches` | `runtime.jobs` or `runtime.artifacts` | Tool gap; batch collection lookup is not yet public |
| `expire_generation_job` | `.expireGenerationJob` | `runtime.jobs.expire(id:)` | Existing; needs explicit request-ID access |
| `get_generation_job` | `.generationJob` | `runtime.jobs.job(id:)` | Existing; needs explicit request-ID access |
| `list_generation_jobs` | `.generationJobs` | `runtime.jobs.list()` | Existing; needs explicit request-ID access |
| `list_generation_queue` | `.listQueue(..., .generation)` | `runtime.jobs.generationQueue()` and `runtime.generate.snapshot()` | Existing; JSONL response can use the typed snapshot once encoding moves to tool |
| `clear_generation_queue` | `.clearQueue(..., .generation)` | `runtime.jobs.clearQueue()` or `runtime.clearQueue(.generation)` | Existing; needs explicit request-ID access |
| `cancel_generation` | `.cancelRequest(..., .generation)` | `runtime.jobs.cancel(_:)` or `runtime.cancel(.generation, requestID:)` | Existing; needs explicit request-ID access |

### Playback

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `list_playback_queue` | `.listQueue(..., .playback)` | `runtime.playback.snapshot()` | Existing; tool should encode the snapshot to the legacy queue payload |
| `playback_pause` | `.playback(..., .pause)` | `runtime.playback.pause()` | Existing; needs explicit request-ID access |
| `playback_resume` | `.playback(..., .resume)` | `runtime.playback.resume()` | Existing; needs explicit request-ID access |
| `get_playback_state` | `.playback(..., .state)` | `runtime.playback.snapshot()` | Existing; tool can answer from typed playback state without queueing a request |
| `clear_playback_queue` | `.clearQueue(..., .playback)` | `runtime.playback.clearQueue()` or `runtime.clearQueue(.playback)` | Existing; needs explicit request-ID access |
| `cancel_playback` | `.cancelRequest(..., .playback)` | `runtime.playback.cancelRequest(_:)` or `runtime.cancel(.playback, requestID:)` | Existing; needs explicit request-ID access |

### Voice Profiles

| JSONL `op` | Current worker request | Public API target | Migration status |
| --- | --- | --- | --- |
| `create_voice_profile_from_description` | `.createProfile(..., author: .user)` | `runtime.voices.create(design:from:vibe:voiceDescription:outputPath:)` | Existing; needs explicit request-ID access and cwd handling |
| `create_system_voice_profile_from_description` | `.createProfile(..., author: .system)` | `runtime.voices.create(builtInDesign:from:vibe:voiceDescription:seed:outputPath:)` | Existing; needs explicit request-ID access, seed decoding, and cwd handling |
| `create_voice_profile_from_audio` | `.createClone` | `runtime.voices.create(clone:from:vibe:transcript:)` | Existing; needs explicit request-ID access and cwd handling |
| `list_voice_profiles` | `.listProfiles` | `runtime.voices.list()` | Existing; needs explicit request-ID access |
| `update_voice_profile_name` | `.renameProfile` | `runtime.voices.rename(_:to:)` | Existing; needs explicit request-ID access |
| `reroll_voice_profile` | `.rerollProfile` | `runtime.voices.reroll(_:)` | Existing; needs explicit request-ID access |
| `delete_voice_profile` | `.removeProfile` | `runtime.voices.delete(named:)` | Existing; needs explicit request-ID access |

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
| `get_status` | `.status` | `runtime.snapshot()` | Existing for typed state; Tool gap for legacy status-event payload encoding |
| `get_runtime_overview` | `.overview` | `runtime.snapshot()` plus storage/profile summary APIs | Tool gap; overview is still assembled by runtime internals |
| `get_default_voice_profile` | `.defaultVoiceProfile` | `runtime.defaultVoiceProfile` | Existing |
| `set_default_voice_profile` | `.setDefaultVoiceProfile` | `runtime.setDefaultVoiceProfile(_:)` | Existing |
| `set_speech_backend` | `.switchSpeechBackend` | `runtime.switchSpeechBackend(to:)` | Existing; needs explicit request-ID access |
| `reload_models` | `.reloadModels` | `runtime.reloadModels()` | Existing; needs explicit request-ID access |
| `unload_models` | `.unloadModels` | `runtime.unloadModels()` | Existing; needs explicit request-ID access |
| `clear_queue` | `.clearQueue(..., nil)` | `runtime.clearQueue(_:)` for each queue | Tool gap; cross-queue clear should be one public tool operation so the JSONL response has one request ID and one cleared count |
| `cancel_request` | `.cancelRequest(..., nil)` | `runtime.cancel(_:requestID:)` for a specific queue | Tool gap; cross-queue cancel should remain one public tool operation so callers do not need to know the target queue |

### Decoder and Encoder Ownership

`SpeakSwiftlyTool` should move these transport-only pieces out of the library:

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

## First Implementation Moves

1. Add `SpeakSwiftly.Tool` as a public staging handle returned by
   `runtime.tool`.
2. Add request-ID-preserving `Tool` methods for the existing queueing operations
   first: generation, voice-profile generation, resident-model controls,
   playback controls, queue clear, and cancellation.
3. Add `Tool` batch and artifact lookups that are missing from the public handle
   surface only where the JSONL contract already depends on them.
4. Move JSONL raw decoding into `SpeakSwiftlyTool` after the tool can call public
   API without losing request IDs.
5. Move JSONL response encoding last, because stdout/stderr behavior is the
   externally visible worker contract.

## Migration Slices

### Slice 1: Tool Adapter Inventory

Create an operation matrix that lists every current JSONL `op`, the public API
call it should use, and any missing `Tool` or `Dev` API required to preserve the
worker contract.

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

Status: implemented in the `tool: move jsonl output encoding into tool` slice.
The runtime now publishes package-scoped typed worker-output events and can
disable its own JSONL stdout fallback. `SpeakSwiftlyTool` subscribes to that
typed output before startup, owns stdout JSONL encoding for the executable path,
and writes decode-failure responses directly from the tool.

Validation:

```bash
swift test --filter WorkerProtocolTests
swift test --filter WorkerLoggingTests
swift test --filter WorkerRuntimeControlSurfaceTests
```

### Slice 5: Publish-Lane Verification

Run the executable publishing and worker verification lanes after the adapter
path owns JSONL input and output.

Validation:

```bash
sh scripts/repo-maintenance/publish-runtime.sh --configuration Debug
sh scripts/repo-maintenance/verify-runtime.sh --configuration Debug
sh scripts/repo-maintenance/run-e2e.sh --suite quick
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
- Runtime publishing and quick E2E validation pass through the new adapter path.
