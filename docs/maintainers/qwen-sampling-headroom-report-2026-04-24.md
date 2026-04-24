# Qwen Sampling Headroom Report

Date: 2026-04-24

This note prepares the next Qwen investigation pass. It does not change runtime
sampling defaults by itself.

## Current Runtime Policy

SpeakSwiftly currently sends the resident Qwen path these caller-visible
generation parameters:

- `maxTokens`: `4096`
- `temperature`: `0.9`
- `topP`: `1.0`
- `repetitionPenalty`: `1.05`

The runtime also uses prepared Qwen conditioning by default. That means a stored
voice profile can contribute a reusable speaker embedding, reference speech
codes, and reference text token IDs to every resident Qwen generation request.

Live Qwen playback streams audio chunks at `0.32` second intervals. Generated
audio files should stay single-pass at the SpeakSwiftly runtime level so they can
remain a cleaner comparison point against live chunked playback.

## Upstream Effective Budget

The pinned `mlx-audio-swift` Qwen3TTS implementation resolves the caller
parameters into a VoiceDesign generation setting and then applies an internal
effective token cap:

```swift
let targetTokenCount = tokenizer.encode(text: text).count
let effectiveMaxTokens = min(maxTokens, max(75, targetTokenCount * 6))
```

Practical effect:

- `4096` is not always the real number of generated codec steps.
- Short text still gets at least `75` codec steps.
- Longer text gets up to about six generated codec steps per text token unless
  the global cap is reached.
- After the available text context is consumed, generation continues with the
  Qwen TTS pad embedding until the model emits EOS or reaches the cap.

That final point is the main headroom risk. If EOS is weak near the end of a
chunk, the model has room to keep producing speech-like tokens after the useful
text pressure has faded.

## Why This Could Spiral Near The End

The most plausible failure mode is not ordinary playback shaping. Playback
receives generated sample chunks; it can smooth samples and buffer/drain them,
but it does not decide what words or vocal artifacts the model generates.

The risk lives in generation:

- `temperature: 0.9` keeps sampling expressive.
- `topP: 1.0` leaves nucleus filtering effectively open.
- `repetitionPenalty: 1.05` is mild.
- the internal minimum of `75` codec steps can be generous for very short final
  chunks.
- prepared conditioning can be long and stylistically strong, so the reference
  prompt may dominate short target text.

Those choices can still be reasonable for lively voices. The question for the
next pass is whether the current defaults are too permissive for Qwen's final
chunk or tail behavior.

## Current Live Profile Context

The live `default-femme` profile inspected during this review was created on
2026-04-24. Its prepared Qwen conditioning artifact reported:

- `referenceSpeechCodes.shape`: `[1, 16, 560]`
- `referenceTextTokenIDs.shape`: `[1, 160]`
- `resolvedLanguage`: `auto`
- `codecLanguageID`: `null`

That is a fairly long style reference for a profile intended to speak many short
assistant replies. It should be included in the sampling investigation instead
of treating the profile as a neutral constant.

## Investigation Plan

1. Keep generated-file Qwen rendering single-pass at the runtime level.
2. Restore or land generated-code capture and replay tooling on `main`.
3. Capture matched runs for:
   - current `default-femme`
   - a shorter but still bright `testing-femme`
   - a calmer baseline profile if needed
4. Compare generated codec length, EOS timing, tail token patterns, and WAV-side
   prosody for the same input text.
5. Try a small parameter matrix only after the capture surface is trustworthy:
   - current default: `temperature 0.9`, `topP 1.0`, `repetitionPenalty 1.05`
   - slightly tighter nucleus: `temperature 0.9`, `topP 0.9`
   - slightly stronger repeat control: `repetitionPenalty 1.1`
   - combined conservative candidate: `temperature 0.85`, `topP 0.9`,
     `repetitionPenalty 1.1`
6. Treat audible output as the final check, but do not rely on listening alone as
   the first measurement surface.

## Non-Goals

- Do not tune Qwen defaults from one bad live reply.
- Do not use `compare-volume` for streamed-vs-direct conclusions unless it first
  proves matched spans.
- Do not make the default voice flat or subdued just to reduce variance. The
  target is energetic but stable speech, not bland speech.
