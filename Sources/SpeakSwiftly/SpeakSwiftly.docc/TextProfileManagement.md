# Text Profile Management

Shape normalization behavior through the shared normalizer, its stored text profiles, and its replacement rules.

## Overview

SpeakSwiftly uses ``SpeakSwiftly/Normalizer`` as the top-level home for text normalization behavior. You can construct a normalizer yourself and pass it into ``SpeakSwiftly/Configuration`` during runtime startup, or you can work through the normalizer already attached to an active runtime at ``SpeakSwiftly/Runtime/normalizer``.

The normalizer splits its public API into two focused handles:

- ``SpeakSwiftly/Normalizer/Style`` for built-in style selection.
- ``SpeakSwiftly/Normalizer/Profiles`` for profile and replacement-rule management.
- ``SpeakSwiftly/Normalizer/Persistence`` for loading, saving, and restoring persisted state.

## Use The Runtime-Attached Normalizer

If the runtime already owns the normalizer you want, start there:

```swift
let runtime = await SpeakSwiftly.liftoff()
let normalizer = runtime.normalizer
```

You can also build a standalone normalizer ahead of time and inject it through ``SpeakSwiftly/Configuration`` when startup needs a specific persistence location or seeded state.

## Inspect Profiles

Profile inspection lives on ``SpeakSwiftly/Normalizer/Profiles`` and style inspection lives on ``SpeakSwiftly/Normalizer/Style``:

```swift
let active = await normalizer.profiles.getActive()
let stored = await normalizer.profiles.list()
let effective = await normalizer.profiles.getEffective()
let builtInStyle = await normalizer.style.getActive()
let styleOptions = await normalizer.style.list()
```

Use the active profile when you want the currently selected custom profile, the stored list when you want the saved profiles on disk or in memory, and the effective profile when you want the merged result after built-in style and custom replacements are applied together.

## Create Or Update Profiles

Create a stored profile with ``SpeakSwiftly/Normalizer/Profiles/create(name:)``:

```swift
let profile = try await normalizer.profiles.create(name: "Logs")
```

Rename or activate a stored profile by stable identifier:

```swift
let renamed = try await normalizer.profiles.rename(profile: profile.profileID, to: "Build Logs")
try await normalizer.profiles.setActive(id: renamed.profileID)
```

Delete, reset, or factory-reset profiles through the same handle:

```swift
try await normalizer.profiles.reset(id: renamed.profileID)
try await normalizer.profiles.delete(id: renamed.profileID)
try await normalizer.profiles.factoryReset()
```

Use ``SpeakSwiftly/Normalizer/Style/setActive(to:)`` when the broad built-in normalization style should change for all later effective output.

## Manage Replacement Rules

Replacement rules can be managed on either the active profile or a specific stored profile:

```swift
let replacement = TextForSpeech.Replacement(
    id: "swiftpm",
    pattern: "SwiftPM",
    replacement: "Swift P M"
)

try await normalizer.profiles.addReplacement(replacement)
try await normalizer.profiles.patchReplacement(replacement)
try await normalizer.profiles.removeReplacement(id: "swiftpm")
```

When you want to target a stored profile instead of the active one, use the overloads that take `toProfile`, `inProfile`, or `fromProfile`.
If you need a full replacement reset, call ``SpeakSwiftly/Normalizer/Profiles/reset(id:)`` on that stored profile instead of clearing the replacement list through a separate API.

## Persist State

Persistence lives on ``SpeakSwiftly/Normalizer/Persistence``:

```swift
try await normalizer.persistence.save()
try await normalizer.persistence.load()
```

Use ``SpeakSwiftly/Normalizer/Persistence/url()`` when you need the configured persistence location. Construct the normalizer with a seeded `TextForSpeech.PersistedState` when startup needs an in-memory snapshot restored immediately.

## Where To Look Next

Once a normalizer is configured the way you want, pass its profile identifiers into generation calls with the `textProfileID` parameter so speech or file generation uses that stored normalization behavior.
