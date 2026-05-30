# Generation Quality Telemetry And Guard Plan

Date: 2026-05-30

Tracking issue: [#83](https://github.com/gaelic-ghost/SpeakSwiftly/issues/83)

## Status

In progress.

Stage 1 trace-only telemetry has an initial implementation in the playback trace
surface. When `SPEAKSWIFTLY_PLAYBACK_TRACE=1` is enabled, live playback now emits
`playback_trace_generation_quality_chunk` before raw generated sample chunks are
shaped into playback buffers. This intentionally stays inside the existing
playback trace setup instead of adding a new generation-quality flag.

Stage 2 warning telemetry is also in place for high-signal suspicious chunks.
The monitor now emits `playback_generation_quality_warning` as a request-scoped
warning event and mirrors the structured event through `Logger` for Console and
Unified Logging inspection. Cutoff behavior remains intentionally pending until
warning telemetry has enough suspicious real-run evidence.

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

Initial trace fields:

- `generated_duration_ms`
- `total_generated_duration_ms`
- `peak_amplitude`
- `rms_amplitude`
- `near_silence_ratio`
- `clipping_ratio`
- `non_finite_sample_count`
- `dc_offset`
- `zero_crossing_rate`
- `boundary_jump`
- `repeated_window_similarity`

### Stage 2: Warning Events

Implemented for the initial playback path. Strong but non-fatal signals become
request-scoped warning events. The initial warning reasons are:

- `non_finite_samples`
- `clipping`
- `repeated_non_silent_window`
- `excessive_generated_duration`
- `dc_offset`

Warnings are visible through the same stderr JSONL request logging surface used
for synthesis and playback telemetry. They use `level: "warning"` and are also
mirrored to Apple's Unified Logging surface through `Logger` with the
`com.gaelic-ghost.SpeakSwiftly` subsystem and `worker` category. The OSLog
message intentionally carries event/request metadata rather than full details so
raw requested text does not move into persistent system logs.

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

The current useful shape is:

- `GeneratedAudioQualityMonitor` owns rolling sample windows and request-level
  counters.
- `GeneratedAudioQualityObservation` carries per-chunk metrics.
- `GeneratedAudioQualityWarning` carries warning reason, message, and observed
  metric values.
- `AudioPlaybackDriver.play(...)` or the resident generation forwarding loop
  feeds chunks into the monitor before `makePCMBuffer(...)`.
- warning outcomes flow through existing playback events and request logging.
- abort outcomes remain pending until thresholds have better evidence.

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

- Resolved for the initial implementation: trace-only quality metrics are
  enabled by the existing playback trace flag. Reconsider a dedicated
  generation-quality trace flag only if the event volume becomes too noisy or
  generated-file jobs need the same metric surface outside playback.
- Should abort outcomes use an existing worker error code or a new
  generation-quality-specific code?
- Should generated-file jobs receive the same quality metrics before live
  playback cutoffs ship?
- Which Qwen profiles should become the standard comparison set for good,
  borderline, and bad generations?

## First Slice

1. Done: add trace-only metrics for live generated chunks before playback
   scheduling.
2. Done: extend the trace E2E suite so `playback_trace_generation_quality_chunk`
   must appear in real worker playback trace output.
3. Run known-good Qwen prompts and at least one reproduced bad or suspicious
   generation through the same metric surface.
4. Record the observed metric ranges in this note or a follow-up report.
5. Done: promote only the clearest signals into warning events.
6. Design cutoff thresholds after the warning telemetry has real examples.

## Initial Test Commands

Use the repo-maintenance E2E wrapper so the live `SpeakSwiftlyServer` service can
unload resident models before the package-owned worker starts and reload them
afterward:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite trace --playback-trace
sh scripts/repo-maintenance/run-e2e.sh --suite deep-trace --deep-trace --playback-trace
```

The wrapper calls `unload-live-service-resident-models.sh` before `swift test`
unless `SPEAKSWIFTLY_E2E_LIVE_SERVICE_MANAGED=1` is already set. It calls
`reload-live-service-resident-models.sh` on exit so the live service is restored
after the test run.

## Initial Observations

### Known-Good Trace Capture

Command:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite trace --playback-trace
```

Result:

- test passed
- the wrapper unloaded and reloaded live-service resident models
- 60 `playback_trace_generation_quality_chunk` events were emitted for
  `req-live-trace`
- total generated duration was 19,200 ms
- maximum peak amplitude was 0.593369
- maximum RMS amplitude was 0.141917
- maximum near-silence ratio was 0.667839
- maximum clipping ratio was 0
- non-finite sample count was 0
- maximum boundary jump was 0.035428
- repeated-window similarity ranged from -0.316463 to 0.389933
- maximum inter-chunk gap was 642 ms
- 7 quality chunks arrived while playback was rebuffering

Early read: the trace surface is usable for collecting healthy baseline ranges.
The known-good trace included quiet tail chunks near the end, including a final
chunk with peak amplitude around 0.0151 and RMS around 0.00359, so near-silence
alone should not become an abort signal. Repeated-window similarity stayed well
below a high-repeat threshold in this run.

### Warning Telemetry Smoke Pass

Command:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite trace --playback-trace
```

Result:

- test passed
- the wrapper unloaded and reloaded live-service resident models
- 53 `playback_trace_generation_quality_chunk` events were emitted
- 0 `playback_generation_quality_warning` events were emitted
- maximum generated duration was 16,720 ms
- maximum peak amplitude was 0.823839
- maximum RMS amplitude was 0.207812
- maximum near-silence ratio was 0.647917
- maximum clipping ratio was 0
- non-finite sample count was 0
- maximum repeated-window similarity was 0.240239

Early read: the initial warning thresholds do not fire on this healthy trace
capture. That is the desired first-pass behavior; suspicious-warning evidence
still needs a reproduced bad or borderline generation.

### Deep Trace Baseline Pass

Command:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite deep-trace --deep-trace --playback-trace
```

Result:

- test suite passed
- the wrapper unloaded and reloaded live-service resident models
- 5 real-worker deep-trace requests completed
- 1,049 total `playback_trace_generation_quality_chunk` events were emitted
- longest request generated 73,920 ms of audio
- maximum peak amplitude was 0.684818
- maximum RMS amplitude was 0.141314
- maximum near-silence ratio was 1.0
- maximum clipping ratio was 0
- non-finite sample count was 0
- maximum boundary jump was 0.094032
- repeated-window similarity ranged from -0.444082 to 1.0
- maximum inter-chunk gap was 843 ms
- 98 quality chunks arrived while playback was rebuffering

Early read: healthy deep-trace runs can contain chunks that are all or nearly
all silence, and repeated-window similarity can reach 1.0 during quiet tail
material. Warning and cutoff rules should therefore combine repeated-window
similarity with non-silent RMS or peak evidence, duration budget overrun, and
late-tail context instead of treating high similarity or near-silence alone as a
failure.
