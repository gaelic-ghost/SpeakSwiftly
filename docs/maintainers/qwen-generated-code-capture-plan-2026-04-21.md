# Qwen Generated-Code Capture Plan

## Status

The first direct-lane landing now exists in `SpeakSwiftlyTesting` as
`capture-qwen-codes`.

What shipped in this first pass:

- direct capture for `--conditioning raw|artifact|auto`
- replay-friendly JSON artifacts under `.local/volume-probes/`
- retained waveform analysis in the same artifact
- generated Qwen codec tensor capture
- reference codes, reference text token IDs, resolved language, and codec
  language ID capture
- paired capture-plus-replay artifacts for both
  `probe-soft-femme-20260421` and `probe-clear-masc-20260421`
- `compare-qwen-codes` for artifact-versus-artifact generated-code summaries
  and direct code-stream comparison
- raw-conditioning capture and replay controls for both investigation profiles

What is still intentionally deferred:

- streamed runtime generated-code capture
- fixture export automation for upstream `mlx-audio-swift`
- checksums or deduplicated large-payload storage

## Current Next Slice

The next concrete step after the first capture landing is a local replay helper
that can consume `capture-qwen-codes-*.json` directly inside
`SpeakSwiftlyTesting`.

That helper now exists as `replay-qwen-codes` and can now compare:

- pure bounded decode from the captured codes
- current helper decode (`debugDecodeChunk(...)`)
- plain streaming decode from the captured generated codes
- reference-warmed streaming decode from the same captured generated codes

That replay helper should:

- load one saved capture artifact
- rebuild the captured generated and reference code tensors as `MLXArray`
- run the same four decode surfaces already used in the upstream fork audit
  - bounded decode
  - current `debugDecodeChunk(...)`
  - reference-warmed `debugStreamingDecode(...)`
- write one replay artifact under `.local/volume-probes/`
- reuse the same retained waveform summaries already used by
  `compare-volume` and `capture-qwen-codes`

That now gives us a local narrow lane for answering the decode-path question
from both a degraded saved run and a healthier saved run before we build any
fixture-export convenience.

The next investigation step is no longer "capture the second profile." It is
to compare the captured-code statistics directly across:

- soft-femme versus clear-masc
- raw versus artifact conditioning for the same profile

That should tell us whether the meaningful divergence is already present in the
generated codec sequence before replay decode starts.

After the raw capture-and-replay pass, the answer is sharper: profile-sensitive
behavior persists across both `raw` and `artifact` conditioning, and replay
decode still does not look like the main divergence point.

Also keep the broader operator symptom in view:

- the degraded long-form runs are reported to drift upward in pitch and faster
  in cadence over time, not just lower in retained loudness
- those symptoms also do not present identically on every bad run; loudness
  decay, pitch rise, faster cadence, and glitchier delivery appear to be
  common but inconsistent manifestations, which makes a compound and partly
  non-deterministic failure model more plausible than one tidy single bug

That means the next analysis should stay open to prosody-regime drift rather
than treating this purely as an amplitude-envelope problem.

The first quarter-level codebook pass now exists too. It is directionally
useful, but it did not reveal one obvious late-quarter cliff that cleanly
explains the bad profile by itself. The next narrower slice should therefore
either:

- inspect those suspect codebooks on a finer time grid than quarters, or
- add audio-side pitch and cadence summaries so the token drift can be checked
  against the reported perceptual shift directly

That first audio-side prosody summary path now exists as well, using lightweight
pitch and pulse-rate proxies derived from the saved waveform windows. The first
read is informative but not yet aligned with the reported symptom: the coarse
proxy trends slightly downward on both profiles rather than clearly surfacing
the reported pitch-up / faster-cadence drift. That means the next prosody pass
should use a better-targeted measurement, not assume the symptom is disproven.

The new `analyze-audio-prosody` helper also gives us a cheaper direct-WAV spot
check without rerunning Qwen generation. That tighter `0.5s` pass was useful
for ruling out one glitchy replay as the whole story, but it still did not
produce a clean soft-femme-only pitch-up / cadence-speedup signature. The
quarter medians stayed fairly flat on both profiles, and the healthier
clear-masc run still showed a modest tail-ward pulse-rate increase. So the next
audio-side slice should improve the estimator itself, not expand the same proxy
across more reruns.

The next controlled runtime sweep should also test resident streaming cadence
directly. The current `0.18s` cadence appears to be a playback-oriented policy
chosen to reduce one-chunk startup shudder, but on the Qwen path it also forces
very frequent streaming decoder flushes. In the current vendored implementation
the streaming decoder flush size is derived from:

- `streamingChunkSize = max(1, Int(streamingInterval * 12.5))`

That means the current sweep should cover:

- `0.18s`
- `0.32s`
- `0.64s`
- `1.0s`
- `1.5s`
- `2.0s`

And it should explicitly track two linked questions:

1. Does a larger cadence improve long-form output quality or stability for the
   degraded profiles?
2. Does a larger cadence reduce generation-and-decode churn enough to improve
   throughput, chunk smoothness, or glitch resistance without reintroducing the
   original startup shudder that motivated the tighter cadence?

The current working model is:

- cadence does not change Qwen sampling randomness directly
- cadence does change how often the decoder is asked to flush tiny batches of
  new codec frames into waveform output
- smaller cadences likely increase decoder call overhead, chunk-boundary churn,
  and generation-time contention
- those factors are plausible contributors to the observed inconsistent symptom
  cluster even if they are not the only root cause

The first real sweep is now complete for
`probe-soft-femme-20260421` under artifact conditioning, and it reinforces the
same conclusion while narrowing the next step:

- `0.18s` remained strongly degraded
- `0.32s` improved dramatically in the streamed lane
- `0.64s` and `1.0s` swung back toward heavy degradation
- `1.5s` improved relative to the baseline but was still clearly degraded
- `2.0s` also improved relative to the baseline

So the cadence effect is real, but not monotonic. The next practical slice
should be:

1. remove the hardcoded English language setting
2. rerun a narrower cadence set centered on the strongest current candidate
   - `0.18s`
   - `0.32s`
   - `2.0s`
3. repeat that narrower set on `probe-clear-masc-20260421` so the healthier
   profile can serve as a control against the soft-femme degraded profile

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
