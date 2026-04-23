# v4.0.1 Release Notes

## What changed

- changed `SpeakSwiftly.RequestContext` to a public typealias for
  `TextForSpeech.RequestContext`, so request-origin metadata now uses one
  shared concrete model across normalization, generation, and downstream
  packages that import `SpeakSwiftly`
- added a library-surface regression test that proves the shared request
  context still round-trips through the public `SpeakSwiftly` API
- refreshed generated-artifact E2E assertions to use the current
  `voice_profile` field in generated file and generated batch payloads

## Breaking changes

- none

## Migration or upgrade notes

- existing callers can keep spelling the type as `SpeakSwiftly.RequestContext`
- generated artifact payloads continue to use `voice_profile`; this release
  updates stale E2E coverage to match that existing contract
- this release starts the stable `v4.0.x` line from the earlier
  `v4.0.0-rc.1` prerelease branch

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
