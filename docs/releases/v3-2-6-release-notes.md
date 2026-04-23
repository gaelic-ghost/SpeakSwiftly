# v3.2.6 Release Notes

## What changed

- refreshed the `TextForSpeech` dependency to `0.18.6` so live Qwen chunk
  normalization now preserves paragraph structure instead of flattening the
  long-form request into one paragraph
- added structured logging for the exact live Qwen chunk text handed into
  generation, including visible newline markers in the stderr trace
- added an explicit finished-chunk playback boundary marker in the live Qwen
  stream
- changed playback so a finished Qwen chunk drains the audio that is already
  queued before ordinary low-water rebuffer handling can pause playback

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release focused on Qwen live playback stability and trace
  visibility
- live Qwen traces now include `text` and `text_visible_breaks` on the
  `qwen_live_chunk_planned` and `qwen_live_chunk_started` events
- the chunk-boundary fix improves the transition out of a finished chunk, but
  longer intra-stream Qwen supply slowdowns can still rebuffer later in a run

## Verification performed

```bash
swift test --filter ModelClientsTests
```

```bash
swift test --filter WorkerRuntimePlaybackTests
```

```bash
SPEAKSWIFTLY_E2E=1 SPEAKSWIFTLY_AUDIBLE_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 SPEAKSWIFTLY_QWEN_LONGFORM_E2E=1 swift test --filter 'SpeakSwiftlyTests.QwenLongFormE2ETests/`voice design live speech spans nine prose paragraphs`()'
```
