# v5.0.0-rc.1 Release Prep

Date: 2026-05-03

This release candidate is the first next-major candidate for the
`TextForSpeech` `0.19.0` surface simplification.

## Scope

- Bump the package dependency floor from `TextForSpeech` `0.18.9` to `0.19.0`.
- Remove `SpeakSwiftly.InputTextContext` from the public typed Swift surface.
- Use `TextForSpeech.SourceFormat` directly only for whole-source generation.
- Carry request metadata and path context through `SpeakSwiftly.RequestContext`.
- Remove JSONL `input_text_context`, `text_format`, and
  `nested_source_format` from the current generation wire shape.
- Reject stale removed generation-context keys with a clear invalid-request
  message.
- Keep retained generated files, generation jobs, generated batches, request
  observation, and worker emission aligned on `source_format` and
  `request_context`.

## Not Included

- A coordinated `SpeakSwiftlyServer` adoption branch.
- A `speak-to-user` monorepo submodule bump.
- A backend default change.
- A voice-profile storage migration.

## SemVer Framing

- Release this candidate as `v5.0.0-rc.1`.
- This is a major candidate because it removes the public
  `SpeakSwiftly.InputTextContext` Swift API and rejects removed JSONL
  generation-context keys.

## Validation Target

Run the checks serially:

```bash
swift build
swift test
bash scripts/repo-maintenance/validate-all.sh
sh scripts/repo-maintenance/run-e2e-full.sh
```

## Verification Performed

- `swift test --filter WorkerProtocolTests` passed after the review-finding
  fixes.
- `swift build` passed.
- `swift test` passed with 250 non-E2E tests in 11 suites.
- `bash scripts/repo-maintenance/validate-all.sh` passed.
- `sh scripts/repo-maintenance/run-e2e-full.sh` passed the release-safe E2E
  suite set: `GeneratedFileE2ETests`, `GeneratedBatchE2ETests`,
  `ChatterboxE2ETests`, `QueueControlE2ETests`, `MarvisE2ETests`, and
  `QwenE2ETests`.
- The full E2E wrapper unloaded live `SpeakSwiftlyServer` resident models
  before the run and reloaded them after completion.

## Release Command

After validation and full E2E pass:

```bash
sh scripts/repo-maintenance/release.sh --mode standard --version v5.0.0-rc.1 --skip-version-bump
```
