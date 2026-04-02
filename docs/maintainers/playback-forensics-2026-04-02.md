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

## 2026-04-02 phase-aware buffering follow-up

Context:

- We kept the existing text length and complexity classes, but added an explicit playback phase model inside the existing controller instead of creating a new subsystem.
- The controller now distinguishes `warmup`, `steady`, and `recovery` so early playback does not immediately behave like the request has already proven stable cadence.

What changed:

- `warmup` now uses a more conservative seeded posture derived from the existing complexity class.
- Stable chunk cadence can promote playback from `warmup` into `steady`.
- A rebuffer or starvation event can move a previously stable request into `recovery`.
- `recovery` can return to `steady` only after a shorter but still meaningful streak of stable chunk arrivals.

Why this matters:

- Earlier tuning helped preserve raised thresholds, but playback still skipped too often because the controller was still too eager to behave like steady-state early in the request.
- The phase-aware pass is intended to reduce early skips without throwing away the existing complexity-class prior.
- The complexity classes still matter as the initial guess; the new phase logic simply stops the controller from trusting the request too early.

Current status:

- Package verification passed after this change with `swift build`, `swift test --filter adaptivePlaybackThresholds`, and `swift test`.
- New tests now cover:
  - warmup to steady transition after stable chunk cadence
  - steady to recovery transition after rebuffer
  - recovery back to steady after stable cadence returns
- Audible verification on the phase-aware build was subjectively better, but still not fully smooth.
- The phase-aware direct trace ended with:
  - `avg_inter_chunk_gap_ms: 188`
  - `avg_queued_audio_ms: 1232`
  - `startup_buffer_target_ms: 1384`
  - `low_water_target_ms: 1054`
  - `resume_buffer_target_ms: 2214`
  - `startup_buffered_audio_ms: 1120`
  - `rebuffer_event_count: 10`
  - `rebuffer_total_duration_ms: 11100`
  - `longest_rebuffer_duration_ms: 1482`
  - `time_to_first_chunk_ms: 369`
  - `time_to_preroll_ready_ms: 1894`
  - `starvation_event_count: 0`
- Early direct-trace rebuffers resumed at sturdier queue depths like `1280 ms`, `1440 ms`, `1600 ms`, `1760 ms`, `1920 ms`, `2080 ms`, and `2240 ms`.

Interpretation:

- The major choppiness problem was not purely "the model is bad at this prompt."
- Adaptive buffering materially reduced starvation and made playback much more stable.
- The remaining skips look more like repeated low-buffer rebuffer cycles than full starvation cascades.
- The remaining pops are likely a separate boundary-quality issue and should be revisited after buffering behavior is stable enough that the two problem classes do not mask each other.
- The phase-aware pass appears to have reduced early eagerness and materially strengthened queue recovery, but some requests still skip more often than desired even after warmup and recovery improvements.
- The remaining gap now looks increasingly likely to involve speakability and text-shape effects in addition to buffering policy alone.
- Section-aware forensic tracing now emits `playback_section_detected` and `playback_section_window` events so we can correlate rebuffers against estimated content windows without pretending we have exact token-to-audio alignment.
- A forward segmented direct capture on the section-aware worker finished with `9` rebuffers and mapped those rebuffers roughly as:
  - `Section One`: `3`
  - `Section Two`: `2`
  - `Section Three`: `2`
  - `Section Four`: `1`
  - `Footer`: `1`
- A reversed-order segmented direct capture also finished with `9` rebuffers, but startup was materially faster:
  - `time_to_first_chunk_ms: 358` versus `1548` in the forward-order section-aware run
  - `time_to_preroll_ready_ms: 1808` versus `3067` in the forward-order section-aware run
- The reversed-order section-aware run mapped rebuffers roughly as:
  - `Footer`: `2`
  - `Section Three`: `2`
  - `Section Two`: `2`
  - `Section One`: `2`
  - one final late rebuffer fell just past the estimated final section window boundary
- That comparison suggests two things at once:
  - there is still an "early in the request" instability effect, because reversing the order materially improved startup timing
  - the harder text shapes still matter throughout the run, because reversing the order did not reduce the total rebuffer count
- The current best read is that both startup-phase instability and content-shape difficulty are contributing, rather than either one fully explaining the skips by itself.
- After the path-and-identifier normalization pass, a fresh forward segmented direct capture on the latest build still showed meaningful improvement in startup timing, but rebuffers remained frequent:
  - `time_to_first_chunk_ms: 491`
  - `time_to_preroll_ready_ms: 2411`
  - `rebuffer_event_count: 14`
  - `rebuffer_total_duration_ms: 18032`
  - `avg_inter_chunk_gap_ms: 189`
  - `avg_queued_audio_ms: 1512`
- That latest forward normalized run mapped rebuffers roughly as:
  - `Section One`: `4`
  - `Section Two`: `4`
  - `Section Three`: `3`
  - `Section Four`: `1`
  - `Footer`: `1`
  - one final late rebuffer fell just past the estimated final section window boundary
- A fresh reversed-order direct capture on the same normalized build performed better overall:
  - `time_to_first_chunk_ms: 405`
  - `time_to_preroll_ready_ms: 2205`
  - `rebuffer_event_count: 10`
  - `rebuffer_total_duration_ms: 11041`
  - `avg_inter_chunk_gap_ms: 189`
  - `avg_queued_audio_ms: 1259`
- That latest reversed normalized run mapped rebuffers roughly as:
  - `Footer`: `2`
  - `Section Four`: `1`
  - `Section Three`: `2`
  - `Section Two`: `3`
  - `Section One`: `1`
  - one final late rebuffer fell just past the estimated final section window boundary
- The latest normalized comparison strengthens the current hypothesis:
  - ordering still matters, because moving easier material earlier improves startup and lowers total rebuffer time
  - `Section Two` remains one of the strongest repeat offenders even when moved later, which keeps pointing at identifier-heavy speech normalization as the next high-signal tuning area
- We also added matched section-aware conversational prose probes to compare "ordinary" speech against the code-heavy forensic family with the same section-window machinery.
- The latest forward conversational direct capture finished with:
  - `time_to_first_chunk_ms: 426`
  - `time_to_preroll_ready_ms: 2279`
  - `rebuffer_event_count: 11`
  - `rebuffer_total_duration_ms: 12410`
  - `avg_inter_chunk_gap_ms: 193`
  - `avg_queued_audio_ms: 1325`
- The latest forward conversational run mapped rebuffers roughly as:
  - `Section One`: `4`
  - `Section Two`: `2`
  - `Section Three`: `2`
  - `Section Four`: `1`
  - `Footer`: `1`
  - one final late rebuffer fell just past the estimated final section window boundary
- The latest reversed conversational direct capture finished with:
  - `time_to_first_chunk_ms: 492`
  - `time_to_preroll_ready_ms: 2346`
  - `rebuffer_event_count: 9`
  - `rebuffer_total_duration_ms: 10484`
  - `avg_inter_chunk_gap_ms: 188`
  - `avg_queued_audio_ms: 1216`
- The latest reversed conversational run mapped rebuffers roughly as:
  - `Footer`: `2`
  - `Section Four`: `1`
  - `Section Three`: `2`
  - `Section Two`: `2`
  - `Section One`: `1`
  - one final late rebuffer fell just past the estimated final section window boundary
- The prose-versus-code comparison is useful but also exposed a detection problem:
  - the sectioned conversational prose still logged `looks_code_heavy: true`
  - the same prose also landed in `text_complexity_class: "extended"`
  - that likely means the current code-heaviness heuristic is overreacting to markdown section structure rather than actual code-ish content
- The latest cross-family comparison suggests:
  - prose is somewhat better than code-heavy material, but not dramatically better
  - reversing the section order helps both families, which keeps startup-phase sensitivity in the picture
  - identifier-heavy and section-leading content still appear to be meaningful contributors
  - the current complexity detector probably needs its own tuning pass before prose-versus-code classification can be trusted as a strong signal

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

- Explore text-side cadence stabilization for code-heavy or punctuation-heavy spans, since identifiers, paths, punctuation density, and oddly spelled words may still be producing uneven chunk timing even after the buffering improvements.
- Revisit the worker's stdin-close cancellation behavior after the buffering path is in a better place, because it currently makes direct forensic capture more fragile than it should be.
- Revisit chunk-boundary smoothing only after the buffering path is no longer the dominant source of audible defects.

## 2026-04-02 long prose threshold tuning log

Context:

- Gale asked for the long sectioned conversational prose forensic to be tuned directly against audible playback until rebuffering was eliminated.
- The tuning target in this pass was the direct worker capture path with trace enabled and the same long prose payload on every run.
- Every set below records the actual values in code at the time of the run, the exact test path used, and the observed result.

### Set A: pre-tuning baseline

Code values:

- `maxStartupBufferTargetMS: 2400`
- `maxResumeBufferTargetMS: 2800`
- `maxLowWaterTargetMS: 1600`
- `.extended` seed:
  - `startupBufferTargetMS: 960`
  - `lowWaterTargetMS: 480`
  - `resumeBufferTargetMS: 1120`
  - `chunkGapWarningMS: 620`
  - `scheduleGapWarningMS: 260`
- fixed drain timeout:
  - `5 seconds`

Validation path:

- direct audible worker capture
- trace file:
  - `/tmp/speakswiftly-prose-tune-1/stderr.jsonl`

Observed result:

- `playback_started` logged:
  - `startup_buffer_target_ms: 1127`
  - `startup_buffered_audio_ms: 1280`
- `playback_finished` logged:
  - `rebuffer_event_count: 11`
  - `rebuffer_total_duration_ms: 12220`
  - `starvation_event_count: 0`
  - `avg_inter_chunk_gap_ms: 194`
  - `avg_queued_audio_ms: 1300`
  - `time_to_preroll_ready_ms: 2179`
- conclusion:
  - baseline long prose was still audibly skipping and still rebuffering too often

### Set B: first aggressive seed attempt, stale worker binary

Code values:

- `maxStartupBufferTargetMS: 20000`
- `maxResumeBufferTargetMS: 24000`
- `maxLowWaterTargetMS: 12000`
- `.extended` seed:
  - `startupBufferTargetMS: 12800`
  - `lowWaterTargetMS: 4800`
  - `resumeBufferTargetMS: 16000`
  - `chunkGapWarningMS: 900`
  - `scheduleGapWarningMS: 400`
- fixed drain timeout:
  - `5 seconds`

Validation path:

- direct audible worker capture
- trace file:
  - `/tmp/speakswiftly-prose-tune-2/stderr.jsonl`

Observed result:

- the direct capture still logged roughly the old startup values:
  - `startup_buffer_target_ms: 1118`
  - `startup_buffered_audio_ms: 1120`
- `playback_finished` logged:
  - `rebuffer_event_count: 9`
  - `rebuffer_total_duration_ms: 9704`
- conclusion:
  - this run did not actually exercise the new thresholds because the direct worker command was still pointing at a stale Xcode-built binary
  - keep the numbers for provenance, but do not treat this run as a valid threshold result

### Set C: aggressive seed on rebuilt worker, fixed drain timeout

Code values:

- `maxStartupBufferTargetMS: 20000`
- `maxResumeBufferTargetMS: 24000`
- `maxLowWaterTargetMS: 12000`
- `.extended` seed:
  - `startupBufferTargetMS: 12800`
  - `lowWaterTargetMS: 4800`
  - `resumeBufferTargetMS: 16000`
  - `chunkGapWarningMS: 900`
  - `scheduleGapWarningMS: 400`
- fixed drain timeout:
  - `5 seconds`

Validation path:

- rebuilt the Xcode worker with `xcodebuild`
- direct audible worker capture
- trace file:
  - `/tmp/speakswiftly-prose-tune-3/stderr.jsonl`

Observed result:

- `playback_started` logged:
  - `startup_buffer_target_ms: 12800`
  - `startup_buffered_audio_ms: 12800`
- there were:
  - `0` `playback_rebuffer_started` events
  - `0` `playback_rebuffer_resumed` events
  - `0` starvation events
  - `0` schedule-gap warnings
- stdout ended with:
  - `audio_playback_timeout`
- stderr logged:
  - `worker_error`
  - `failure_code: "audio_playback_timeout"`
- conclusion:
  - the aggressive preroll and resume floors eliminated rebuffering for the long prose run
  - the next bottleneck was drain completion, because the worker still used a fixed `5 second` post-generation drain timeout even though more than `12.8 seconds` of audio had been buffered ahead

### Set D: aggressive seed plus dynamic drain timeout

Code values:

- `maxStartupBufferTargetMS: 20000`
- `maxResumeBufferTargetMS: 24000`
- `maxLowWaterTargetMS: 12000`
- `.extended` seed:
  - `startupBufferTargetMS: 12800`
  - `lowWaterTargetMS: 4800`
  - `resumeBufferTargetMS: 16000`
  - `chunkGapWarningMS: 900`
  - `scheduleGapWarningMS: 400`
- dynamic drain timeout:
  - minimum `5 seconds`
  - actual timeout = `queued audio at drain start + 3000 ms`

Validation path:

- rebuilt the Xcode worker with `xcodebuild`
- direct audible worker capture
- trace file:
  - `/tmp/speakswiftly-prose-tune-4/stderr.jsonl`

Observed result:

- `playback_started` logged:
  - `startup_buffer_target_ms: 12800`
  - `startup_buffered_audio_ms: 12800`
- `playback_finished` logged:
  - `rebuffer_event_count: 0`
  - `rebuffer_total_duration_ms: 0`
  - `starvation_event_count: 0`
  - `avg_inter_chunk_gap_ms: 189`
  - `avg_queued_audio_ms: 8734`
  - `max_queued_audio_ms: 12960`
  - `low_water_target_ms: 4800`
  - `resume_buffer_target_ms: 16000`
  - `time_to_preroll_ready_ms: 16715`
  - `time_from_preroll_ready_to_drain_ms: 57146`
- stdout ended with:
  - `playback_finished`
  - final `ok: true`
- conclusion:
  - this set met the pass target for the long prose forensic: no rebuffering and clean playback completion
  - the tradeoff is much higher startup latency, which is now explicit and traceable
