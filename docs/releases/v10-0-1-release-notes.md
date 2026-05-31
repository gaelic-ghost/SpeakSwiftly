# v10.0.1 Release Notes

## What Changed

- Smoothed macOS media-app ducking so supported app volume lowers through a
  short shaped ramp instead of one abrupt volume change.
- Made media-app volume restoration gentler than ducking, with a longer shaped
  restore ramp.
- Added restore verification and up to two restore retries when Spotify or Music
  does not report the original volume after restoration.
- Kept media ducking active across back-to-back playback jobs so SpeakSwiftly
  does not restore media volume prematurely while more playback work is already
  queued.
- Included the macOS retrench and mobile split documentation update in this
  patch release branch.

## Breaking Changes

None.

## Migration Notes

- Existing hosts do not need code changes. Media ducking remains controlled by
  `SpeakSwiftly.Configuration.duckMediaVolume`.
- Hosts that enable media ducking still need macOS Automation permission for the
  supported media apps they want SpeakSwiftly to control.

## Verification

- `swift test --filter MacOSMediaVolumeDuckerTests`
- `swift test --filter PlaybackQueueExecutionTests`
- `swift test --filter WorkerRuntimePlaybackTests`
- `git diff --check`
- commit-hook repo-maintenance validation, including SwiftFormat, MLX resource
  checks, and SwiftLint
