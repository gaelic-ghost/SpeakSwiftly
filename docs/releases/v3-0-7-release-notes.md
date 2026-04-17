# v3.0.7 Release Notes

## What changed

- hardened the playback-drain waiter so cancellation resumes the stored waiter
  instead of leaving a suspended task parked behind mutable request state
- collapsed the playback, recovery, and interruption drain-completion paths
  onto shared continuation helpers in the playback request state
- added a focused regression test for cancelled drain waiters
- declared `swiftLanguageModes: [.v6]` in `Package.swift`
- finished moving versioned release notes into `docs/releases/`

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release aimed at queued live-playback drain stability
- the issue `#13` repro came from queued Marvis live playback through
  `SpeakSwiftlyServer`, but the hardening work in this release is scoped to the
  upstream `SpeakSwiftly` playback driver
- if plain `swift build` or `swift test` hits the vendored `EnglishG2P.swift`
  parser failure, switch to the documented repo-root Xcode-backed package lane
  instead of retrying the same SwiftPM command

## Verification performed

```bash
sh scripts/repo-maintenance/validate-all.sh
```

```bash
swift package dump-package
```

```bash
swift test --filter "playback drain waiter clears stored continuation when cancelled"
```
