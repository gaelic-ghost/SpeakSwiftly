# v4.1.0 Release Prep

Date: 2026-04-28

This note captures the intended scope and validation story for the `v4.1.0`
release.

## Intended Scope

The release should be framed as:

- a minor TextForSpeech integration refresh that adopts `TextForSpeech` `0.18.9`
- a normalization simplification that routes live speech and retained file
  generation through one shared `SpeakSwiftly.Normalizer.speechText(...)` path
- a package-surface alignment with the current `TextForSpeech.InputContext`,
  `TextForSpeech.RequestContext`, and profile-details naming model

Included work on the current branch:

- update the `TextForSpeech` dependency floor and resolved pin to `0.18.9`
- change `SpeakSwiftly.InputTextContext.context` to use
  `TextForSpeech.InputContext`
- keep JSONL text-profile payloads encoded as `profile_id` while mapping from
  `TextForSpeech.Runtime.Profiles.Details.id`
- centralize normalization through the shared normalizer before live playback
  or retained file generation
- preserve source-format handling, selected text profiles, active built-in
  style, and TextForSpeech summarization-provider selection through that shared
  path
- enqueue live playback state before generation admission so async
  normalization cannot let generation outrun playback registration
- make `runtime.player.cancelRequest(_:)` submit the broad request-cancel
  operation promised by its documentation, while retaining queue-specific
  cancellation through `runtime.cancel(_:requestID:)`

Not included:

- a coordinated `speak-to-user` submodule bump
- a voice-profile storage migration
- a real-model backend default change

## SemVer Framing

- release this as `v4.1.0`
- this is a minor release because it updates the public Swift normalization
  typing around `TextForSpeech.InputContext` and simplifies the generation
  normalization path while preserving JSONL compatibility
- JSONL callers can keep sending the existing `input_text_context`,
  `request_context`, and `text_profile_id` compatibility keys

## Validation Target

Baseline package validation before release:

```bash
swift build
```

```bash
swift test
```

Coverage before release:

```bash
swift test --enable-code-coverage
```

Formatting, linting, and repo-maintenance validation before release:

```bash
git diff --check
```

```bash
sh scripts/repo-maintenance/validate-all.sh
```

Release-safe E2E validation before release:

```bash
sh scripts/repo-maintenance/run-e2e-full.sh
```

## Release Checklist

- confirm the release-safe E2E lane passes after the PR branch is pushed
- check GitHub CI and PR comments before tagging
- rerun E2E after any PR feedback fix that touches runtime, generation,
  playback, or normalization behavior
- release through `scripts/repo-maintenance/release.sh --mode standard
  --version v4.1.0`
