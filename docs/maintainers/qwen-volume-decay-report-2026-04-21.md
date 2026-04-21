# Qwen Volume Decay Report

Date: 2026-04-21

## Scope

This report records the 2026-04-21 rerun of the active Qwen long-form volume
decay investigation across:

- the forked `mlx-audio-swift` regression suite on `tests/qwen3tts-decay-repro`
- the local `SpeakSwiftly` Qwen benchmark suite
- local `SpeakSwiftlyTesting` direct investigation commands and saved artifacts
- four local `SpeakSwiftlyTesting` generated-code captures
- four local `SpeakSwiftlyTesting` replays of saved generated-code artifacts
- three local `SpeakSwiftlyTesting` generated-code comparisons

Operator-observed symptom note:

- The long-form failure is not only a tail-loudness issue. Gale also reports
  that the generated speech tends to get higher pitched and faster in cadence
  as generation continues. That broader prosody drift may be related to the
  same underlying regime shift and should be treated as part of the active
  symptom cluster, not as a separate unrelated issue.
- The exact symptom mix is also inconsistent from run to run. Loudness decay,
  pitch rise, cadence acceleration, and glitchier delivery all seem to be
  common manifestations, but not every failing run presents the same blend.
  The working model should therefore stay open to multiple smaller issues that
  compound in a partly non-deterministic way rather than assuming one neat
  single defect with one stable presentation.

The live local SpeakSwiftly service was unloaded first with:

```sh
launchctl bootout gui/501/com.gaelic-ghost.speak-swiftly-server
```

That left the machine free for serialized MLX-backed validation.

## Commands Run

### Forked dependency regression lane

```sh
xcodebuild build-for-testing \
  -scheme MLXAudio-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/derived-data/qwen-decay

xcodebuild test-without-building \
  -scheme MLXAudio-Package \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .local/derived-data/qwen-decay \
  -only-testing:'MLXAudioTests/Qwen3TTSDecodeRegressionTests'
```

Notes:

- Plain `swift test --filter conditionedGeneratedCodesStayLevelAcrossDecodePaths`
  did not provide a usable result because the SwiftPM lane failed before test
  execution with `Failed to load the default metallib`.
- The Xcode-backed lane was required to get real Qwen coverage.

### Local package benchmark lane

```sh
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1 \
  swift test --filter QwenBenchmarkE2ETests
```

### Local direct investigation lanes

```sh
swift run SpeakSwiftlyTesting compare-volume \
  --profile probe-soft-femme-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --repeat 16 \
  --conditioning raw

swift run SpeakSwiftlyTesting capture-qwen-codes \
  --profile probe-soft-femme-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --conditioning artifact \
  --repeat 16 \
  --lane direct

swift run SpeakSwiftlyTesting capture-qwen-codes \
  --profile probe-clear-masc-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --conditioning artifact \
  --repeat 16 \
  --lane direct

swift run SpeakSwiftlyTesting capture-qwen-codes \
  --profile probe-soft-femme-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --conditioning raw \
  --repeat 16 \
  --lane direct

swift run SpeakSwiftlyTesting capture-qwen-codes \
  --profile probe-clear-masc-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --conditioning raw \
  --repeat 16 \
  --lane direct

swift run SpeakSwiftlyTesting replay-qwen-codes \
  --artifact-file .local/volume-probes/capture-qwen-codes-latest.json

swift run SpeakSwiftlyTesting replay-qwen-codes \
  --artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T20-52-42Z.json

swift run SpeakSwiftlyTesting replay-qwen-codes \
  --artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T20-55-33Z.json

swift run SpeakSwiftlyTesting compare-qwen-codes \
  --left-artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T19-29-27Z.json \
  --right-artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T20-40-02Z.json

swift run SpeakSwiftlyTesting compare-qwen-codes \
  --left-artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T20-52-42Z.json \
  --right-artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T19-29-27Z.json

swift run SpeakSwiftlyTesting compare-qwen-codes \
  --left-artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T20-55-33Z.json \
  --right-artifact-file .local/volume-probes/capture-qwen-codes-2026-04-21T20-40-02Z.json

swift run SpeakSwiftlyTesting analyze-audio-prosody \
  --file /var/folders/hw/pp57v7m145vfh7517y14t_zr0000gn/T/SpeakSwiftlyTesting/probe-soft-femme-20260421-replay-warmed-streaming.wav \
  --window-seconds 0.5

swift run SpeakSwiftlyTesting analyze-audio-prosody \
  --file /var/folders/hw/pp57v7m145vfh7517y14t_zr0000gn/T/SpeakSwiftlyTesting/probe-clear-masc-20260421-replay-warmed-streaming.wav \
  --window-seconds 0.5
```

Attempted but intentionally stopped:

```sh
swift run SpeakSwiftlyTesting matrix-volume \
  --profile probe-soft-femme-20260421 \
  --profile probe-clear-masc-20260421 \
  --profile-root "$HOME/Library/Application Support/SpeakSwiftly" \
  --short-repeat 4 \
  --long-repeat 14 \
  --iterations 1
```

The matrix sweep was proving to be a very large multi-generation batch with no
useful interim checkpoints. Because the upstream suite already covered both
profiles and both conditioning paths in one pass, it was stopped in favor of
capturing a report from the completed evidence set.

## Results

### 1. Forked `mlx-audio-swift` regression suite

The full `Qwen3TTSDecodeRegressionTests` suite passed.

Passing tests:

- `cachedEncodedSpeechTailDoesNotCollapseRelativeToBoundedDecode`
- `streamingDecodeTailDoesNotCollapseRelativeToBoundedDecode`
- `conditionedGeneratedCodesStayLevelAcrossDecodePaths`
- `speakSwiftlyConditioningArtifactProbeCapturesProfileDecay`
- `speakSwiftlyProfileMatrixLogsArtifactAndLengthSensitivity`

Key observations from the suite output:

- `conditionedGeneratedCodesStayLevelAcrossDecodePaths` passed with
  `helper tail gain ~= 0.97084` and `warmed tail gain ~= 0.97084`.
  The direct helper and warmed streaming decode paths stayed near the bounded
  decode tail level instead of collapsing catastrophically.
- `speakSwiftlyConditioningArtifactProbeCapturesProfileDecay` passed for
  `probe-clear-masc-20260421` with:
  - raw tail ratio `0.88136`
  - artifact tail ratio `0.80824`
- `speakSwiftlyProfileMatrixLogsArtifactAndLengthSensitivity` passed and logged:
  - `probe-soft-femme-20260421 [short]`
    - raw tail ratio `0.59495`
    - artifact tail ratio `0.62984`
  - `probe-soft-femme-20260421 [long]`
    - raw tail ratio `0.81795`
    - artifact tail ratio `0.88948`
  - `probe-clear-masc-20260421 [short]`
    - raw tail ratio `0.71236`
    - artifact tail ratio `0.80526`
  - `probe-clear-masc-20260421 [long]`
    - raw tail ratio `0.83767`
    - artifact tail ratio `0.91907`

Interpretation:

- The fork-side regression evidence still says the worst collapse is not a
  simple decode-path bug.
- Stored artifact conditioning generally improves tail retention for the
  profile-matrix probes, especially on the local long-form reproductions.

### 2. Local `QwenBenchmarkE2ETests`

The benchmark test passed and wrote:

- `.local/benchmarks/qwen-resident-benchmark-2026-04-21T19-09-51Z.json`
- `.local/benchmarks/qwen-resident-benchmark-latest.json`

Extracted summary:

| Strategy | Preload | File complete | File first audio | Live complete | Live first audio | Live preroll | Tokens/s | Peak memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `legacy_raw` | 1409.95 ms | 17391.04 ms | 374.42 ms | 16540.18 ms | 207.75 ms | 864.10 ms | 11.91 | 8.81 GB |
| `prepared_conditioning` | 945.65 ms | 16076.03 ms | 189.31 ms | 16673.17 ms | 193.24 ms | 858.58 ms | 11.95 | 8.81 GB |

Interpretation:

- Prepared conditioning materially improves the retained file lane:
  - preload improved by about `464 ms`
  - file first-audio improved by about `185 ms`
  - file completion improved by about `1.3 s`
- Live playback timing is effectively neutral between the two strategies.
- Throughput and peak memory are essentially unchanged.

### 3. Local `compare-volume` probe

The completed local compare run wrote:

- `.local/volume-probes/compare-volume-2026-04-21T19-15-36Z.json`
- `.local/volume-probes/compare-volume-latest.json`

Run:

- profile: `probe-soft-femme-20260421`
- conditioning: `raw`
- text length: `7678` characters / `1184` words

Extracted summaries:

| Lane | First RMS | Last RMS | Drop | Head RMS | Tail RMS | Tail/Head |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Streamed retained file | 0.12945 | 0.07001 | -45.92% | 0.08529 | 0.06260 | 0.73396 |
| Direct decode | 0.09328 | 0.05277 | -43.42% | 0.07483 | 0.05519 | 0.73750 |

Interpretation:

- The local soft-femme profile still shows real long-form tail decay in both
  the retained streamed file lane and the direct decode lane.
- The streamed-vs-direct difference is small:
  - tail/head differs by only about `0.0035`
  - drop percentage differs by only about `2.49` points
- That matches the upstream conclusion that the severe local symptom is not
  explained by the direct-vs-streamed decode path alone.

### 4. Local generated-code capture

The completed capture runs wrote:

- `.local/volume-probes/capture-qwen-codes-2026-04-21T19-29-27Z.json`
- `.local/volume-probes/capture-qwen-codes-2026-04-21T20-40-02Z.json`
- `.local/volume-probes/capture-qwen-codes-2026-04-21T20-52-42Z.json`
- `.local/volume-probes/capture-qwen-codes-2026-04-21T20-55-33Z.json`
- `.local/volume-probes/capture-qwen-codes-latest.json`

Common capture shape:

- conditioning: `artifact`
- lane: `direct`
- model repo: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
- generated code shape: `[1, 2048, 16]`
- generated code values: `32768`
- reference text token shape: `[1, 11]`
- resolved language: `english`
- codec language ID: `2050`

Per-run capture summaries:

| Profile | Conditioning | Reference code shape | First RMS | Last RMS | Drop | Head RMS | Tail RMS | Tail/Head |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `probe-soft-femme-20260421` | `artifact` | `[1, 16, 47]` | 0.12379 | 0.05830 | -52.90% | 0.09045 | 0.06752 | 0.74651 |
| `probe-soft-femme-20260421` | `raw` | `[1, 16, 47]` | 0.10787 | 0.06973 | -35.36% | 0.08932 | 0.06628 | 0.74207 |
| `probe-clear-masc-20260421` | `artifact` | `[1, 16, 49]` | 0.13393 | 0.10120 | -24.44% | 0.11398 | 0.10482 | 0.91959 |
| `probe-clear-masc-20260421` | `raw` | `[1, 16, 49]` | 0.11999 | 0.08783 | -26.80% | 0.09045 | 0.07892 | 0.87257 |

Interpretation:

- The new capture path is working on both investigation profiles.
- We now have replay-friendly artifacts that preserve both the waveform summary
  and the exact generated codec tensor across both profiles and both
  conditioning strategies.
- That closes the main instrumentation gap called out in the generated-code
  capture design note.

### 5. Local replay from the saved generated-code artifacts

The completed local replay runs wrote:

- `.local/volume-probes/replay-qwen-codes-2026-04-21T19-39-35Z.json`
- `.local/volume-probes/replay-qwen-codes-2026-04-21T20-40-55Z.json`
- `.local/volume-probes/replay-qwen-codes-2026-04-21T21-09-43Z.json`
- `.local/volume-probes/replay-qwen-codes-2026-04-21T21-10-20Z.json`
- `.local/volume-probes/replay-qwen-codes-latest.json`

Replay inputs:

- conditioning: `artifact`
- model repo: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`

Available local replay lanes today:

- pure bounded decode from the captured codes
- helper decode via `debugDecodeChunk(...)`
- plain streaming decode from the captured generated codes
- reference-warmed streaming decode from the same captured generated codes

Soft-femme replay input:

- source artifact: `.local/volume-probes/capture-qwen-codes-2026-04-21T19-29-27Z.json`
- profile: `probe-soft-femme-20260421`

Representative summaries:

| Lane | First RMS | Last RMS | Drop | Head RMS | Tail RMS | Tail/Head |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Source retained capture | 0.12379 | 0.05830 | -52.90% | 0.09045 | 0.06752 | 0.74651 |
| Bounded decode | 0.12379 | 0.05612 | -54.66% | 0.08981 | 0.06546 | 0.72884 |
| Helper decode | 0.12379 | 0.05830 | -52.90% | 0.09045 | 0.06752 | 0.74651 |
| Plain streaming replay | 0.12336 | 0.05830 | -52.74% | 0.09025 | 0.06752 | 0.74822 |
| Warmed streaming replay | 0.12379 | 0.05830 | -52.90% | 0.09045 | 0.06752 | 0.74652 |

Interpretation:

- The full local replay triangle still suggests the preserved bad tail is not
  introduced by a dramatic divergence between bounded, helper, and warmed
  streaming decode paths.
- The bounded lane is somewhat worse on this capture, but only modestly:
  - bounded tail/head `0.72884`
  - helper tail/head `0.74651`
  - warmed streaming tail/head `0.74652`
- For this saved soft-femme artifact, the degraded envelope appears to be
  largely present before those decode-path choices diverge.

Clear-masc replay input:

- source artifact: `.local/volume-probes/capture-qwen-codes-2026-04-21T20-40-02Z.json`
- profile: `probe-clear-masc-20260421`

Representative summaries:

| Lane | First RMS | Last RMS | Drop | Head RMS | Tail RMS | Tail/Head |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Source retained capture | 0.13393 | 0.10120 | -24.44% | 0.11398 | 0.10482 | 0.91959 |
| Bounded decode | 0.13393 | 0.10111 | -24.50% | 0.11395 | 0.10499 | 0.92133 |
| Helper decode | 0.13393 | 0.10120 | -24.44% | 0.11398 | 0.10482 | 0.91959 |
| Plain streaming replay | 0.13969 | 0.10146 | -27.37% | 0.11581 | 0.10508 | 0.90729 |
| Warmed streaming replay | 0.13393 | 0.10120 | -24.44% | 0.11399 | 0.10482 | 0.91955 |

Interpretation:

- The clear-masc artifact stays healthy across the same four replay lanes.
- The warmed, helper, and retained summaries are nearly identical.
- The plain streaming replay is slightly worse on tail/head than the other
  lanes, but not in a way that resembles the soft-femme collapse.
- Taken together with the soft-femme replay, the local replay harness now shows
  profile-sensitive behavior that is already present in the captured sequence
  or earlier request setup, not a single replay decode path introducing the
  entire failure.

Soft-femme raw replay input:

- source artifact: `.local/volume-probes/capture-qwen-codes-2026-04-21T20-52-42Z.json`
- profile: `probe-soft-femme-20260421`
- conditioning: `raw`

Representative summaries:

| Lane | First RMS | Last RMS | Drop | Head RMS | Tail RMS | Tail/Head |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Source retained capture | 0.10787 | 0.06973 | -35.36% | 0.08932 | 0.06628 | 0.74207 |
| Bounded decode | 0.10787 | 0.06718 | -37.73% | 0.08886 | 0.06479 | 0.72917 |
| Helper decode | 0.10787 | 0.06973 | -35.36% | 0.08932 | 0.06628 | 0.74207 |
| Plain streaming replay | 0.10971 | 0.06977 | -36.40% | 0.08960 | 0.06632 | 0.74014 |
| Warmed streaming replay | 0.10787 | 0.06973 | -35.36% | 0.08932 | 0.06629 | 0.74216 |

Interpretation:

- The raw soft-femme artifact behaves just like the artifact-conditioned
  soft-femme artifact: the degraded tail is already present in the captured
  run, and replay does not introduce a dramatically different outcome.
- Bounded decode is again slightly worse than the helper and warmed streaming
  lanes, but only modestly.

Clear-masc raw replay input:

- source artifact: `.local/volume-probes/capture-qwen-codes-2026-04-21T20-55-33Z.json`
- profile: `probe-clear-masc-20260421`
- conditioning: `raw`

Representative summaries:

| Lane | First RMS | Last RMS | Drop | Head RMS | Tail RMS | Tail/Head |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Source retained capture | 0.11999 | 0.08783 | -26.80% | 0.09045 | 0.07892 | 0.87257 |
| Bounded decode | 0.11999 | 0.08728 | -27.26% | 0.09062 | 0.07894 | 0.87111 |
| Helper decode | 0.11999 | 0.08783 | -26.80% | 0.09045 | 0.07892 | 0.87257 |
| Plain streaming replay | 0.11923 | 0.08803 | -26.16% | 0.09071 | 0.07908 | 0.87181 |
| Warmed streaming replay | 0.11999 | 0.08783 | -26.80% | 0.09045 | 0.07892 | 0.87258 |

Interpretation:

- The raw clear-masc artifact also stays healthy across the replay triangle.
- The raw replay control therefore matches the artifact replay control on both
  profiles: soft-femme remains the degraded case and clear-masc remains the
  healthier case, with only small bounded-vs-helper-vs-streaming differences.

### 6. Local generated-code comparison

The comparison runs wrote:

- `.local/volume-probes/compare-qwen-codes-2026-04-21T20-49-57Z.json`
- `.local/volume-probes/compare-qwen-codes-2026-04-21T20-52-52Z.json`
- `.local/volume-probes/compare-qwen-codes-2026-04-21T20-55-40Z.json`
- `.local/volume-probes/compare-qwen-codes-latest.json`

Soft-femme artifact versus clear-masc artifact:

| Metric | Value |
| --- | ---: |
| Soft-femme tail/head | 0.74651 |
| Clear-masc tail/head | 0.91959 |
| Soft-femme repeat ratio | 0.00727 |
| Clear-masc repeat ratio | 0.00705 |
| Soft-femme head/tail shift mean | 0.59222 |
| Clear-masc head/tail shift mean | 0.59198 |
| Cross-artifact exact match ratio | 0.00101 |
| Cross-artifact distinct-set Jaccard mean | 0.44270 |
| Cross-artifact distribution shift mean | 0.53296 |

Soft-femme raw versus artifact:

| Metric | Raw | Artifact |
| --- | ---: | ---: |
| Tail/Head | 0.74207 | 0.74651 |
| Repeat ratio | 0.00693 | 0.00727 |
| Distinct mean per codebook | 1076.88 | 1082.38 |
| Head/tail shift mean | 0.59052 | 0.59222 |

Cross-run comparison:

- exact match ratio `0.00070`
- distinct-set Jaccard mean `0.48826`
- distribution shift mean `0.47165`

Clear-masc raw versus artifact:

| Metric | Raw | Artifact |
| --- | ---: | ---: |
| Tail/Head | 0.87257 | 0.91959 |
| Repeat ratio | 0.00910 | 0.00705 |
| Distinct mean per codebook | 1084.88 | 1090.00 |
| Head/tail shift mean | 0.59039 | 0.59198 |

Cross-run comparison:

- exact match ratio `0.00085`
- distinct-set Jaccard mean `0.47112`
- distribution shift mean `0.48947`

Interpretation:

- The new `compare-qwen-codes` helper is working and gives us a stable
  artifact-to-artifact summary surface.
- Across soft-femme and clear-masc, the coarse generated-code statistics remain
  surprisingly similar even though the retained waveform outcomes are very
  different.
- Across raw and artifact conditioning for the same profile, the generated code
  streams are still different runs, but the high-level token-shape metrics stay
  very close.
- That means we still do not have a simple codec-level smoking gun like
  "soft-femme collapses into obvious repetition" or "artifact conditioning
  massively changes the coarse token distribution."
- The evidence now points more strongly toward a narrower sequence-level,
  conditioning-content, or request-setup difference than toward a broad decode
  or distribution-collapse explanation.

Narrower codebook-level read from the updated helper:

- The enhanced `compare-qwen-codes` output now surfaces the most shifted
  codebooks instead of only whole-run averages.
- In the first artifact-vs-artifact rerun, both profiles showed codebook `15`
  among their highest head-vs-tail internal shift lanes, while the strongest
  cross-artifact divergence showed up at codebooks `06`, `07`, and `04`.
- That is useful enough to guide a more focused next step, but it is not yet a
  clean discriminator between "bad soft-femme" and "healthy clear-masc" on its
  own.
- The symptom note about rising pitch and faster cadence now matters even more
  here, because a small set of higher-level prosody-driving codebooks drifting
  over time would fit that perceptual pattern better than a pure amplitude-only
  explanation.

Quarter-level codebook follow-up:

- The helper now also logs quarter-by-quarter snapshots for the most shifted
  codebooks in each artifact.
- In the first artifact-vs-artifact rerun, codebook `15` stayed a leading
  head-vs-tail drift lane for both profiles, but its quarter snapshots did not
  show a dramatic late-run cliff by themselves.
- The strongest cross-artifact divergence still came from codebooks `06`, `07`,
  and `04`, while the per-profile internal leaders differed slightly after
  codebook `15`.
- That means the next best move is probably not "look for one quarter where
  everything suddenly collapses." It is to compare a small set of suspect
  codebooks against audible prosody measures or against finer-grained sequence
  motifs in the later quarters.

## Overall Readout

The current evidence points to the same shape as the earlier investigation:

- Qwen long-form tail decay is still reproducible locally.
- Prepared artifact conditioning helps but does not eliminate the decay.
- The direct-vs-streamed decode path is not the primary root cause.
- The new generated-code capture hook is now available and producing the exact
  codec payload we need for offline replay or narrower upstream comparisons.
- The soft-femme saved bad run kept the same degraded tail shape across
  bounded, helper, and both streaming replay variants.
- The clear-masc saved run stayed healthy across those same replay lanes, which
  makes the profile-specific divergence even more likely to be upstream of the
  replay decode split.
- The new generated-code comparisons did not reveal an obvious coarse token
  collapse signature. Soft-femme, clear-masc, raw, and artifact runs all stay
  in roughly the same band for repeat ratio, distinct-token spread, and
  head-versus-tail distribution shift.
- The new raw replay controls match the artifact replay result: profile
  sensitivity persists across both conditioning strategies, and the replay
  decode split still is not the primary source of the collapse.
- The observed symptom cluster now includes loudness decay, pitch rise, and
  cadence acceleration over longer generations, which makes a broader prosody
  drift more plausible than a volume-only defect.
- The symptom presentation is also inconsistent enough that the current best
  read is "compound and partly non-deterministic" rather than "one bug with one
  canonical signature."
- The first quarter-level codebook snapshots did not reveal an obvious single
  late-quarter cliff, so the next analysis likely needs finer-grained
  time-local or prosody-aware measurements rather than broader quarter averages.

### 7. First audio-side prosody summary pass

The replay helper now emits a first-pass prosody summary alongside the existing
volume summary, using:

- a coarse pitch proxy from short-frame autocorrelation on voiced windows
- a coarse pulse-rate proxy from smoothed envelope peak density

First artifact replay comparison:

| Profile | Lane | Head Pitch Hz | Tail Pitch Hz | Tail/Head Pitch | Head Pulse Rate | Tail Pulse Rate | Tail/Head Pulse |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `probe-soft-femme-20260421` | `warmed_streaming_decode` | 197.77 | 197.47 | 0.99848 | 3.80 | 3.51 | 0.92417 |
| `probe-clear-masc-20260421` | `warmed_streaming_decode` | 166.64 | 166.30 | 0.99797 | 4.05 | 3.80 | 0.93910 |

Additional top-line readouts:

- soft-femme warmed streaming first/last pitch proxy: `218.39 Hz` -> `182.55 Hz`
- clear-masc warmed streaming first/last pitch proxy: `198.15 Hz` -> `177.37 Hz`
- soft-femme warmed streaming first/last pulse proxy: `4.50` -> `3.26` per second
- clear-masc warmed streaming first/last pulse proxy: `4.50` -> `2.17` per second

Interpretation:

- This first prosody pass does not reproduce the reported pitch-up / faster
  cadence symptom directly.
- The crude proxy actually trends slightly downward on both profiles, and the
  pulse-rate proxy also softens rather than accelerating.
- That does not mean the perceptual report is wrong. It means this first proxy
  is likely too blunt for the exact symptom or is measuring a different aspect
  of the speech than what the ear is picking up.
- The audio-side path is still useful because it gives the investigation a
  place to improve prosody measurements without guessing entirely from codebook
  drift.

### 8. Finer 0.5-second prosody spot-check with direct WAV analysis

The new `analyze-audio-prosody` helper can also inspect one saved WAV directly
without rerunning Qwen generation. That gave us a cheaper way to recheck the
warm-replay audio after one slightly glitchy listening pass.

Matched warmed-streaming replay WAVs:

| Profile | Head Pitch Hz | Tail Pitch Hz | Tail/Head Pitch | Head Pulse Rate | Tail Pulse Rate | Tail/Head Pulse |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `probe-soft-femme-20260421` | 195.77 | 192.95 | 0.98560 | 3.12 | 3.11 | 0.99586 |
| `probe-clear-masc-20260421` | 165.55 | 163.71 | 0.98892 | 3.32 | 3.60 | 1.08434 |

Additional direct-analysis readouts:

- soft-femme first/last pitch proxy: `260.37 Hz` -> `172.82 Hz`
- clear-masc first/last pitch proxy: `152.16 Hz` -> `225.78 Hz`
- soft-femme first/last pulse proxy: `6.00` -> `2.94` per second
- clear-masc first/last pulse proxy: `0.00` -> `2.94` per second
- soft-femme quarter pitch medians: `195.77`, `198.42`, `188.82`, `192.95`
- clear-masc quarter pitch medians: `165.55`, `177.04`, `169.33`, `163.71`
- soft-femme quarter pulse medians: `3.12`, `3.27`, `3.17`, `3.11`
- clear-masc quarter pulse medians: `3.32`, `3.63`, `3.68`, `3.60`

Interpretation:

- The finer 0.5-second spot-check still does not cleanly reproduce the
  operator-reported pitch-up / faster-cadence symptom on the degraded
  soft-femme run.
- The quarter medians stay fairly flat on both profiles, and soft-femme still
  does not show a clear late-run acceleration signal in this proxy.
- Clear-masc shows a modest tail-ward increase in the pulse-rate proxy even
  though it is the healthier loudness case, which is another sign that this
  proxy is not yet isolating the audible failure mode cleanly.
- The first/last numbers swing more than the quarter medians, especially on
  clear-masc, which suggests the current estimator is sensitive to local
  windows and should not be over-read as a literal prosody contour yet.
- This makes the next measurement task clearer: improve the prosody estimator
  itself rather than keep paying for more model reruns through the same coarse
  proxy.

## Recommended Next Steps

1. Go deeper than coarse token-distribution summaries.
   The next useful question is whether the bad soft-femme run differs in a
   narrower way, such as per-codebook trajectory, token bigrams, tail-localized
   motifs, or alignment against the reference-code prefix rather than in
   whole-run uniqueness or repeat ratios.
   The new helper can already point at the most shifted codebooks; the next
   pass should either graph those codebooks on a finer time grid than quarters
   or correlate them against an actual audio-side pitch/cadence summary so the
   token analysis can be compared to the reported perceptual drift directly.
2. Add a smaller local matrix variant for daily reruns.
   The current `matrix-volume` shape is too expensive for frequent use; a
   reduced-profile or reduced-length variant would keep the evidence fresh
   without tying up the machine for a very long batch.
3. If replay from the captured codes still produces healthy tails upstream
   while the local retained file lane decays, focus next on SpeakSwiftly-owned
   behavior around request text shaping, runtime reuse, or the exact
   profile-materialization inputs rather than the codec decode step itself.
4. Replace the first-pass prosody proxy with a better-targeted measurement.
   The replay-level and direct-WAV spot checks are both useful scaffolds, but
   neither one cleanly captures the reported pitch-up / faster-cadence
   symptom. The next version should favor a more stable F0 contour and a
   better speaking-rate estimate rather than more reruns through the same
   proxy.
