# v3.2.2 Release Notes

## What changed

- removed SpeakSwiftly's hardcoded Qwen `"English"` generation override and now
  let the upstream Qwen3 model auto-detect language during resident generation
- applied that same Qwen auto-detection path to prepared conditioning, profile
  design generation, reroll generation, and the direct testing probe path
- raised the standard Qwen resident streaming cadence to `0.32` for live and
  generated-file output while keeping Marvis-specific tuned cadences unchanged
- bumped `TextForSpeech` from `0.18.2` to `0.18.3`
- kept the `mlx-audio-swift` fork pin on its current latest release, `0.7.0`
- documented the new Qwen behavior in README and CONTRIBUTING

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release focused on backend behavior alignment and validation
- if you relied on SpeakSwiftly always forcing Qwen resident generation to
  English, that language override is now gone and the upstream model decides
  language from its own auto-detection path
- the `mlx-audio-swift` dependency remains intentionally pinned to the same
  exact fork release as before

## Verification performed

```bash
swift build
```

```bash
swift test
```

```bash
sh scripts/repo-maintenance/run-e2e-full.sh
```
