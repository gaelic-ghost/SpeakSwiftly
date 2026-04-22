# v3.2.2 Release Prep

Date: 2026-04-21

This note captures the intended scope and validation story for the `v3.2.2`
patch release.

## Intended Scope

The release should be framed as:

- a Qwen3 backend-behavior alignment pass
- a dependency refresh for the current `TextForSpeech` release
- a small resident-generation tuning update for Qwen live and file output

Included work on the current branch:

- remove the hardcoded Qwen `"English"` generation override and rely on the
  upstream model's language auto-detection instead
- apply the same no-hardcoded-language rule to prepared conditioning, profile
  design generation, reroll generation, and the direct Qwen testing probe path
- raise the standard Qwen resident streaming cadence to `0.32` while leaving
  Marvis-specific tuned cadences unchanged
- bump the `TextForSpeech` package dependency from `0.18.2` to `0.18.3`
- keep the `mlx-audio-swift` fork pin on the current latest release, `0.7.0`
- document the new Qwen behavior in README and CONTRIBUTING

Not included:

- a new public API surface
- a change to the current Chatterbox or Marvis backend semantics
- a move away from the exact `mlx-audio-swift` fork pin

## SemVer Framing

- this should ship as a patch release
- the change adjusts backend defaults and dependency pins, but it does not add
  a new consumer-facing API or break the existing public contract

## Validation Performed

Shared package validation:

```bash
swift build
swift test
```

Full release-safe real-model e2e lane:

```bash
sh scripts/repo-maintenance/run-e2e-full.sh
```

## Release Checklist

- keep the notes focused on Qwen3 behavior alignment and validation, not as a
  broader architecture release
- call out that Qwen now leans on upstream language auto-detection instead of
  a SpeakSwiftly-owned hardcoded override
- mention that `TextForSpeech` moved to `0.18.3` and that the
  `mlx-audio-swift` fork pin remains `0.7.0`
- mention that the full release-safe e2e lane passed across Quick,
  GeneratedFile, GeneratedBatch, Chatterbox, Marvis, and Qwen
