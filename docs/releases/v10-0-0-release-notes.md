# v10.0.0 Release Notes

## What Changed

- Added `SpeakSwiftly.DuckMediaVolume` and
  `SpeakSwiftly.Configuration.duckMediaVolume` for optional macOS media-app
  volume ducking during local playback.
- Supports `.off`, `.aLittle`, `.default`, and `.aLot`, with `.off` as the out-of-box default.
- Ducks running Spotify and Music app volume by 20%, 35%, or 75% while
  SpeakSwiftly playback is active, then restores the original app volume after
  playback stops.
- Added macOS Automation permission preflight/request behavior for enabled
  ducking settings without persisting permission state.
- Raised the `mlx-audio-swift` fork pin to `0.100.0`.
- Returned the `SpeakSwiftly` package contract and current docs to macOS-only,
  with future mobile speech work planned for a separate `SpeakSwiftlyMobile`
  app.
- Changed the standard release script to run the full release-safe E2E wrapper
  before release instead of only the quick E2E suite.

## Breaking Changes

- `Package.swift` no longer declares iOS support. iOS package consumers should
  not depend on `SpeakSwiftly`; future mobile work belongs in a separate app
  that can share `TextForSpeech` where appropriate.

## Migration Notes

- Existing macOS hosts keep the default `.off` ducking behavior unless they
  explicitly set `duckMediaVolume`.
- macOS app hosts that enable ducking should include
  `NSAppleEventsUsageDescription` in their Info.plist. Suggested copy is
  available as `SpeakSwiftly.DuckMediaVolume.automationUsageDescription`.
- CLI and service hosts that enable ducking should expect macOS to request
  Automation permission for Spotify and Music when those apps are running.

## Verification

- `swift package resolve`
- `swift package dump-package`
- `swift build`
- `swift test`
- `sh scripts/repo-maintenance/validate-all.sh`
- `sh scripts/repo-maintenance/run-e2e-full.sh`
