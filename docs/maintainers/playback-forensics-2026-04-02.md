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

## 2026-04-02 adaptive-threshold follow-up

Context:

- We continued audible forensic playback after splitting the playback subsystem into its own file and after adding adaptive threshold floors so later cadence updates could not silently erase earlier rebuffer or starvation escalation.
- We also tested a more conservative `extended` complexity-class seed and added extra startup and resume budget when observed chunk cadence was slower than realtime.

What improved:

- Runaway or looping behavior still did not reproduce in the long code-heavy forensic request.
- A direct trace from the updated worker confirmed that raised rebuffer targets were finally being honored instead of collapsing back to the old seed immediately afterward.
- In the updated direct trace, rebuffer resumes occurred at progressively higher queue depths such as:
  - `800 ms` at `resume_buffer_target_ms: 729`
  - `960 ms` at `resume_buffer_target_ms: 820`
  - `1120 ms` at `resume_buffer_target_ms: 981`
  - `1280 ms` at `resume_buffer_target_ms: 1225`

What still remains:

- Audible playback is still skipping too often, especially early in long code-heavy requests.
- Early forensic playback can still show roughly `2.0 GB` memory usage in `btop`, which is materially better than prior runaway states but still higher than we would like for this prompt class.
- Even after threshold-floor fixes, the worker can still enter repeated rebuffer cycles on heavy prompts, so buffering is improved but not yet solved.

Interpretation:

- Preserving threshold escalation floors fixed a real controller bug, but that bug was not the entire skip problem.
- The remaining issue now looks more like "the initial and early adaptive policy is still too optimistic for some code-heavy cadences" than "we are losing escalation state mid-run."
- Boundary smoothing is still a distinct follow-up area, but repeated rebuffer remains the dominant audible defect for these forensic requests.

Interpretation:

- The major choppiness problem was not purely "the model is bad at this prompt."
- Adaptive buffering materially reduced starvation and made playback much more stable.
- The remaining skips look more like repeated low-buffer rebuffer cycles than full starvation cascades.
- The remaining pops are likely a separate boundary-quality issue and should be revisited after buffering behavior is stable enough that the two problem classes do not mask each other.

Operational notes:

- Live service logs are under `~/Library/Logs/speak-to-user-mcp/<VERSION>/`.
- For local forensic runs, stop the live `speak-to-user-mcp` service first so the worker has more unified memory available.
- A separate queue-ordering bug allowed `speak_live` to outrun an earlier `create_profile` for the same profile name; that was fixed in commit `a4f62eb`.
- The direct-command forensic capture path that worked reliably was:
  - reuse the Xcode-built worker product under `/var/folders/.../SpeakSwiftly-xcodebuild-e2e-dd/Build/Products/Debug/SpeakSwiftly`
  - point `DYLD_FRAMEWORK_PATH` at the matching `Build/Products/Debug` directory
  - hold stdin open with a pattern like `(cat input.jsonl; sleep 180) | ... SpeakSwiftly ...`
  - capture `stdout` and `stderr` JSONL separately under `/tmp/...`
- Closing stdin before queued work drains currently cancels queued requests, even if the worker is only waiting for resident-model warmup. This is a known behavior quirk that should be fixed soon.

Next buffering direction:

- Let repeated rebuffers raise adaptive thresholds even when starvation never occurs.
- Keep starvation as an immediate stronger escalation path.
- Bias the `extended` complexity class toward a more conservative startup policy for code-heavy requests, especially early in playback.
- Revisit the worker's stdin-close cancellation behavior after the buffering path is in a better place, because it currently makes direct forensic capture more fragile than it should be.
- Revisit chunk-boundary smoothing only after the buffering path is no longer the dominant source of audible defects.
