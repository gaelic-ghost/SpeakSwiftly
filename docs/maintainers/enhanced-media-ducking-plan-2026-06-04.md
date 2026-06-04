# Enhanced Media Ducking Plan

## Purpose

Improve macOS media-app volume ducking beyond live best-effort automation by
learning a small set of usual per-app volume levels over time. The goal is to
detect likely missed duck or restore writes more confidently without fighting a
user who is actively adjusting Spotify or Music volume.

This is a durable building-block change, not a local implementation detail. It
would add persisted observations and confidence rules around the existing
`MacOSMediaVolumeDucker` behavior.

## Current Baseline

The current ducker is intentionally live-only:

- It only targets supported running media apps.
- It only ducks apps whose AppleScript `player state` reports `playing`.
- It samples app volume before ducking or restoring and waits for a briefly
  stable value before writing.
- It skips ducking or restoring when volume keeps changing, because that is
  likely a user adjustment in progress.
- It remembers the pre-duck volume only for the active playback session.

## Enhanced Mode

Enhanced media ducking should be opt-in through configuration. A possible
public shape is a separate mode from the existing strength setting:

```swift
configuration: .init(
    duckMediaVolume: .default,
    mediaDuckingMode: .enhanced
)
```

The existing `duckMediaVolume` value should keep meaning "how strongly to lower
supported media apps." The enhanced option should mean "use persisted
observations to sanity-check duck and restore behavior."

## Observation Model

Record compact per-request observations when ducking is enabled:

- app bundle identifier
- pre-duck volume
- duck target volume
- observed volume after duck
- pre-restore volume
- restore target volume
- observed volume after restore
- ducking strength
- whether the app was playing
- whether a live stability wait happened
- whether a write was skipped because volume kept changing
- timestamp

Keep this bounded. A small ring buffer per app is enough for the first version.
Avoid storing track titles, artists, playlist names, or other media metadata.

## Learned Common Volumes

For each supported app, derive the three to five most common stable pre-duck
volumes from recent observations. Treat values within a small tolerance, such as
two percentage points, as the same bucket.

Use those buckets only as a confidence aid:

- If a restore target is close to a learned common volume, prefer restoring to
  that target after the live volume is stable.
- If the app appears to remain near the ducked target after restore, and the
  expected original volume is near a learned common volume, retry restore.
- If the app is off from the learned common volume by roughly the ducking delta,
  treat that as a likely missed restore event.
- If the live volume is moving or far from all learned common volumes, assume
  user intent and avoid writing.

## Safety Rules

- Keep enhanced mode off by default.
- Never infer from learned volumes alone when live volume is actively changing.
- Never restore a volume that the user moved far away from the active session's
  ducked value.
- Provide a way to clear learned ducking observations.
- Keep all observations local to the runtime state root.
- Do not collect media identity metadata.

## Implementation Slices

1. Add an internal observation model and bounded per-app store under the playback
   feature area.
2. Record observations from `MacOSMediaVolumeDucker` without changing decisions.
3. Add derived common-volume buckets and tests for tolerance, bucket ranking, and
   bounded retention.
4. Add enhanced-mode decision checks for likely missed duck and restore events.
5. Add a public or JSONL reset operation only if the learned store becomes
   visible enough that operators need a manual reset.

## Open Questions

- Should learned volumes be per app only, or per app plus output device?
- Should observations expire by count, age, or both?
- Should enhanced mode live in `SpeakSwiftly.Configuration` or stay entirely
  host-controlled until a second consumer needs it?
- Should the reset surface be typed Swift only, JSONL only, or both?
