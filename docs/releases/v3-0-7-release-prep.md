# v3.0.7 Release Prep

Date: 2026-04-17

This note captures the intended scope and validation story for the `v3.0.7`
patch release.

## Intended Scope

The release should be framed as:

- a playback-runtime hardening patch for issue `#13`
- a package-manifest compatibility cleanup that pins the package to Swift 6
  language mode explicitly
- a release-surface docs cleanup that finishes moving versioned release notes
  under `docs/releases/`

Included work on the current branch:

- harden `AudioPlaybackDriver.waitForPlaybackDrain(...)` so the drain waiter is
  installed through a structured helper instead of an unstructured main-actor
  hop
- resume the stored drain continuation with `CancellationError` when the waiter
  task is cancelled so the suspended waiter can unwind cleanly instead of
  lingering behind mutable request state
- collapse the normal playback, recovery-reschedule, and interruption paths
  onto shared drain-continuation helpers
- add a focused regression test that proves a cancelled drain waiter clears its
  stored continuation
- add `swiftLanguageModes: [.v6]` to `Package.swift`
- finish the versioned release-notes relocation from `docs/maintainers/` to
  `docs/releases/` for the existing `v3.0.5` and `v3.0.6` notes surfaces

Not included:

- a broader playback-queue redesign
- a backend-policy retuning pass for Marvis overlap behavior
- a claim that the queued Marvis live-playback repro is fully end-to-end fixed
  in server context beyond the upstream drain-wait hardening on this branch

## Issue Mapping

- `#13` should be referenced as the primary fix:
  - the queued Marvis crash pointed at the playback-drain wait race
  - this branch hardens drain waiter ownership and cancellation behavior in the
    upstream playback driver

## Validation Performed

Repo gate:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

Manifest sanity:

```bash
swift package dump-package
```

Focused regression lane:

```bash
swift test --filter "playback drain waiter clears stored continuation when cancelled"
```

## Release Checklist

- keep the GitHub release notes focused on the playback-drain hardening, the
  explicit Swift 6 language-mode declaration, and the release-doc location
  cleanup
- reference issue `#13`
- describe the fix as a runtime cancellation and continuation-ownership
  hardening patch, not as a broader playback architecture rewrite
- keep verification notes honest about which lanes were run on this branch
