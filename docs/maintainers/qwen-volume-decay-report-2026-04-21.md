# Qwen Volume Decay Report

Date: 2026-04-21

## Scope

This report records the 2026-04-21 rerun of the active Qwen long-form volume
decay investigation across:

- the forked `mlx-audio-swift` regression suite on `tests/qwen3tts-decay-repro`
- the local `SpeakSwiftly` Qwen benchmark suite
- local `SpeakSwiftlyTesting` direct investigation commands and saved artifacts

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

The completed capture run wrote:

- `.local/volume-probes/capture-qwen-codes-2026-04-21T19-29-27Z.json`
- `.local/volume-probes/capture-qwen-codes-latest.json`

Run:

- profile: `probe-soft-femme-20260421`
- conditioning: `artifact`
- lane: `direct`
- model repo: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`

Captured payload highlights:

- generated code shape: `[1, 2048, 16]`
- generated code values: `32768`
- reference code shape: `[1, 16, 47]`
- reference text token shape: `[1, 11]`
- resolved language: `english`
- codec language ID: `2050`

Waveform summary:

| Metric | Value |
| --- | ---: |
| First RMS | 0.12379 |
| Last RMS | 0.05830 |
| RMS drop | -52.90% |
| Head RMS | 0.09045 |
| Tail RMS | 0.06752 |
| Tail/Head | 0.74651 |

Interpretation:

- The new capture path is working.
- We now have a replay-friendly artifact that preserves both the degraded
  waveform summary and the exact generated codec tensor from the same run.
- That closes the main instrumentation gap called out in the generated-code
  capture design note.

## Overall Readout

The current evidence points to the same shape as the earlier investigation:

- Qwen long-form tail decay is still reproducible locally.
- Prepared artifact conditioning helps but does not eliminate the decay.
- The direct-vs-streamed decode path is not the primary root cause.
- The new generated-code capture hook is now available and producing the exact
  codec payload we need for offline replay or narrower upstream comparisons.

## Recommended Next Steps

1. Use the saved `capture-qwen-codes-latest.json` artifact to build a narrow
   replay path in the fork so we can compare:
   - bounded decode from captured codes
   - warmed streaming decode from captured codes
   - any helper or convenience decode path used in SpeakSwiftly
2. Re-run `capture-qwen-codes` for `probe-clear-masc-20260421` so we have one
   replay artifact per probe profile, not just the soft-femme lane.
3. Add a smaller local matrix variant for daily reruns.
   The current `matrix-volume` shape is too expensive for frequent use; a
   reduced-profile or reduced-length variant would keep the evidence fresh
   without tying up the machine for a very long batch.
4. Compare the captured generated-code statistics across raw and artifact
   conditioning for the same profile.
   The next useful question is whether the bad tail comes from materially
   different generated codec sequences or from later decode/render behavior.
5. If replay from the captured codes still produces healthy tails upstream
   while the local retained file lane decays, focus next on SpeakSwiftly-owned
   behavior around request text shaping, runtime reuse, or the exact
   profile-materialization inputs rather than the codec decode step itself.
