# TextForSpeech Split and SpeakSwiftly Integration Plan

## Goal

Finish the `TextForSpeech` extraction as a real package split instead of leaving it as a half-moved internal subsystem.

At the end of this work:

- `TextForSpeech` is the source of truth for text normalization models, runtime state, persistence, and normalization execution.
- `SpeakSwiftly` depends on `TextForSpeech` as an external package.
- `SpeakSwiftly` consumers can manage normalization profiles through public `SpeakSwiftly` APIs.
- speech requests can select a normalization profile and input kind at request time.

## Non-negotiable behavior

The current built-in normalization rules in `SpeakSwiftly` must be preserved.

Those rules should become the always-on base normalization profile in `TextForSpeech`, not optional custom overrides that can accidentally be turned off.

The intended model is:

- base profile:
  the currently hardcoded normalization behavior that keeps the model reliable and speakable
- custom profile:
  user or app-defined additions and overrides
- effective profile:
  the merged result of `base profile + selected custom profile`

So when a request normalizes text, it should never run only a custom profile by itself. It should always run the base profile, then merge in the selected custom profile on top.

That preserves reliability while still making customization useful.

## Why this split is worth doing

This is a durable building-block change, not cleanup for its own sake.

It unlocks real near-term use cases:

- package consumers can actually manage text normalization through public APIs
- `SpeakSwiftly` consumers can customize speech output without forking the built-in normalizer
- `TextForSpeech` can become a genuinely reusable package for other apps and tools
- persistence, import/export, YAML, and hot reload can live in the text system instead of leaking into speech-worker code

The simpler path considered first was keeping `TextForSpeech` as a mostly-standalone model package while `SpeakSwiftly` continued owning the real normalization behavior. That path should be rejected now because it preserves the current failure mode: two packages exist, but only one actually matters in practice.

## Target architecture

### TextForSpeech

`TextForSpeech` should own:

- `TextForSpeech.Context`
- `TextForSpeech.Kind`
- `TextForSpeech.Replacement`
- `TextForSpeech.Profile`
- `TextForSpeechRuntime`
- the concrete text normalizer implementation
- base-profile definition and effective-profile merging
- profile persistence
- later: config adapters such as YAML and hot reload

### SpeakSwiftly

`SpeakSwiftly` should own:

- worker protocol decoding and encoding
- request lifecycle
- playback
- voice profile storage
- queueing
- logging and observability
- request-time integration with `TextForSpeech`

`SpeakSwiftly` should not remain the owner of the normalization system once this split is complete.

## Required behavior model

### Base profile

`TextForSpeech` should define a public base profile that captures the current built-in normalization behavior.

This base profile is not the same thing as an empty default profile.

It should represent the current always-on rules that make speech output reliable, including categories such as:

- fenced code handling
- inline code handling
- markdown link handling
- URL normalization
- Gale alias handling
- file path normalization
- identifier cleanup
- code-heavy line normalization
- spiral-prone word handling
- whitespace cleanup

The implementation may still keep some of those as built-in passes under the hood, but the package-level model should treat them as the base profile behavior, not as an unrelated invisible layer.

### Custom profile merging

Custom profiles should be merged with the base profile when loaded or selected.

That means the effective profile for a request should be:

1. start with the base profile
2. overlay the selected custom profile
3. preserve phase ordering and priority semantics

The important outcome is:

- built-in reliability stays on
- custom rules can extend or override it
- consumers do not have to rebuild the base behavior themselves

### Runtime semantics

`TextForSpeechRuntime` should own:

- the active custom profile
- stored custom profiles
- the base profile
- effective-profile snapshots for new jobs
- persistence

Each new job should still capture a stable snapshot at start time.

## Public API outcomes

### TextForSpeech public API

`TextForSpeech` should expose a public API that supports:

- constructing profiles
- constructing replacement rules
- storing named profiles
- updating or replacing named profiles
- removing named profiles
- reading the base profile
- reading the active custom profile
- reading the effective merged profile
- snapshotting the effective profile for a new normalization job
- persistence load and save operations

Convenience APIs should be added so consumers do not have to constantly rebuild arrays by hand for every small change.

That likely means adding public methods along the lines of:

- append replacement
- update replacement
- remove replacement
- replace profile

The exact names should stay Swifty and value-oriented, but the workflow should stop feeling low-level.

### SpeakSwiftly public API

`SpeakSwiftly.Runtime` should expose public normalization-facing APIs such as:

- reading the current normalization state
- using a normalization profile
- storing a normalization profile
- removing a normalization profile
- resetting to base-only behavior
- choosing a normalization profile for a speech request
- choosing an input kind for a speech request

The important practical outcome is that a `SpeakSwiftly` consumer can manage normalization without reaching around the runtime and rebuilding internal assumptions themselves.

## Implementation plan

### Phase 1: Build the real TextForSpeech package

In `../TextForSpeech`:

1. Move the current `TextForSpeech` models from `SpeakSwiftly` into the real package.
2. Move the actual normalizer implementation from `SpeakSwiftly` into `TextForSpeech`.
3. Move or recreate the relevant normalization tests there.
4. Define the base profile behavior explicitly.
5. Implement effective-profile merging.

Exit criteria:

- `TextForSpeech` can normalize text on its own
- the current built-in behavior is preserved
- the package has passing tests for profile selection and merging

### Phase 2: Add runtime ownership and persistence

In `../TextForSpeech`:

1. Expand `TextForSpeechRuntime` so it owns:
   - base profile
   - active custom profile
   - stored custom profiles
   - effective-profile snapshots
2. Add persistence for text profiles.
3. Keep persistence format simple first, likely JSON on disk.
4. Add tests for:
   - base-only behavior
   - merged custom behavior
   - persistence round-trip
   - active-profile fallback after removal

Exit criteria:

- profiles are not only in-memory
- the package can reload persisted profiles
- the effective merged profile is stable and test-covered

### Phase 3: Adopt TextForSpeech in SpeakSwiftly

In `SpeakSwiftly`:

1. Add `TextForSpeech` as a package dependency.
2. Remove duplicated local `TextForSpeech` model ownership.
3. Remove duplicated local normalization implementation or leave only thin compatibility shims during migration, then delete them in the same pass.
4. Wire `SpeakSwiftly.Runtime` to own a `TextForSpeechRuntime`.
5. Use request-time snapshots from that runtime when normalizing speech requests.

Exit criteria:

- `SpeakSwiftly` depends on external `TextForSpeech`
- `SpeakSwiftly` no longer acts as the hidden source of truth for normalization

### Phase 4: Expose real consumer-facing normalization APIs

In `SpeakSwiftly`:

1. Add public APIs to manage normalization profiles.
2. Extend speech request APIs so callers can specify:
   - normalization profile ID
   - input kind
   - context
3. Extend the worker protocol if needed so the CLI/process boundary can also select profile and kind.
4. Add integration tests for:
   - base profile only
   - base plus custom profile
   - stored profile selection
   - profile persistence across runtime restarts if that is meant to apply in `SpeakSwiftly`

Exit criteria:

- a package consumer can actually use the profile system through `SpeakSwiftly`
- the package no longer exposes a mostly-theoretical normalization model

## Migration notes

During migration, avoid leaving long-term duplicate sources of truth in place.

If compatibility shims are temporarily needed, they should be explicitly temporary and removed before calling the split complete.

The final architecture should have:

- one source of truth for text normalization logic
- one source of truth for text profile runtime state
- one speech runtime that consumes that subsystem cleanly

## Deferred follow-up

These are good follow-up items, but they should not block the first complete split:

- YAML-backed configuration
- hot reload
- SwiftUI settings integration
- richer slice types as first-class public API
- more specialized match kinds such as path-segment or regex rules

The important thing is to finish the useful core first:

- base profile
- merged custom profiles
- persistence
- public `SpeakSwiftly` integration
