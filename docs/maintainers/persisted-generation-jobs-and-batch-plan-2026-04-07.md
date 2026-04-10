# Persisted Generation Jobs And Batch Plan

Date: 2026-04-07

## Why This Exists

This is a durable building-block change, not a local generated-file tweak.

The near-term use cases it unlocks are already visible:

- callers should be able to submit file-generation work and reconnect later without keeping one stdio session attached
- callers should be able to inspect whether generation is queued, running, completed, failed, or expired
- the repository should be able to add batch-oriented generation later without renaming core identifiers or moving ownership again

The simpler extension path considered first was:

- keep `generate_audio_file` as an immediate request/response operation
- keep using the request id as the one durable identifier
- keep the current generated-file store as the only persisted state

That path is no longer enough.

It removes no current design pressure:

- there is still no persisted job state to reconnect to
- long-running file generation still assumes the caller stays attached to one live request stream
- batch output would force a second identifier reset because one request can eventually produce more than one artifact

So the right next step is not a whole new service. It is an explicit persisted job model that still sits inside the current worker-owned generation surface.

## Current State

Today `SpeakSwiftly` has:

- a worker request surface for `generate_audio_file`
- a generated-file store with persisted artifact metadata and WAV output
- read operations for `generated_file` and `generated_files`

Today it does **not** have:

- a persisted generation job record
- reconnectable inspection for in-flight work
- a durable distinction between a job and an output artifact
- a batch-aware identifier model

Current README behavior is intentionally simpler:

- the request id is currently treated as the artifact id for the first saved file
- `generated_file` fetches one stored artifact
- `generated_files` lists stored artifacts

That is a good first managed-artifact model, but it is not the final async-job model.

## Core Decision

The durable identifier model should be:

- `jobID`: the stable identifier for one generation job
- `artifactID`: the stable identifier for one saved output artifact

That means the request id should become the durable `jobID`, not the durable artifact id.

Within the generation layer for this milestone, the persisted execution model should explicitly support two job kinds:

- `file job`: one job that produces one saved file
- `batch job`: one job that produces many saved files

This is the most important contract choice in the whole milestone.

It keeps single-file generation easy to reason about:

- one file job
- one artifact

and it composes cleanly into later batch generation:

- one batch job
- many artifacts

The alternative considered first was keeping one id for both concepts. That would feel simpler today, but it would force either duplicate fake ids or a breaking rename once batch output lands. That path should be rejected now while the surface is still small.

## Ownership Model

This milestone should stay inside the current worker and generation ownership boundaries.

The intended ownership split is:

- `GeneratedFileStore` owns persisted artifact files and artifact metadata
- a new generation-job store owns persisted job metadata and job state transitions
- generation operations create and update job records while they create artifacts
- worker protocol operations expose job submission and inspection

This should **not** introduce:

- a separate daemon
- a new top-level job-service subsystem
- a subscription or MCP-only architecture
- a second queue implementation distinct from the current worker-owned generation flow

Those may become justified later, but this pass should only widen the current model enough to make reconnectable async generation real.

## Proposed Data Model

### Generation Job

Persist one record per generation request with fields along these lines:

- `version`
- `jobID`
- `jobKind`
- `createdAt`
- `updatedAt`
- `requestedByRequestID`
- `op`
- `profileName`
- `textProfileName`
- `speechBackend`
- `state`
- `text`
- `error`
- `artifacts`
- `retention`

`state` should be an explicit enum with at least:

- `queued`
- `running`
- `completed`
- `failed`
- `expired`

The stored record should also leave room for progress-like details without inventing fake percentages:

- `startedAt`
- `completedAt`
- `failedAt`
- `expiresAt`

`jobKind` should be explicit from the start:

- `file`
- `batch`

### Generation Artifact

Artifacts should stay persisted separately from job state, but job records should reference them explicitly.

Each artifact reference should describe:

- `artifactID`
- `kind`
- `createdAt`
- `filePath`
- `sampleRate`
- `profileName`
- `textProfileName`

For the current implementation, `kind` can remain small:

- `audio_wav`

That leaves room for later sidecar outputs without redesigning the job record.

### Relationship

The intended relationship is:

- one job can own zero, one, or many artifacts
- artifacts can be listed independently
- job reads should include artifact references instead of forcing callers to perform a second blind lookup

Zero artifacts matters because failed and expired jobs must still be inspectable.

## Worker Contract Direction

The worker contract should widen intentionally, but only enough to make persisted async generation inspectable and reconnectable.

### Near-Term Worker Operations

The next worker operations should be:

- `generate_audio_file`
  submit a file job and return a durable `jobID`
- `generation_job`
  fetch one persisted job by `jobID`
- `generation_jobs`
  list known jobs with compact summaries

The current artifact reads should remain:

- `generated_file`
- `generated_files`

That gives a clean split:

- jobs answer "what happened to the request?"
- artifacts answer "what saved output exists?"

### Response Shape Direction

`generate_audio_file` should stop implying that completion is tied to one still-open stream.

The submission response should be shaped around the job:

- immediate `ok`
- `job`
- optionally `generated_file` only when the file is already completed before the response is emitted

The simpler alternative considered first was keeping `generate_audio_file` as a fully immediate completed response and layering reconnect semantics somewhere else later. That path should be rejected because it would preserve two mental models for the same operation.

## Retention And Expiry

Retention rules need to be explicit before batch output exists.

The baseline rule should be:

- completed jobs keep their job record and artifact references until expiry
- failed jobs keep their job record even if they have no artifacts
- expired jobs retain enough metadata to explain what existed and why it is gone

The expiry model should distinguish:

- job-record expiry
- artifact-file expiry

The simplest durable starting point is:

- artifact files and completed job records expire together under one retention policy
- failed job records can outlive missing artifacts because they may never have produced any

That keeps ownership easy to reason about and avoids orphaned file cleanup semantics on day one.

## Batch Shape

The generation-job model should be explicit and boring:

- file jobs exist
- batch jobs exist
- batch means many files

The intended naming split for generation work should be:

- `job`: one persisted execution record
- `file job`: one job that creates one file artifact
- `batch job`: one job that creates many file artifacts
- `batch`: the caller-facing multi-file unit represented by a batch job

The intended direction is:

- one file submission creates one file job
- one future batch submission creates one batch job
- a batch job records batch metadata and can own many artifact references
- later reads should expose `generated_batch(id:)` and `generated_batches()` as first-class batch surfaces

So "batch" should not be treated as a vague synonym for "job." In this milestone it is the caller-facing name for the many-files generation shape, and it is backed by a batch job in the persisted generation model.

The model should be:

- single-file generation:
  one file job, one artifact
- batch generation:
  one batch job, many artifacts

This is why `jobID` and `artifactID` must separate now, and why file-job and batch-job naming should stay explicit.

## State Transition Rules

The intended state flow should be explicit and boring:

- `queued` when accepted and persisted but not started
- `running` when generation begins
- `completed` when all intended artifacts are safely persisted
- `failed` when the job cannot finish successfully
- `expired` when retention cleanup removes artifacts or otherwise retires the job

Important invariant:

- a job should not become `completed` until artifact metadata and files are both durably written

Important cleanup rule:

- expiry should be modeled as an intentional state transition, not silent disappearance

## Near-Term Implementation Sequence

The first implementation pass should be:

1. Add persisted generation-job models and store types with explicit `jobKind`.
2. Make `generate_audio_file` create a durable file-job record before generation starts.
3. Update generation operations to transition the file job through `queued` -> `running` -> `completed` or `failed`.
4. Store artifact references on the completed file job record.
5. Add worker read operations for one job and many jobs.
6. Keep the current artifact reads intact.
7. Update README and roadmap wording so request id no longer claims to be the artifact id and batch jobs remain reserved for the many-files shape.

That sequence deliberately avoids:

- batch submission APIs
- cross-process notifications
- live subscriptions
- splitting the worker into a separate job service

## Concrete Recommendation

The next implementation work should treat Milestone 19 as:

- a persisted generation-job layer added underneath the current generated-file feature
- a durable `jobID` / `artifactID` split
- reconnectable worker inspection for job state
- no new service boundary yet

That gives `SpeakSwiftly` one explicit direction that composes from today's single-file generation into later batch generation without another ownership or naming reset.
