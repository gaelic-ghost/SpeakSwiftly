# Qwen Generated-Code Capture Plan

## Purpose

This note plans the next investigation surface for the Qwen long-form decay
issue in `SpeakSwiftly`.

The current `SpeakSwiftlyTesting` harness is now good at comparing retained
waveform output across:

- streamed runtime generation
- direct non-stream generation
- raw rebuilt conditioning
- persisted artifact conditioning
- short versus long prompt length

What it still does not preserve is the exact generated Qwen codec sequence from
the bad run itself.

That missing surface is now the highest-value follow-up because it would let us
take one concrete SpeakSwiftly failure case and replay the identical generated
codes inside upstream `mlx-audio-swift` across multiple decode paths.

## Goal

Add an opt-in investigation path that captures the exact generated Qwen codec
stream, together with enough request metadata to replay the run later.

The captured artifact should let us answer two separate questions cleanly:

1. Did the runtime produce a bad waveform because the generated codec sequence
   itself drifted toward lower-energy content over time?
2. Or did the waveform become bad only after that same codec sequence went
   through a particular decode path?

## Desired Artifact Shape

The capture artifact should be JSON-first and investigation-oriented.

At minimum it should record:

- `generatedAt`
- `profileName`
- `profileRoot`
- `requestText`
- `textCharacters`
- `textWords`
- `conditioningMode`
  - `raw`
  - `artifact`
- `lane`
  - `streamed`
  - `direct`
- `modelRepo`
- `referenceAudioFile`
- `referenceText`
- `generatedFilePath`
- `sampleRate`
- retained waveform analysis summary
  - first and last RMS
  - head and tail RMS
  - `tail_head_ratio`
  - quarter summaries if available
- generated-code payload
  - generated code tensor values
  - generated code tensor shape
- reference-conditioning payload when present
  - reference speech codes
  - reference text token IDs
  - resolved language
  - codec language ID

If storing the full speaker embedding is too large or awkward, it can be
omitted initially. The critical replay surface is the generated codec stream and
the reference codec/text prefix information.

## Recommended Capture Surface

The cleanest initial implementation is a new `SpeakSwiftlyTesting` command
rather than expanding the existing user-facing runtime API.

Suggested command:

- `capture-qwen-codes`

Suggested invocation shape:

```bash
swift run SpeakSwiftlyTesting capture-qwen-codes \
  --profile probe-soft-femme-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --conditioning artifact \
  --text-file /path/to/long-prompt.txt \
  --lane direct
```

Optional follow-up:

- allow `--lane streamed` too, but direct capture should land first because it
  avoids mixing runtime playback questions into the first generated-code
  artifact format

## Why a New Command Is Better Than Extending `compare-volume`

`compare-volume` is currently a waveform-comparison tool.

That is a good operator-facing surface for:

- retained loudness analysis
- streamed-versus-direct comparison
- raw-versus-artifact comparison

But generated-code capture changes the artifact size, the debugging intent, and
the expected consumers. A dedicated command keeps that complexity away from the
simple volume-probe path and makes it easier to evolve the codec-capture format
without confusing the existing harness output.

## Implementation Shape

### 1. Add an opt-in generated-code callback surface in vendored `mlx-audio-swift`

`SpeakSwiftly` currently uses `AnySpeechModel` plus the resident Qwen runtime
paths in:

- `Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift`
- `Sources/SpeakSwiftly/Generation/FileGenerationOperations+ResidentInputs.swift`

The current runtime records token, info, and audio events, but not the final
codec tensor payload.

We should add a narrow debug-only surface in the vendored `mlx-audio-swift`
checkout used by this repo that exposes the same kind of generated-code capture
hooks already added in the local upstream audit branch.

The required shape is small:

- capture generated codes after generation
- capture reference codes when present
- expose them back to `SpeakSwiftlyTesting` without changing the ordinary public
  package API more than necessary

If possible, mirror the upstream debug hook shape closely so later cross-repo
comparison stays easy.

### 2. Thread that debug capture through the local Qwen generation path

For the first pass, keep this scoped to the direct harness path in
`SpeakSwiftlyTesting`.

That means:

- load the same Qwen model already used by `runDirectProbe(...)`
- run the same raw or artifact conditioning path
- collect waveform output exactly as today
- additionally collect the generated codec payload and reference prefix payload
- write one JSON artifact under `.local/volume-probes/`

This lets the first capture feature stay out of the worker runtime and out of
the playback path.

### 3. Write one replay-friendly JSON artifact

Suggested directory:

- `.local/volume-probes/`

Suggested stem:

- `capture-qwen-codes-<ISO8601>.json`
- `capture-qwen-codes-latest.json`

Suggested top-level fields:

- `schemaVersion`
- `generatedAt`
- `profileName`
- `conditioningMode`
- `lane`
- `text`
- `textCharacters`
- `textWords`
- `modelRepo`
- `retainedAnalysis`
- `generatedCodes`
- `referenceCodes`
- `referenceTextTokenIDs`
- `resolvedLanguage`
- `codecLanguageID`
- `generatedFilePath`

## First Acceptance Target

The first version is good enough if it can do all of the following:

1. Run against `probe-soft-femme-20260421` and `probe-clear-masc-20260421`.
2. Capture direct raw and direct artifact runs.
3. Preserve the generated codec tensor in a replayable JSON artifact.
4. Preserve the retained waveform summary in the same artifact.
5. Let us take that artifact into `mlx-audio-swift` and compare:
   - bounded decode
   - current `decodeChunk(...)`
   - reference-warmed incremental decode

## Nice Follow-Ups After First Landing

These are valuable, but not required for the first usable capture surface:

- capture streamed runtime generated codes too
- include artifact ID and request ID when available
- add a paired replay helper in `SpeakSwiftlyTesting`
- add a small script that turns a capture artifact into an upstream
  `mlx-audio-swift` fixture
- add a checksum or hash of the generated code payload for quick rerun
  comparison

## Risks and Constraints

### Artifact size

Long-form generated code payloads may get large. That is acceptable for local
maintainer investigation, but the format should still stay straightforward and
JSON-first until size becomes a real problem.

### Debug-surface creep

This should stay an investigation hook, not a broad public API commitment.

Prefer:

- internal hooks
- test-harness-owned wiring
- maintainer-doc usage

Avoid turning generated-code capture into a general runtime feature unless a
clear operator-facing use case appears later.

### Runtime pollution

The first pass should avoid touching ordinary playback or worker request flow if
the same result can be achieved in the direct `SpeakSwiftlyTesting` path.

That keeps the failure surface smaller and makes the captured artifacts easier
to reason about.

## Recommended Step Order

1. Add the minimum vendored `mlx-audio-swift` debug hook needed to capture
   generated and reference codes from direct Qwen generation.
2. Add `capture-qwen-codes` to `SpeakSwiftlyTesting`.
3. Write artifacts under `.local/volume-probes/`.
4. Run one direct raw and one direct artifact capture for
   `probe-soft-femme-20260421` on the long prompt.
5. Replay those exact captures upstream in `mlx-audio-swift`.
6. Only after that decide whether streamed runtime capture is still necessary.

## Success Condition

We should consider this plan successful when one concrete SpeakSwiftly bad run
can be preserved as:

- one retained waveform artifact
- one generated-code JSON artifact

and that same generated-code artifact can be replayed upstream to answer
whether the late-tail failure came from sequence generation, decode choice, or
their interaction.
