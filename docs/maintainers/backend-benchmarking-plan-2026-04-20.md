# Backend Benchmarking Plan

## Status

This note started as a design plan for a repo-native benchmark suite. Parts of
that plan are now implemented, but the longer-term GPU profiling and deeper
playback-analysis story still remains incomplete.

What exists already:

- one shared benchmark harness under
  `Tests/SpeakSwiftlyTests/E2E/Benchmarks/BenchmarkSupport.swift`
- one opt-in backend-wide benchmark suite under
  `Tests/SpeakSwiftlyTests/E2E/Benchmarks/BackendBenchmarkE2ETests.swift`
- one opt-in Qwen resident benchmark suite under
  `Tests/SpeakSwiftlyTests/E2E/Qwen/QwenBenchmarkE2ETests.swift`
- per-request generation event metrics such as prefill time, generation time,
  tokens per second, and model-reported peak memory
- runtime memory snapshots for process CPU time, process memory footprint, and
  MLX memory usage
- playback summary and playback trace surfaces that already report queue-depth,
  rebuffer, starvation, and scheduling behavior
- one repo-maintenance benchmark wrapper under
  `scripts/repo-maintenance/run-benchmark.sh`

What does not exist yet:

- one separate Instruments-oriented GPU profiling wrapper
- one deeper retained playback-analysis report beyond the current per-request
  playback summary aggregates
- one broader benchmark history or comparison tool that diff-checks retained
  JSON summaries across runs

## Why This Exists

The package already has several useful performance surfaces, but they are still
split across different seams:

- Qwen has a dedicated benchmark suite
- playback quality shows up in playback summaries and trace events
- runtime resource usage shows up in runtime memory snapshots
- backend-generation timing shows up in generation event info

That is enough to support real benchmarking work. The missing piece is one
maintainer-owned benchmark model that asks every backend to do the same job and
stores the results in one comparable shape.

The immediate goal is not abstract benchmarking infrastructure for its own
future sake. The immediate goal is simpler:

- run the same standard speech-generation workload on `qwen3`,
  `chatterbox_turbo`, and `marvis`
- capture speed, throughput, memory pressure, CPU load, and playback stability
- see what changes between backends and between queued job positions
- keep the results durable enough that later optimization work is based on
  evidence instead of recollection

## The Standard Scenario

The benchmark suite should standardize around one package-owned scenario:

- one resident runtime per benchmark sample
- one selected backend
- one stored benchmark voice profile
- two live speech requests submitted back-to-back
- each request contains two paragraphs of fixed benchmark text
- the second request should be accepted while the first request is still active
  so the queue path is exercised on purpose

This is the core scenario because it exercises the part of the package that is
most likely to feel slow or unstable to a real caller:

- resident model warmup
- first live playback startup
- queue admission and waiting behavior
- overlap between generation and playback
- contention effects on the second request

The benchmark text should stay checked in and stable. Do not let ad hoc local
paragraphs drift between runs.

Recommended benchmark fixture shape:

- paragraph 1: normal prose with ordinary sentence structure
- paragraph 2: slightly denser prose with longer clauses and punctuation

That gives us something closer to real operator usage than a single short
sentence while avoiding a bizarre stress-only corpus that no one would actually
send to the package.

## Recommended Benchmark Lanes

The benchmark suite should be split into three lanes with different goals.

### Lane 1: Canonical Backend Comparison

This should become the default backend-comparison lane.

Shape:

- real models
- real resident runtime
- silent playback driver
- the standard two-job live scenario
- multiple iterations

Why it exists:

- it keeps backend-to-backend comparisons relatively stable
- it avoids host speaker routing and output-device quirks dominating the numbers
- it still exercises live generation, preroll, queueing, and drain behavior

This lane should be the source of truth for:

- timing regressions
- throughput changes
- process and MLX memory changes
- queue and playback stability changes

### Lane 2: Audible Stress Lane

This should run the same standard scenario, but through real audible playback.

Shape:

- real models
- real resident runtime
- audible playback enabled
- the standard two-job live scenario
- fewer iterations than the canonical lane

Why it exists:

- it answers the real-world question "does this sound stable on the machine"
- it catches rebuffering, underruns, and device-specific playback pain that a
  silent driver can hide
- it gives maintainers a deliberate path for "is the package usable right now"
  verification without confusing those runs with the cleaner backend-comparison
  numbers

Do not treat this lane as the primary regression baseline unless the package
later grows a more controlled audio-device test environment. It is important,
but it is noisier.

### Lane 3: Instruments and GPU Profiling Lane

This lane should stay separate from the ordinary benchmark suite.

Shape:

- one targeted scenario at a time
- Xcode-backed or Instruments-driven profiling session
- signposts and trace alignment when deeper diagnosis is needed

Why it exists:

- immediate package-side benchmark runs can tell us that one backend got slower
  or more memory-hungry
- they cannot fully answer where Apple-silicon GPU time went in a clean,
  per-test, package-native way

Use this lane when a canonical benchmark already proved that a regression
exists and we need to inspect CPU hot spots, Metal scheduling pressure, or
unified-memory pressure in more depth.

## Why XCTest Performance Metrics Are Not The Primary Plan

Apple's XCTest performance APIs can directly measure:

- elapsed wall time
- CPU activity
- memory deltas
- signposted regions

That is useful, but it is not the best primary fit here.

This package is already structured around worker-backed e2e flows, async event
streams, runtime-owned playback, and retained JSON benchmark output. A plain
`measure { ... }` block would not capture the package's real request lifecycle
as cleanly as the existing event-driven harness can.

More importantly, the GPU story is different:

- MetricKit exposes GPU metrics, including cumulative GPU time
- MetricKit reports are app-delivered and aggregate over time
- that makes MetricKit a poor primary source for one immediate package test run

So the practical design should be:

- package-native benchmark harness first
- XCTest performance metrics only if we later want one smaller host-process
  microbenchmark around a narrow operation
- Instruments or app-hosted profiling as the GPU-deep-dive lane

## Metrics To Capture

The benchmark result model should separate:

- suite-level settings
- per-sample host details
- per-request lifecycle metrics
- per-request generation metrics
- per-request resource metrics
- per-request playback metrics
- backend-level aggregate summaries

### Required Metrics

These should be present for every backend benchmark sample.

Timing:

- resident preload time
- queue admission time
- queue wait time
- time to acknowledged
- time to started
- time to first token
- time to first audio chunk
- time to buffering
- time to preroll ready
- time to playback finished
- total completion time

Generation:

- observed token count
- prompt token count when available
- generation token count when available
- prefill time when available
- generation time when available
- tokens per second when available

Runtime resource usage:

- process resident bytes before and after request
- process physical footprint bytes before and after request
- process user CPU time before and after request
- process system CPU time before and after request
- MLX active memory before and after request
- MLX cache memory before and after request
- MLX peak memory after request

Playback stability:

- startup buffered audio
- time to first chunk
- time to preroll ready
- min queued audio
- max queued audio
- average queued audio
- queue depth sample count
- rebuffer event count
- total rebuffer duration
- longest rebuffer duration
- starvation event count
- max and average inter-chunk gap
- max and average schedule gap

### Optional Metrics

These should be recorded when the backend or lane can support them cleanly.

- generated artifact ID for retained file outputs
- model-native peak memory usage from generation info
- host audio-device metadata for audible runs
- signpost-linked region durations for Instruments-oriented captures

Optional metrics should be explicit `null` values in JSON, not silently missing
fields, so later comparison code can tell the difference between "not provided"
and "forgotten in this schema version."

## How To Treat The Second Job

The second request is not just another sample. It is the most important part of
the scenario.

For each benchmark sample, store metrics for:

- job 1
- job 2
- sample-level aggregate comparisons

The suite should call out at least these derived values:

- job 2 queue wait minus job 1 queue wait
- job 2 first-audio latency minus job 1 first-audio latency
- job 2 completion time minus job 1 completion time
- job 2 rebuffer count minus job 1 rebuffer count

That makes the queued-request tax obvious instead of forcing maintainers to
infer it from two large JSON blobs.

## Expected Backend Differences

The benchmark suite should not force every backend into fake symmetry.

`qwen3` can already surface richer generation info and should continue doing so.

`chatterbox_turbo` and `marvis` may not currently produce the same info payload
shape on every run. That is acceptable as long as:

- the shared benchmark schema keeps the fields stable
- optional metrics are recorded explicitly when unavailable
- the suite still captures the common timing, process-resource, and playback
  metrics for all backends

The benchmark model should prefer honest partial comparison over flattening the
backend differences into misleading generic numbers.

## Result Storage

The current Qwen benchmark already writes JSON summaries under `.local/benchmarks`.
The generalized backend suite should keep that storage root and adopt a stable
family naming pattern such as:

- `backend-live-benchmark-<ISO8601>.json`
- `backend-live-benchmark-latest.json`
- `backend-live-audible-benchmark-<ISO8601>.json`
- `backend-live-audible-benchmark-latest.json`

The summary should record:

- schema version
- generation timestamp
- host machine description
- backend list
- iteration count
- playback mode
- benchmark text fixture identity
- profile identity
- all sample results
- aggregate reports per backend

Keep the schema versioned so comparison tooling can evolve without corrupting
older retained runs.

## Near-Term Follow-Up

Track the Qwen long-form volume-decay regression in the dedicated maintainer
note:

- `docs/maintainers/qwen-volume-decay-investigation-2026-04-21.md`

Keep the benchmarking note focused on benchmark coverage, storage, and lane
design. Keep the decode-path investigation, retained loudness evidence, and
Qwen-specific follow-up steps in the dedicated investigation document.

## Suggested Test Layout

The current Qwen benchmark suite proves the basic shape already works. The next
step should be to generalize it instead of creating a second unrelated harness.

Recommended test layout:

- `Tests/SpeakSwiftlyTests/E2E/Benchmarks/BackendBenchmarkE2ETests.swift`
- `Tests/SpeakSwiftlyTests/E2E/Benchmarks/BackendBenchmarkSupport.swift`
- `Tests/SpeakSwiftlyTests/E2E/Support/SpeakSwiftlyE2EPolicy.swift`
  extended with backend-benchmark environment gates

Recommended policy flags:

- `SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E=1`
- `SPEAKSWIFTLY_BACKEND_BENCHMARK_ITERATIONS=<n>`
- `SPEAKSWIFTLY_BACKEND_BENCHMARK_AUDIBLE=1`

Recommended suite tags:

- `.e2e`
- `.benchmark`
- backend-specific tags when useful

Keep the suite serialized. This repository already treats heavy worker-backed
model tests as strictly one-at-a-time work.

## Suggested Implementation Slices

### Slice 1: Generalize The Existing Qwen Benchmark Harness

Goal:

- extract shared benchmark support from the current Qwen suite
- preserve the current Qwen lane while moving common code into reusable support

What to move into shared support:

- benchmark runtime bootstrapping
- request lifecycle collection
- generation metric collection
- benchmark summary writing
- host and settings capture

### Slice 2: Add A Shared Two-Job Live Scenario

Goal:

- replace the current one-request Qwen benchmark shape with the standard
  two-queued-job scenario

Important rule:

- submit job 2 while job 1 is still active
- do not wait for job 1 to finish first

That is the only way the benchmark can honestly claim it measures queue
behavior.

### Slice 3: Add Playback Summary Capture Per Request

Goal:

- attach playback summary data to each benchmarked request

This is the slice that makes the benchmark useful for "speed" and "did the user
actually hear stable audio" at the same time.

### Slice 4: Widen The Suite To All Backends

Goal:

- run the same scenario against `.qwen3`, `.chatterboxTurbo`, and `.marvis`

Do not wait for every backend to surface identical model-native metrics before
landing this slice. The comparison is still valuable with the shared timing,
process-resource, and playback metrics.

### Slice 5: Add The Audible Lane

Goal:

- add a deliberate audible variant of the same suite

Keep this lane opt-in and lower-iteration.

### Slice 6: Add Repo-Maintenance Commands

Goal:

- make the benchmark suite easy to discover and re-run

Recommended shape:

- one repo-maintenance wrapper for canonical backend comparison
- one repo-maintenance wrapper or flag for audible backend comparison

## GPU Strategy

The benchmark suite should report what it can measure directly now, and it
should be explicit about the GPU boundary.

What the package can measure directly today:

- MLX memory state
- process CPU time
- process memory footprint
- end-to-end timing
- playback stability

What the package should not pretend it already has:

- clean immediate per-sample GPU time per request from a plain package test

If we need deeper GPU visibility, the next honest step is:

- add or reuse signposts around resident preload, first token, first audio
  chunk, preroll ready, and playback drain
- line those signposts up in Instruments
- keep that workflow documented as a profiling lane, not as the ordinary
  backend benchmark suite

## Recommended Outcome

The best immediate path is:

1. generalize the current Qwen benchmark harness
2. standardize on the two-queued-live-job scenario
3. make the silent canonical lane the default backend-comparison source of truth
4. add the audible lane as a second opt-in benchmark story
5. keep GPU-deep-dive work in a separate profiling workflow

That gives the package one benchmark system that matches the real runtime job
it is doing for Gale:

- speak two substantial requests
- queue the second one behind the first
- show how fast each backend starts speaking
- show how hard each backend pushes the machine
- show whether playback stays stable while it happens
