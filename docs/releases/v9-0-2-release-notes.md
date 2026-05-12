# SpeakSwiftly v9.0.2 Release Notes

## What Changed

- Added a public-safe Codex Security repo-wide audit bundle under `docs/security-audits/`.
- Added Milestone 29 to `ROADMAP.md` to track the audit findings and deferred hardening rows.
- Raised the `TextForSpeech` dependency floor to `0.22.1`.

## Breaking Changes

None.

## Migration Notes

No API migration is required. Package consumers can resolve the updated `TextForSpeech` patch release through Swift Package Manager.

## Verification

- `swift package resolve`
- `swift test`
