# Generation Quality Telemetry And Guard Plan

Date: 2026-05-30

Tracking issue: [#83](https://github.com/gaelic-ghost/SpeakSwiftly/issues/83)

## Status

Planned.

This note captures the first implementation shape for detecting runaway or
glitchy speech generations before they continue through live playback. The
initial target is Qwen3 live generation, but the plan should stay backend-aware
instead of Qwen-only where the signal is audio-derived.

## Problem

Live speech generation can complete from the runtime's point of view while still
producing bad audible output. Playback completion currently proves that generated
sample chunks were buffered, scheduled, and drained. It does not prove that the
generation sounded healthy, stopped at a sensible point, or avoided late-tail
spirals.

The most important failure mode to catch is a model that keeps producing
speech-like audio after the useful text pressure has faded. For Qwen3 this can
show up as long tail behavior, repeated or spiraling prosody, unstable chunk
cadence, or audio that remains technically playable while becoming clearly wrong.

## Current Live Playback Path

The live Qwen path is sample-stream based, not WAV-buffer based:

1. Qwen generation emits token, info, and audio events.
2. Audio events yield `[Float]` sample chunks into the resident generation stream.
3. `handleQueueSpeechLiveGeneration(...)` forwards each sample chunk into the
   request playback stream.
4. `AudioPlaybackDriver.play(...)` consumes that stream, records chunk cadence,
   shapes samples, and turns chunks into `AVAudioPCMBuffer` instances.
5. `AudioPlaybackRequestState` stores queued buffers and queue-depth accounting.
6. `AVAudioPlayerNode.scheduleBuffer(...)` hands each buffer to Core Audio.
7. Playback callbacks mark scheduled buffers as played back and drive drain,
   rebuffer, starvation, and completion handling.

That means the best first guard point is between sample chunk receipt and buffer
scheduling. At that point the runtime still knows the request, backend, sample
rate, chunk index, generated duration, planned text chunk, recent sample history,
and whether the audio has already reached the player.

## Existing Signals

SpeakSwiftly already records useful delivery-health signals:

- time to first chunk
- time to preroll
- chunk count and sample count
- inter-chunk gap warnings
- scheduling gap warnings
- queued-audio depth
- rebuffer, starvation, and rebuffer-thrash warnings
- boundary discontinuity and leading/trailing amplitude summaries
- synthesis token, info, and audio-chunk events

These signals are necessary but not sufficient. They explain whether the stream
arrived and drained. They do not classify whether the generated content itself
was healthy enough to keep playing.

## Proposed Guard Stages

### Stage 1: Trace-Only Quality Telemetry

Add a small rolling audio-quality analyzer that observes generated sample chunks
before they are converted to playback buffers. It should emit metrics without
changing behavior.

Candidate metrics:

- generated duration per chunk and per request
- generated duration compared with normalized text length and word count
- peak amplitude, RMS, and near-silence ratio
- clipping ratio
- non-finite sample count before shaping replaces invalid values
- DC offset
- zero-crossing rate
- boundary jump before smoothing
- repeated-window similarity across recent audio
- chunk cadence compared with streaming interval and planned text chunks
- late-tail duration after the final planned text chunk starts

The trace surface should preserve enough context to compare good and bad runs
without persisting raw spoken text in normal logs.

### Stage 2: Warning Events

Promote strong but non-fatal signals into request-scoped warning events. These
warnings should be operator-facing and specific, for example:

- generation exceeded the expected audio-duration budget for the input size
- repeated audio windows were detected across multiple chunks
- the generated tail stayed active after the planned text chunk should have
  ended
- chunk cadence became unstable while playback remained otherwise healthy

Warnings should be visible through the same observation and logging surfaces
used for synthesis and playback telemetry.

### Stage 3: Conservative Cutoff

Only after trace data proves the thresholds, add abort behavior for high-confidence
failure patterns. A cutoff should:

1. cancel the active generation task
2. stop and reset active playback if unhealthy audio has already been scheduled
3. finish the request with a clear failure reason
4. log which guard fired, the observed metric values, and the most likely cause

Cutoff rules should require multiple signals at first. A single loud sample,
brief silence, expressive held vowel, or long but valid sentence should not abort
the request by itself.

## Likely Implementation Shape

Start with a local support type in the playback or generation feature area,
depending on where the final call site lands. This should be a local
implementation detail, not a new runtime subsystem.

The simplest useful shape is:

- `GenerationQualityMonitor` owns rolling sample windows and request-level
  counters.
- `GenerationQualityObservation` carries per-chunk metrics.
- `GenerationQualityDisposition` returns `.healthy`, `.warning`, or `.abort`.
- `AudioPlaybackDriver.play(...)` or the resident generation forwarding loop
  feeds chunks into the monitor before `makePCMBuffer(...)`.
- warning and abort outcomes flow through existing request observation and
  worker-error completion paths.

Prefer one monitor per active live request. Avoid global shared state unless a
later issue proves cross-request comparison is useful.

## Qwen-Specific Inputs

Qwen should combine audio-derived quality signals with synthesis-side telemetry:

- generated token count
- codec/audio event count
- model info timing
- streaming interval
- planned text chunk index and word count
- whether prepared conditioning was used
- generation parameters such as temperature, top-p, top-k, min-p, repetition
  penalty, and token limits

This should connect with the existing Qwen sampling headroom investigation rather
than replacing it. Sampling changes can reduce the chance of bad tails, while
quality guards limit damage when bad tails still happen.

## Non-Goals

- Do not tune Qwen defaults from one bad audible sample.
- Do not classify speech quality from playback drain success alone.
- Do not add a separate playback subsystem.
- Do not persist raw spoken request text in quality logs.
- Do not make cutoff behavior default-on until trace data supports the threshold
  choices.

## Open Questions

- Should trace-only quality metrics be enabled by the existing playback trace
  flag, a new generation-quality trace flag, or both?
- Should abort outcomes use an existing worker error code or a new
  generation-quality-specific code?
- Should generated-file jobs receive the same quality metrics before live
  playback cutoffs ship?
- Which Qwen profiles should become the standard comparison set for good,
  borderline, and bad generations?

## First Slice

1. Add trace-only metrics for live generated chunks before playback scheduling.
2. Run known-good Qwen prompts and at least one reproduced bad or suspicious
   generation through the same metric surface.
3. Record the observed metric ranges in this note or a follow-up report.
4. Promote only the clearest signals into warnings.
5. Design cutoff thresholds after the warning telemetry has real examples.
