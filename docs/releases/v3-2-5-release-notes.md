# v3.2.5 Release Notes

## What changed

- bounded live Qwen generation to two blank-line-separated paragraphs per model
  call so long-form audible playback no longer relies on one unbounded resident
  generation span
- added a smaller sentence-group fallback when one paired paragraph chunk is
  still too large
- kept generated audio-file rendering on the original single-pass Qwen path
- added regression coverage for the bounded live path, the oversized fallback,
  and the live-vs-file scope split

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release focused on Qwen live playback stability
- live `generate_speech` requests on the Qwen backend now synthesize two
  blank-line-separated paragraphs at a time before moving to the next chunk
- retained `generate_audio_file` requests on the Qwen backend still render in a
  single pass

## Verification performed

```bash
swift test --filter ModelClientsTests
```

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen --audible
```

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen-longform --audible
```
