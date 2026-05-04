# v5.0.0 Release Prep

Date: 2026-05-04

This final release stabilizes the `v5.0.0-rc.1` public API and JSONL wire-shape
simplification for downstream adopters.

## Scope

- Publish the final `v5.0.0` tag from the reviewed release branch.
- Keep the `TextForSpeech` dependency floor at `0.19.0`.
- Keep the simplified `sourceFormat` and `requestContext` typed Swift surface.
- Keep the current JSONL generation shape centered on `source_format` and
  `request_context`.
- Preserve the stale-key rejection behavior introduced in the release
  candidate.
- Align the release E2E live-service unload/reload helpers with the current
  `SpeakSwiftlyServer` control routes while keeping fallback support for the
  older route shape.

## Not Included

- A backend default change.
- A voice-profile storage migration.
- A coordinated `speak-to-user` monorepo submodule bump.

## SemVer Framing

- Release this final as `v5.0.0`.
- This is a major release because it removes the public
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

- `bash scripts/repo-maintenance/validate-all.sh` passed.
- `sh scripts/repo-maintenance/run-e2e-full.sh` passed.

## Release Command

After validation and full E2E pass:

```bash
sh scripts/repo-maintenance/release.sh --mode standard --version v5.0.0 --skip-version-bump
```
