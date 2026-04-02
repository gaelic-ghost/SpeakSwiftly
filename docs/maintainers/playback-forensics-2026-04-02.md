# Playback Forensics Notes

## 2026-04-02 adaptive buffering pass

Context:

- We ran audible forensic playback against a long, code-heavy request with paths, markdown fences, optional-chaining syntax, nil-coalescing syntax, and oddly spelled words.
- The goal was to separate runaway generation problems from playback buffering and chunk-boundary problems.

What improved:

- The current adaptive-buffering build was subjectively much better than the earlier fixed-threshold behavior.
- `btop` memory during the improved audible run was around `1.3 GB`, down from earlier problem runs that were often observed around `2 GB` and sometimes higher.
- The improved forensic trace completed cleanly with `0` starvation events.
- The improved forensic trace ended with:
  - `avg_inter_chunk_gap_ms: 189`
  - `avg_queued_audio_ms: 634`
  - `startup_buffer_target_ms: 720`
  - `low_water_target_ms: 320`
  - `resume_buffer_target_ms: 720`
  - `time_to_first_chunk_ms: 508`
  - `time_to_preroll_ready_ms: 1543`
- The older bad trace had roughly `160 ms` output chunks arriving around `315 ms` apart, with frequent queue collapse and repeated starvation.
- The improved run still used `160 ms` output chunks, but chunk cadence later settled closer to `180 ms` to `197 ms` between arrivals instead of the older half-realtime behavior.

What still remains:

- Audible playback still has some skips.
- The improved forensic trace still showed `31` rebuffer events with about `12.7 s` of total rebuffer time.
- Audible playback still has occasional pops or static-like chunk-boundary roughness.
- The improved forensic trace still logged a non-trivial `max_boundary_discontinuity`, so boundary shaping remains a separate follow-up area.

Interpretation:

- The major choppiness problem was not purely "the model is bad at this prompt."
- Adaptive buffering materially reduced starvation and made playback much more stable.
- The remaining skips look more like repeated low-buffer rebuffer cycles than full starvation cascades.
- The remaining pops are likely a separate boundary-quality issue and should be revisited after buffering behavior is stable enough that the two problem classes do not mask each other.

Operational notes:

- Live service logs are under `~/Library/Logs/speak-to-user-mcp/<VERSION>/`.
- For local forensic runs, stop the live `speak-to-user-mcp` service first so the worker has more unified memory available.
- A separate queue-ordering bug allowed `speak_live` to outrun an earlier `create_profile` for the same profile name; that was fixed in commit `a4f62eb`.

Next buffering direction:

- Let repeated rebuffers raise adaptive thresholds even when starvation never occurs.
- Keep starvation as an immediate stronger escalation path.
- Revisit chunk-boundary smoothing only after the buffering path is no longer the dominant source of audible defects.
