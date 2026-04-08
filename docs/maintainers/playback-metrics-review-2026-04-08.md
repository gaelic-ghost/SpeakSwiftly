# Playback Metrics Review

Date: 2026-04-08

## Scope

Use the retained audible e2e stderr artifacts to decide whether the remaining wobble and pops are primarily:

- hard starvation
- schedule jitter / late buffer scheduling
- chunk-boundary shaping discontinuity

This review intentionally uses shipped `stderr.jsonl` artifacts instead of synthetic spies so the conclusion stays grounded in the real worker path.

## Evidence

Clean sequential audible Marvis run:

- artifact: [`.local/e2e-runs/2026-04-08T00-48-11Z-91ec1fbd-f3dc-40f4-97f4-a6bffdfd5d2b-marvisvoicedesignprofilesrunaudibleliveplaybackacrossallvibes/stderr.jsonl`](/Users/galew/Workspace/SpeakSwiftly/.local/e2e-runs/2026-04-08T00-48-11Z-91ec1fbd-f3dc-40f4-97f4-a6bffdfd5d2b-marvisvoicedesignprofilesrunaudibleliveplaybackacrossallvibes/stderr.jsonl)
- all three `playback_finished` events reported:
  - `rebuffer_event_count: 0`
  - `starvation_event_count: 0`
  - `max_schedule_gap_ms: 0`
  - `max_inter_chunk_gap_ms: 0`
  - `max_boundary_discontinuity` stayed modest, roughly `0.048` to `0.080`

Queued audible Marvis run:

- artifact: [`.local/e2e-runs/2026-04-08T00-35-03Z-1156ff8a-b3d8-4485-a3b7-55c1b2d978e7-marvisaudibleliveplaybackprequeuesthreejobsanddrainsinorder/stderr.jsonl`](/Users/galew/Workspace/SpeakSwiftly/.local/e2e-runs/2026-04-08T00-35-03Z-1156ff8a-b3d8-4485-a3b7-55c1b2d978e7-marvisaudibleliveplaybackprequeuesthreejobsanddrainsinorder/stderr.jsonl)
- first queued live request (`req-live-marvis-queued-femme`) reported:
  - repeated `playback_rebuffer_started`
  - one `playback_schedule_gap_warning`
  - `playback_finished` with `rebuffer_event_count: 4`, `rebuffer_total_duration_ms: 8246`, `starvation_event_count: 0`, `max_schedule_gap_ms: 266`, `max_boundary_discontinuity: 0.0782`
- second queued live request (`req-live-marvis-queued-masc`) reported:
  - dense runs of `playback_schedule_gap_warning`
  - repeated `playback_rebuffer_started`
  - queued audio repeatedly collapsing toward `480ms`
  - no `playback_starved` evidence in the retained event stream before the test moved on

## Conclusion

The dominant audible defect is schedule jitter and queue-drain timing under pressure, not hard starvation and not primarily chunk-boundary shaping.

Why:

- the clean sequential audible run has zero schedule-gap and zero rebuffer events while still showing roughly the same boundary-discontinuity range as the noisy run
- the queued audible run degrades exactly where schedule-gap warnings and rebuffers spike
- the queued audible run keeps reporting `starvation_event_count: 0` even when playback quality is already visibly worse

So the current ordering is:

1. scheduling jitter / late buffer scheduling
2. rebuffer behavior driven by that jitter
3. chunk-boundary shaping as a secondary polish issue
4. hard starvation as a non-primary issue in the retained audible Marvis evidence

## Follow-through

Before any further cadence retune, prefer work that reduces late scheduling on queued live playback. Do not treat boundary shaping as the lead problem while the queued lane is still producing repeated `playback_schedule_gap_warning` and rebuffer bursts.
