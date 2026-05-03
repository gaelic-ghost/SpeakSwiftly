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

The next cleanup should preserve that shape. The problem is not that the API has
handles. The problem is that several public model and result families now
describe the same runtime concepts in different ways.

## Improvement Areas

### 1. Retained Generation Models

The retained generation surface currently exposes overlapping public models:

- `SpeakSwiftly.GenerationJob`
- `SpeakSwiftly.GeneratedBatch`
- `SpeakSwiftly.GeneratedFile`
- `SpeakSwiftly.GenerationArtifact`
- `SpeakSwiftly.BatchItem`

`GenerationJob`, `GeneratedBatch`, and `GenerationArtifact` carry similar
information about state, timestamps, failure, retention, input items, and output
artifacts. A caller can reasonably ask whether a retained batch should be
inspected through `runtime.jobs.job(id:)`, `runtime.artifacts.batch(id:)`, or
`runtime.artifacts.files()`.

Desired direction:

- make `GenerationJob` the canonical retained-work model
- treat generated files as outputs of retained jobs
- remove `GeneratedBatch` as a separate public model unless a concrete consumer
  needs a batch-specific projection
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

Desired direction:

- keep the JSONL response envelope transport-owned
- introduce typed completion payloads for Swift callers
- make terminal request observation return data shaped around the operation
  that completed
- consider a transitional public `RequestCompletion` enum if a fully generic
  typed request handle is too large for one pass

Possible first shape:

```swift
enum RequestCompletion: Sendable, Equatable {
    case speech
    case generatedFile(SpeakSwiftly.GeneratedFile)
    case generationJob(SpeakSwiftly.GenerationJob)
    case voiceProfile(SpeakSwiftly.ProfileSummary)
    case profiles([SpeakSwiftly.ProfileSummary])
    case textProfile(SpeakSwiftly.TextProfileDetails)
    case textProfiles([SpeakSwiftly.TextProfileSummary])
    case queue(SpeakSwiftly.QueueSnapshot)
    case playbackState(SpeakSwiftly.PlaybackStateSnapshot)
    case runtimeOverview(SpeakSwiftly.RuntimeOverview)
    case status(SpeakSwiftly.StatusEvent)
    case clearedQueue(count: Int)
    case cancelledRequest(id: String)
}
```

That enum is a possible planning target, not a committed final design. The
important part is that typed callers should not have to inspect a transport
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

The current `Player` surface breaks that expectation by exposing
`clearQueue(_:)` and `cancel(_:requestID:)`, which can operate on a queue that
the playback handle does not own.

Desired direction:

- keep `runtime.clearQueue(.generation)` and `runtime.clearQueue(.playback)`
- keep `runtime.cancel(.generation, requestID:)` and
  `runtime.cancel(.playback, requestID:)`
- keep `jobs.clearQueue()` and `jobs.cancel(_:)` as generation conveniences
- keep `player.clearQueue()` as a playback convenience
- keep `player.cancelRequest(_:)` only if the broad request-id behavior remains
  intentionally different from queue-scoped cancellation
- remove or deprecate `player.clearQueue(_:)` and
  `player.cancel(_:requestID:)` because they make `Player` look like a general
  queue router

Practical consequence: a caller can tell from the handle name whether an
operation affects playback, generation, or both.

Relevant files:

- [`Sources/SpeakSwiftly/API/Playback.swift`](../../Sources/SpeakSwiftly/API/Playback.swift)
- [`Sources/SpeakSwiftly/API/QueueControls.swift`](../../Sources/SpeakSwiftly/API/QueueControls.swift)
- [`Sources/SpeakSwiftly/API/GenerationJobs.swift`](../../Sources/SpeakSwiftly/API/GenerationJobs.swift)
- [`CONTRIBUTING.md`](../../CONTRIBUTING.md)

### 4. Request Operation Names

The typed Swift API currently exposes raw worker operation strings through:

- `RequestHandle.operation`
- `RequestSnapshot.operation`
- `ActiveRequest.op`
- `QueuedRequest.op`

Those names are transport truth for JSONL, but they leak worker vocabulary into
typed Swift callers. A caller who used `runtime.generate.speech(...)` should not
need to know that the worker op is `generate_speech` unless they are debugging
or bridging to JSONL.

Desired direction:

- introduce a public typed request kind, such as `SpeakSwiftly.RequestKind`
- expose typed request-kind values from request handles, snapshots, and queue
  snapshots
- keep raw JSONL `op` as a transport field where the JSONL response model still
  needs it
- decide whether raw operation strings remain available as a debug-only or
  transport-only property

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

Desired direction:

- decide whether this public cleanup pass should introduce small value types for
  the identifiers that are easiest to confuse
- prioritize `VoiceProfileName`, `TextProfileID`, `RequestID`, `ArtifactID`, and
  `GenerationJobID` if typed ids are adopted
- do not introduce typed ids only halfway; every affected method, model,
  JSONL-mapping boundary, and test should tell the same story

Practical consequence: downstream callers get compiler help when passing ids
between request observation, artifact lookup, and profile APIs.

Relevant files:

- [`Sources/SpeakSwiftly/SpeakSwiftly.swift`](../../Sources/SpeakSwiftly/SpeakSwiftly.swift)
- [`Sources/SpeakSwiftly/API/Generation.swift`](../../Sources/SpeakSwiftly/API/Generation.swift)
- [`Sources/SpeakSwiftly/API/GeneratedFiles.swift`](../../Sources/SpeakSwiftly/API/GeneratedFiles.swift)
- [`Sources/SpeakSwiftly/API/GenerationJobs.swift`](../../Sources/SpeakSwiftly/API/GenerationJobs.swift)

### 7. Voice Creation Labels

The `Voices.create(...)` overload family is mostly sound because the first label
distinguishes the creation path:

- `create(design:from:vibe:voice:outputPath:)`
- `create(systemDesign:from:vibe:voice:seed:outputPath:)`
- `create(clone:from:vibe:transcript:)`

The main naming rough spots are `voice voiceDescription`, which reads doubled at
the use site, and `systemDesign`, which says more about package authorship than
what the caller is doing.

Desired direction:

- consider `describedAs:` or `description:` for the voice prompt
- consider `seededDesign` or `packageDesign` for the system-owned design path
- keep one `create(...)` family unless the implementation proves the overloads
  are making use sites ambiguous

Practical consequence: voice-profile creation keeps its current narrow shape but
reads more naturally in Swift call sites.

Relevant files:

- [`Sources/SpeakSwiftly/API/VoiceProfiles.swift`](../../Sources/SpeakSwiftly/API/VoiceProfiles.swift)
- [`Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift`](../../Sources/SpeakSwiftly/Generation/VoiceProfileOperations.swift)

## Planning Sequence

### Phase 1: Low-Risk Boundary Cleanup

Clean up public controls where the desired owner is already documented.

- remove or deprecate cross-queue controls from `Player`
- update README, CONTRIBUTING, DocC, and API tests to match the queue-control
  ownership model
- keep JSONL queue operation names unchanged

This phase is the smallest useful first implementation slice.

### Phase 2: Text Profile Boundary Cleanup

Make `SpeakSwiftly.Normalizer` consistently return `SpeakSwiftly` models.

- return `SpeakSwiftly.TextProfileSummary`
- return `SpeakSwiftly.TextProfileDetails`
- return `SpeakSwiftly.TextProfileStyleOption`
- keep conversion to and from `TextForSpeech` localized inside normalization
  support code
- verify downstream `SpeakSwiftlyServer` alignment before release

This phase removes model-family confusion without changing the core runtime
queue or generation model.

### Phase 3: Request Observation And Completion Shape

Separate typed Swift completion data from JSONL transport envelopes.

- design a typed request-completion model
- add a typed request-kind model or equivalent
- decide what happens to `RequestHandle.operation` and queue snapshot `op`
- update request-observation tests around terminal success and failure data
- document how Swift callers should inspect completion results

This phase may be source-breaking if the public `Success` envelope stops being
the primary terminal payload for typed callers.

### Phase 4: Retained Generation Canonical Model

Make retained generation work tell one story.

- choose the canonical retained-work model
- collapse batch-specific public output duplication where possible
- align `GeneratedFile`, `GenerationArtifact`, and `GenerationJob` terminology
- update artifact lookup and job lookup docs so callers know where to inspect
  retained output
- preserve JSONL response compatibility unless this is intentionally bundled
  into a breaking release

This phase is the largest cleanup because it touches models, storage summaries,
worker responses, README examples, and E2E assertions.

### Phase 5: Identifier And Label Polish

Only after the larger shape is settled, decide whether this release should
introduce typed identifiers and voice-creation label changes.

- add semantic id value types if the package is intentionally taking a breaking
  public API cleanup
- otherwise, document the remaining string aliases as a conscious compatibility
  choice
- polish voice-creation labels if call sites still read awkwardly after the
  larger model cleanup

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
