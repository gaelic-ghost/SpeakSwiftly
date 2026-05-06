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
