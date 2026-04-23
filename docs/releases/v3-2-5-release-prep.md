# v3.2.5 Release Prep

Date: 2026-04-22

This note captures the intended scope and validation story for the `v3.2.5`
patch release.

## Intended Scope

The release should be framed as:

- a Qwen live long-form stability pass
- a bounded-generation correction for audible live playback without changing the
  retained-file path

Included work on the current branch:

- bound live Qwen generation to two blank-line-separated paragraphs per model
  call
- fall back to smaller sentence-group chunks only when one paired paragraph
  chunk still grows too large
- keep generated audio-file rendering on the original single-pass Qwen path
- add regression coverage for the live-only scope and the oversized-chunk
  fallback

Not included:

- a new public API surface
- a change to current Chatterbox or Marvis backend semantics
- a change to generated-file rendering semantics

## SemVer Framing

- this should ship as a patch release
- the change narrows a backend behavior problem for live playback but does not
  add or break a public API

## Validation Performed

Targeted package validation:

```bash
swift test --filter ModelClientsTests
```

Qwen audible real-model e2e coverage:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen --audible
```

Dedicated long-form qwen audible coverage:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen-longform --audible
```

## Release Checklist

- keep the notes focused on Qwen live long-form stability, not as a broader
  backend architecture release
- call out that live playback is now bounded by two blank-line-separated
  paragraphs at a time
- call out that generated audio files still use the original single-pass Qwen
  rendering path
- mention that both the ordinary audible Qwen lane and the dedicated long-form
  audible lane passed before tagging
