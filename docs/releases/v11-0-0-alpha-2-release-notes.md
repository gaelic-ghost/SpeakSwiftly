# v11.0.0-alpha.2 Draft Release Notes

## What Changed

- Added `SpeakSwiftlyFileAudioOutput` for retained `.wav` and AAC `.m4a`
  generated-audio files.
- Added length-prefixed Network.framework stream sender and listener primitives
  under `SpeakSwiftlyNetworkAudioOutput`.
- Added token-authenticated LAN audio stream handshakes for receiver workflows.
- Added `LocalGeneratedAudioPlayer` under `SpeakSwiftlyPlayback` for playing
  canonical generated-audio chunk streams locally.
- Updated release automation so SemVer prerelease tags create GitHub prerelease
  objects and verify existing prerelease metadata.

## Breaking Changes

- This remains part of the v11 major cleanup line. Removed backend and
  request-context compatibility shims from alpha.1 remain removed.

## Migration Notes

- Use `GeneratedAudioFileFormat.m4a` when a portable compressed retained file is
  preferred over `.wav`.
- LAN receiver hosts should enable `NetworkAudioStreamListener` explicitly,
  require a shared token, and pass accepted chunk streams to
  `LocalGeneratedAudioPlayer`.
- Server or app hosts still own request sessions, authorization policy,
  configuration, and routing between remote callers and selected audio receivers.

## Verification

- `swift build`
- `swift test --filter NetworkAudioOutputTests`
- `swift test --filter GeneratedAudioOutputTests`
- `swift test`
- `bash scripts/repo-maintenance/validate-all.sh`

## Follow-Up Before Final v11.0.0

- Update `SpeakSwiftlyServer` to consume this prerelease as an opt-in Bonjour
  LAN audio receiver.
- Add server-side remote-output routing after the receiver can play package
  loopback streams reliably.
