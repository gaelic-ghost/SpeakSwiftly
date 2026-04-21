# Qwen Volume Decay Investigation

## Purpose

This note pulls the Qwen long-form loudness-decay follow-up out of the broader
benchmarking plan so the issue has one dedicated maintainer-facing home.

The working symptom is simple: some long-form Qwen3-TTS generations lose a
large amount of energy as the utterance continues, and the fade shows up in
retained output too, not only in live playback.

## What We Have Already Looked At

### Repo-side audio handling

These package paths were already inspected first so we could avoid blaming the
local audio path too early:

- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver+SampleShaping.swift`
- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver+PlaybackLifecycle.swift`
- `Sources/SpeakSwiftly/Playback/AudioPlaybackDriver.swift`
- `Sources/SpeakSwiftly/Generation/FileGenerationOperations.swift`
- `Sources/SpeakSwiftly/Generation/ModelClients+Speech.swift`

What that inspection established:

- playback shaping is intentionally narrow: clamp to `[-1, 1]`, boundary
  smoothing, and a first-chunk fade-in only
- retained file generation concatenates emitted float chunks and writes WAV
- there is no broad package-side loudness normalization or progressive
  attenuation pass that would explain a sustained fade over time

The current evidence still points upstream toward Qwen generation or decode
behavior rather than local playback shaping.

### Existing probes and measurements

The repo already has two useful long-form probes:

- `swift run SpeakSwiftlyTesting volume-probe ...`
- `swift run SpeakSwiftlyTesting compare-volume ...`

Those probes were used to compare retained streamed output against direct
non-stream Qwen decode using the same stored conditioning.

Observed results from the earlier pass:

- `probe-soft-femme-20260421`: first RMS `0.09940`, last RMS `0.06152`, drop
  `-38.10%`
- `probe-clear-masc-20260421`: first RMS `0.15233`, last RMS `0.00764`, drop
  `-94.98%`
- live `default-femme` before dependency update: streamed drop `-52.32%`,
  direct drop `-38.85%`
- live `default-femme` after `mlx-audio-swift v0.7.0`: streamed drop
  `-53.58%`, direct drop `-54.85%`

What that already told us:

- the decay is real
- it persists in retained output, so it is not just an audible playback quirk
- it is voice/profile sensitive
- updating to `mlx-audio-swift 0.7.0` did not fix it

### Profile and dependency follow-up already done

We already separated a few variables that could have confused the diagnosis:

- compared saved profiles against fresh voice-design profiles
- rerolled the live profile through the runtime surface instead of expanding the
  local harness
- aligned package dependency pins and confirmed the resolved graph afterward

That work ruled out "stale dependency state" as an easy explanation and showed
that prompt/materialization differences can change the severity of the decay.

## Current Strongest Code-Level Suspects

### 1. The main non-streaming decode helper still uses the incremental decoder path

In vendored `mlx-audio-swift`, `Qwen3TTS.decodeChunk(...)` currently loops over
`speechTokenizer.streamingDecode(...)`:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:214`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:218`

That means the ordinary non-streaming generation path in `generateVoiceDesign`
still ends up relying on the incremental decoder helper through
`decodeChunk(decodeCodes)`:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:551`

The tokenizer already has a separate bounded decode surface:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:1060`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:1063`

That normal tokenizer decode uses `decoder.chunkedDecode(...)`, which replays a
bounded left context of `25` tokens instead of keeping one decoder cache alive
for the whole utterance:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:1008`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:1018`

The incremental path keeps transformer cache state across the whole run:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:891`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:970`

So the leading suspect is now narrower than "streaming is different":
ordinary non-streaming generations may also be exposed to decoder-state drift
because their final decode helper still goes through the streaming decoder lane.

### 2. The decoder config exposes `slidingWindow`, but the transformer decode path does not use it

`Qwen3TTSTokenizerDecoderConfig` carries a `slidingWindow` field:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSConfig.swift:307`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSConfig.swift:328`

But the decoder transformer's forward path currently derives positions and
causal masking from the full cache offset and sequence length without applying
that sliding-window bound:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:466`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:475`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift:484`

If the decoder was expected to operate under bounded history, this mismatch is
another plausible reason later chunks can drift away from early-chunk loudness.

### 3. Reference-audio handling is inconsistent between streaming and non-streaming decode lanes

The non-streaming `generateVoiceDesign` path prepends `refCodes` before decode
and trims the corresponding audio back off afterward:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:545`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:558`

The streaming lane does not warm decoder state with those reference codes
before it begins incrementally decoding generated codes:

- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:489`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift:503`

That mismatch may not be the whole loudness-decay bug, but it means
streamed-vs-direct comparisons do not currently start from the same decoder
history when reference conditioning is present.

### 4. The upstream benchmark CLI exercises the streaming lane

The vendored `mlx-audio-swift` TTS benchmark path calls `generateStream(...)`:

- `.build/checkouts/mlx-audio-swift/Sources/Tools/mlx-audio-swift-tts/App.swift:124`

So the current upstream CLI benchmark surface will naturally emphasize any bug
that only appears in the incremental decode lane or is amplified there.

## New Upstream Audit Result

The local upstream checkout now has a dedicated maintainer note at:

- `/Users/galew/Workspace/Blaizzy/mlx-audio-swift/docs/maintainers/qwen3tts-audio-decay-audit.md`

That audit confirms the decode-path split described above and adds regression
coverage in upstream `MLXAudioTTSTests.swift` for three comparisons:

- synthetic bounded decode vs incremental streaming decode
- real encoder-produced codec sequences decoded through both paths
- real conditioned generated-code comparison using the current helper,
  bounded decode, and a reference-warmed incremental decode

The important update is that those probes currently pass on that machine and do
not reproduce the severe late-tail RMS collapse by themselves.

The closest upstream probe to the SpeakSwiftly symptom uses a real conditioned
generation, captures the produced Qwen codec sequence, and then decodes that
same sequence three ways. On that machine:

- the current `decodeChunk(...)` helper and a manual reference-warmed
  incremental decode matched each other closely
- both were somewhat hotter than bounded decode at the head of the waveform
- the tail RMS stayed roughly aligned across all three decode paths

So the upstream audit sharpens the diagnosis:

- the decode-path mismatch is definitely real
- the missing reference warm-up difference is definitely real
- the missing sliding-window enforcement is still suspicious
- but plain decoder-path mismatch by itself is not yet sufficient to reproduce
  the strongest SpeakSwiftly decay symptom in upstream isolation tests

## Newer Upstream Findings

The local upstream checkout has now gone a step further and added a more
SpeakSwiftly-like probe matrix in
`/Users/galew/Workspace/Blaizzy/mlx-audio-swift/Tests/MLXAudioTTSTests.swift`.

That newer probe work adds two important shapes:

- an end-to-end retained-output comparison using a real persisted SpeakSwiftly
  conditioning artifact from `probe-clear-masc-20260421`
- a profile-and-length matrix over both `probe-soft-femme-20260421` and
  `probe-clear-masc-20260421`, comparing raw rebuilt conditioning against the
  persisted `qwen-conditioning-qwen3.json` artifact on both short and long
  prompts

### What the newer upstream work found

First, persisted conditioning artifacts are not neutral. On the same machine
and backend snapshot, using the saved SpeakSwiftly artifact can worsen
late-utterance retained loudness relative to rebuilding conditioning from
`reference.wav` plus the stored reference text.

Second, the strongest local repro so far is now a combination effect:

- profile choice matters
- persisted artifact conditioning matters
- long prompt length matters

The first strong local repro in upstream `mlx-audio-swift` was:

- `probe-soft-femme-20260421`
- long prompt
- persisted artifact conditioning

That combination reportedly dropped to an artifact tail ratio of about `0.0367`
while the corresponding long raw-conditioned run stayed around `0.867`.

### What still did not happen

Even in the artifact-conditioned probe, the current `decodeChunk(...)` helper
still stayed roughly aligned with bounded decode at the tail on the exact same
captured generated code stream. That means the severe field symptom still is
not explained by helper decode choice alone.

### New caveat: the strongest repro is unstable across reruns

The upstream note also reports that the severe matrix collapse moved around or
disappeared across later reruns:

- one rerun showed the previously bad `probe-soft-femme-20260421` long-form
  artifact lane recovering to a much healthier tail ratio
- another rerun shifted the strongest collapse into the
  `probe-clear-masc-20260421` long artifact lane instead
- a later logging-style rerun completed without catastrophic collapse in any
  matrix entry

So the current best upstream reading is not "one specific profile is broken in a
fully deterministic way." It is:

- the failure family is now locally reproducible in the upstream repo
- persisted conditioning artifacts are a real amplifying factor
- profile choice and prompt length materially affect severity
- the worst collapse is stochastic enough that the matrix is currently an
  investigation harness and logging surface, not a reliable pass/fail
  regression gate

## What This Means Right Now

The current investigation state is:

- we already checked the local playback and retained-file code paths
- we already proved the fade exists in retained output
- we already proved the severity varies by profile
- we already proved `mlx-audio-swift 0.7.0` did not fix it
- the Qwen decode-path mismatch remains a real bug-shaped inconsistency, but it
  no longer looks sufficient on its own to explain the entire severe tail-fade
  repro
- the strongest remaining hidden variables now look more like
  profile/materialization specifics, persisted artifact conditioning, runtime
  surface differences above raw decode helpers, and longer generated sequences
  interacting together
- the latest upstream evidence suggests the worst failures are partly
  stochastic, so we should expect reruns to move severity around instead of
  giving us one perfectly stable failing lane

## Next Investigation Pass

The next focused pass should stay narrow and evidence-first:

1. Compare Qwen full decode through `speechTokenizer.decode(...)` against the
   current `decodeChunk(...)` helper on the same generated code sequence.
2. Check whether bounded `chunkedDecode(leftContextSize: 25)` materially
   changes late-utterance RMS relative to `streamingDecode(...)`.
3. Verify whether prepending `refCodes` into the streaming decode state changes
   the loudness trajectory for conditioned generations.
4. Reproduce the upstream conditioned generated-code probe shape against the
   specific SpeakSwiftly profiles that showed the strongest collapse, so we can
   tell whether the missing variable is the profile materialization itself.
5. Reproduce the newer upstream profile-and-length matrix inside SpeakSwiftly so
   we can log raw-vs-artifact retained tail ratios for the same profiles and
   compare how much variance shows up across reruns.
6. Inspect whether the intended decoder `slidingWindow` behavior exists in the
   Python/reference implementation and whether the Swift port drifted from it.
7. Compare the raw generated token lengths and decode inputs from the strongest
   SpeakSwiftly repros against the upstream passing probes to see whether the
   failing cases are simply much longer or otherwise more pathological.

## Related Files

- `docs/maintainers/backend-benchmarking-plan-2026-04-20.md`
- `Sources/SpeakSwiftlyTesting/SpeakSwiftlyTesting.swift`
- `Sources/SpeakSwiftly/Generation/SpeechGeneration+Qwen.swift`
- `Sources/SpeakSwiftly/Generation/ModelClients+Speech.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift`
- `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTSConfig.swift`
