# v3.2.6 Release Prep

Date: 2026-04-22

This note captures the intended scope and validation story for the `v3.2.6`
patch release.

## Intended Scope

The release should be framed as:

- a Qwen live long-form playback boundary fix
- a TextForSpeech structure-preservation refresh for live Qwen chunk planning
- a logging pass that makes the exact chunk text and chunk-finish timing
  visible in playback traces

Included work on the current branch:

- refresh the `TextForSpeech` dependency to `0.18.6`
- keep Qwen live chunk planning on paragraph-preserving chunks instead of
  flattened text
- log the exact live Qwen chunk text handed into generation
- mark finished Qwen live chunks explicitly in the playback stream
- let a finished chunk drain its already queued playback audio instead of
  entering ordinary low-water rebuffer handling before that queued audio is
  exhausted
- keep the dedicated opt-in audible long-form Qwen coverage on the nine
  paragraph prose request

Not included:

- a new public API surface
- concurrent multi-generation use of the same resident Qwen model
- a broader playback architecture rewrite
- a fix for every remaining intra-stream Qwen supply slowdown

## SemVer Framing

- this should ship as a patch release
- the change corrects live Qwen playback behavior and observability without
  breaking the public API

## Validation Performed

Targeted package validation:

```bash
swift test --filter ModelClientsTests
```

```bash
swift test --filter WorkerRuntimePlaybackTests
```

Dedicated long-form qwen audible coverage with trace logging:

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_AUDIBLE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 SPEAKSWIFTLY_QWEN_LONGFORM_E2E=1 swift test --filter 'SpeakSwiftlyTests.QwenLongFormE2ETests/`voice design live speech spans nine prose paragraphs`()'
```

## Release Checklist

- keep the notes focused on the finished-chunk drain fix and the new trace
  visibility, not as a broad playback rewrite
- call out that live Qwen chunk text is now logged directly in structured trace
  output
- call out that the first boundary-adjacent rebuffer now happens later because
  finished chunk audio is allowed to drain before ordinary rebuffer handling
  begins
- mention that structure-preserving normalization now keeps all nine paragraphs
  visible in the live Qwen trace payload
