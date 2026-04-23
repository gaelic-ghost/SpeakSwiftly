# v4.0.1 Release Prep

Date: 2026-04-23

This note captures the intended scope and validation story for the `v4.0.1`
release.

## Intended Scope

The release should be framed as:

- a shared request-context model dedupe across `SpeakSwiftly` and
  `TextForSpeech`
- an end-to-end contract cleanup for generated artifact metadata
- a release validation pass that proves the current full E2E lane still clears
  after the shared-type adoption

Included work on the current branch:

- replace the standalone `SpeakSwiftly.RequestContext` struct with a public
  typealias to `TextForSpeech.RequestContext`
- add a library-surface test that proves the shared request-context model still
  round-trips through the public `SpeakSwiftly` API
- document the shared request-context ownership in the package README
- update E2E artifact assertions to use the current `voice_profile` field name
  in generated file and generated batch payloads
- rerun the full release-safe E2E lane after the stale field-name assertions
  were corrected

Not included:

- a wider public API redesign beyond request-context ownership cleanup
- a worker wire-format compatibility shim that reintroduces `profile_name`
  inside generated artifact payloads
- a broader release-management reorganization for the `v4` line

## SemVer Framing

- release this as `v4.0.1`
- the package-side API cleanup keeps `SpeakSwiftly.RequestContext` available to
  callers while deduplicating the underlying concrete model
- the E2E fixes correct stale tests to match the existing generated-artifact
  payload shape

## Validation Performed

Baseline package validation:

```bash
swift build
```

```bash
swift test
```

Full release-safe end-to-end lane:

```bash
sh scripts/repo-maintenance/run-e2e-full.sh
```

## Release Checklist

- call out that `SpeakSwiftly.RequestContext` now shares the concrete
  `TextForSpeech.RequestContext` model instead of duplicating it locally
- note that the generated-artifact E2E fixes were contract-alignment changes in
  the tests, not worker payload regressions
- include the full E2E lane in the release verification story
