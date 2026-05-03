# Public API Surface Audit

This note records the current public API audit for the standalone `SpeakSwiftly`
Swift package. It is planning guidance for a focused simplification pass before
the package treats its typed Swift API as a stable consumer contract.

## Source Rule

Swift's API Design Guidelines put the main pressure in the right place for this
audit: clarity at the use site is more important than brevity, defaulted
parameters are usually easier to understand than method families, and public
declarations should be explainable in short documentation comments.

For `SpeakSwiftly`, that means the public API should let a caller understand
what they are submitting, observing, querying, or controlling without knowing
the JSONL worker operation names or runtime internals first.

## Current Strengths

The concern-handle shape is still the right backbone for the package:

- `runtime.generate`
- `runtime.player`
- `runtime.voices`
- `runtime.normalizer`
- `runtime.jobs`
- `runtime.artifacts`

Those handles make ownership visible. Generation submission, playback control,
voice-profile storage, text normalization, retained jobs, and retained artifacts
are easier to reason about when callers enter through the handle that owns the
job they are trying to do.

Milestone 27 preserved that shape. The cleanup kept callers on concern handles
while reducing duplicate models, transport leakage, and queue-control ambiguity.

## Improvement Areas

### 1. Retained Generation Models

The retained generation surface now treats `GenerationJob` as the canonical
Swift model for retained work:

- `SpeakSwiftly.GenerationJob`
- `SpeakSwiftly.GeneratedFile`
- `SpeakSwiftly.GenerationArtifact`
- `SpeakSwiftly.BatchItem`

`GeneratedBatch` remains only as a JSONL response compatibility projection for
the worker's `generated_batch` and `generated_batches` payloads. The public
Swift convenience query surface no longer exposes batch-specific artifact
methods; callers inspect retained batch work through `runtime.jobs.job(id:)` or
`runtime.jobs.list()`.

Desired direction:

- keep `GenerationJob` as the canonical retained-work model
- treat generated files as outputs of retained jobs
- keep `GeneratedBatch` constrained to JSONL compatibility unless a concrete
  typed Swift consumer needs a batch-specific projection
- keep `BatchItem` only if batch submission remains caller-authored at the
  typed API boundary
- make generated-artifact and generated-file terminology consistent across
  Swift names, JSONL payloads, README examples, and tests

Practical consequence: downstream code can follow one story. A retained request
creates a generation job. That job has input items, state, failure information,
and output files.

Relevant files:

- [`Sources/SpeakSwiftly/API/GenerationJobs.swift`](../../Sources/SpeakSwiftly/API/GenerationJobs.swift)
- [`Sources/SpeakSwiftly/API/GeneratedBatches.swift`](../../Sources/SpeakSwiftly/API/GeneratedBatches.swift)
- [`Sources/SpeakSwiftly/API/GeneratedFiles.swift`](../../Sources/SpeakSwiftly/API/GeneratedFiles.swift)
- [`Sources/SpeakSwiftly/Storage/GeneratedFileStore.swift`](../../Sources/SpeakSwiftly/Storage/GeneratedFileStore.swift)

### 2. Typed Completion Results

`SpeakSwiftly.Success` is useful as a JSONL response envelope, but it is too
wide for typed Swift callers. It has optional slots for generated files,
batches, jobs, voice profiles, text profiles, queues, playback state, runtime
overview, status, backend changes, cleared counts, and cancellation ids.

That forces callers to know which optional payload should be present for the
operation they submitted.

Implemented direction:

- keep the JSONL response envelope transport-owned
- introduce typed completion payloads for Swift callers through
  `SpeakSwiftly.RequestCompletion`
- make terminal request observation return data shaped around the operation
  that completed

The important part is that typed callers no longer have to inspect a transport
envelope full of unrelated optional fields.

Relevant files:

- [`Sources/SpeakSwiftly/Runtime/WorkerResponses.swift`](../../Sources/SpeakSwiftly/Runtime/WorkerResponses.swift)
- [`Sources/SpeakSwiftly/SpeakSwiftly.swift`](../../Sources/SpeakSwiftly/SpeakSwiftly.swift)
- [`Tests/SpeakSwiftlyTests/API/LibrarySurfaceTests.swift`](../../Tests/SpeakSwiftlyTests/API/LibrarySurfaceTests.swift)

### 3. Queue-Control Ownership

The intended queue-control model is already documented:

- generation-queue inspection lives under `Jobs`
- playback-queue inspection lives under `Player`
- cross-queue controls live on `Runtime`
- same-queue conveniences may live on `Jobs` and `Player`

Milestone 27 removed the cross-queue `Player.clearQueue(_:)` and
`Player.cancel(_:requestID:)` entry points, which could operate on queues the
playback handle did not own.

Implemented direction:

- keep `runtime.clearQueue(.generation)` and `runtime.clearQueue(.playback)`
- keep `runtime.cancel(.generation, requestID:)` and
  `runtime.cancel(.playback, requestID:)`
- keep `jobs.clearQueue()` and `jobs.cancel(_:)` as generation conveniences
- keep `player.clearQueue()` as a playback convenience
- keep `player.cancelRequest(_:)` for broad playback-request cancellation

Practical consequence: a caller can tell from the handle name whether an
operation affects playback, generation, or both.

Relevant files:

- [`Sources/SpeakSwiftly/API/Playback.swift`](../../Sources/SpeakSwiftly/API/Playback.swift)
- [`Sources/SpeakSwiftly/API/QueueControls.swift`](../../Sources/SpeakSwiftly/API/QueueControls.swift)
- [`Sources/SpeakSwiftly/API/GenerationJobs.swift`](../../Sources/SpeakSwiftly/API/GenerationJobs.swift)
- [`CONTRIBUTING.md`](../../CONTRIBUTING.md)

### 4. Request Operation Names

The typed Swift API now exposes `SpeakSwiftly.RequestKind` from request
handles, retained request snapshots, active queue summaries, and queued request
summaries. Raw worker operation names remain the JSONL transport truth and are
still encoded as `op` in worker envelopes and queue payloads.

This keeps Swift callers on a typed request-kind value while preserving the
wire vocabulary for process-boundary callers and logs.

Practical consequence: request observation becomes part of the Swift API instead
of a thin view over the worker protocol.

Relevant files:

- [`Sources/SpeakSwiftly/SpeakSwiftly.swift`](../../Sources/SpeakSwiftly/SpeakSwiftly.swift)
- [`Sources/SpeakSwiftly/Runtime/WorkerResponses+RuntimeOverview.swift`](../../Sources/SpeakSwiftly/Runtime/WorkerResponses+RuntimeOverview.swift)
- [`Sources/SpeakSwiftly/Runtime/WorkerProtocol.swift`](../../Sources/SpeakSwiftly/Runtime/WorkerProtocol.swift)

### 5. Text Profile Model Family

`SpeakSwiftly` defines transport wrappers:

- `SpeakSwiftly.TextProfileSummary`
- `SpeakSwiftly.TextProfileDetails`
- `SpeakSwiftly.TextProfileStyleOption`

The direct `runtime.normalizer` API now returns these `SpeakSwiftly` models
instead of `TextForSpeech.Runtime.Profiles.*` and
`TextForSpeech.Runtime.Style.Option`. This keeps Swift callers in one model
family for text-profile reads and mutations.

Desired direction:

- keep `SpeakSwiftly.Normalizer` returning `SpeakSwiftly` text-profile models
  consistently
- continue accepting `TextForSpeech.Replacement` where that is genuinely the
  shared authored replacement-rule input
- preserve JSONL compatibility for `profile_id`
- keep the source-of-truth behavior in `TextForSpeech`, but do not force every
  `SpeakSwiftly` consumer to juggle internal `TextForSpeech.Runtime` model
  names

Practical consequence: `TextForSpeech` remains the normalization engine, while
`SpeakSwiftly` owns its package-facing profile vocabulary.

Relevant files:

- [`Sources/SpeakSwiftly/API/TextNormalization.swift`](../../Sources/SpeakSwiftly/API/TextNormalization.swift)
- [`Sources/SpeakSwiftly/Normalization/TextNormalizer.swift`](../../Sources/SpeakSwiftly/Normalization/TextNormalizer.swift)
- [`docs/maintainers/slices.md`](slices.md)

### 6. Semantic Identifiers

The package currently uses `String` for several semantically different values:

- voice-profile names
- text-profile ids
- request ids
- artifact ids
- generation-job ids
- batch ids
- worker operation names

`SpeakSwiftly.Name` and `TextProfileID` document intent, but they do not prevent
accidental mixing because they are still type aliases.

Slice 5 decision: do not introduce identifier value types in Milestone 27. The
current identifiers are intentionally wire-shaped strings that pass through JSONL
requests, JSONL responses, retained manifests, request observation, and the
downstream server adapter. Wrapping only part of that surface would make the API
less consistent; wrapping all of it belongs in a dedicated follow-up with
downstream adoption planned at the same time.

Desired direction:

- leave identifier aliases and stored string ids in place for this milestone
- revisit `VoiceProfileName`, `TextProfileID`, `RequestID`, `ArtifactID`, and
  `GenerationJobID` only as a dedicated cross-surface migration
- do not introduce typed ids only halfway; every affected method, model,
  JSONL-mapping boundary, and test should tell the same story

Practical consequence: Slice 5 stays focused on labels that improve call sites
without forcing a broad JSONL and manifest migration.

Relevant files:

- [`Sources/SpeakSwiftly/SpeakSwiftly.swift`](../../Sources/SpeakSwiftly/SpeakSwiftly.swift)
- [`Sources/SpeakSwiftly/API/Generation.swift`](../../Sources/SpeakSwiftly/API/Generation.swift)
- [`Sources/SpeakSwiftly/API/GeneratedFiles.swift`](../../Sources/SpeakSwiftly/API/GeneratedFiles.swift)
- [`Sources/SpeakSwiftly/API/GenerationJobs.swift`](../../Sources/SpeakSwiftly/API/GenerationJobs.swift)

### 7. Voice Creation Labels

The `Voices.create(...)` overload family is mostly sound because the first label
distinguishes the creation path:

- `create(design:from:vibe:voiceDescription:outputPath:)`
- `create(builtInDesign:from:vibe:voiceDescription:seed:outputPath:)`
- `create(clone:from:vibe:transcript:)`

Slice 5 resolves the two roughest labels: the voice prompt now appears as
`voiceDescription:` at the use site, and package-owned seed creation now appears
as `builtInDesign:` instead of `systemDesign:`.

Desired direction:

- keep `voiceDescription:` unless callers prove the label is too verbose
- keep `builtInDesign:` unless package-owned defaults start covering non-built-in
  resources
- keep one `create(...)` family unless the implementation proves the overloads
  are making use sites ambiguous

Practical consequence: voice-profile creation keeps its current narrow shape but
reads more naturally in Swift call sites.

Relevant files:

- [`Sources/SpeakSwiftly/API/VoiceProfiles.swift`](../../Sources/SpeakSwiftly/API/VoiceProfiles.swift)
- [`Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift`](../../Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift)

## Implemented Sequence

### Phase 1: Low-Risk Boundary Cleanup

Cleaned up public controls where the desired owner was already documented.

- removed cross-queue controls from `Player`
- updated README, CONTRIBUTING, DocC, and API tests to match the queue-control
  ownership model
- kept JSONL queue operation names unchanged

This phase was the smallest useful first implementation slice.

### Phase 2: Text Profile Boundary Cleanup

Made `SpeakSwiftly.Normalizer` consistently return `SpeakSwiftly` models.

- returned `SpeakSwiftly.TextProfileSummary`
- returned `SpeakSwiftly.TextProfileDetails`
- returned `SpeakSwiftly.TextProfileStyleOption`
- kept conversion to and from `TextForSpeech` localized inside normalization
  support code
- left downstream `SpeakSwiftlyServer` alignment as separate pre-release adoption

This phase removed model-family confusion without changing the core runtime
queue or generation model.

### Phase 3: Request Observation And Completion Shape

Separated typed Swift completion data from JSONL transport envelopes.

- added `SpeakSwiftly.RequestCompletion`
- added `SpeakSwiftly.RequestKind`
- exposed `RequestHandle.kind` and queue-summary `kind` values while preserving
  JSONL `op` encoding
- updated request-observation tests around terminal success and failure data
- documented how Swift callers should inspect completion results

This phase is source-breaking: the public `Success` envelope remains the JSONL
success payload, while typed request streams now complete with
`SpeakSwiftly.RequestCompletion`.

### Phase 4: Retained Generation Canonical Model

Made retained generation work tell one story.

- chose `GenerationJob` as the canonical retained-work model
- collapsed batch-specific public output duplication where possible
- aligned `GeneratedFile`, `GenerationArtifact`, and `GenerationJob` terminology
- updated artifact lookup and job lookup docs so callers know where to inspect
  retained output
- preserved JSONL response compatibility

This phase was the largest cleanup because it touched models, storage summaries,
worker responses, README examples, and E2E assertions.

### Phase 5: Identifier And Label Polish

After the larger shape settled, the branch decided against identifier value
types for Milestone 27 and applied the voice-creation label changes.

- documented remaining string aliases as a conscious cross-surface compatibility
  choice
- changed designed voice prompts to `voiceDescription:`
- changed trusted package-owned defaults to `builtInDesign:`

## Non-Goals

- Do not replace the concern-handle API shape.
- Do not introduce a new manager, coordinator, router, or transport wrapper to
  solve naming confusion.
- Do not change JSONL operation names casually; Swift API cleanup and wire
  compatibility are related but separate decisions.
- Do not preserve legacy compatibility shims unless a downstream package needs
  an explicit migration window.
- Do not hide `TextForSpeech` where the caller is authoring a real
  `TextForSpeech` concept, such as replacement rules or input context.

## Roadmap Hooks

The actionable work is tracked in `ROADMAP.md` under:

- Milestone 13: Swift Package Distribution
- Milestone 18: Package Docs And Distribution Polish
- Milestone 26: Pre-v1 Release Hardening
- Milestone 27: Public API Surface Simplification
