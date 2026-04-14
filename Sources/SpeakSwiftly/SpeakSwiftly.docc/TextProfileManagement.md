# Text Profile Management

Shape normalization behavior through the shared normalizer, its stored text profiles, and its replacement rules.

## Overview

SpeakSwiftly uses ``SpeakSwiftly/Normalizer`` as the top-level home for text normalization behavior. You can construct a normalizer yourself and pass it into ``SpeakSwiftly/Configuration`` during runtime startup, or you can work through the normalizer already attached to an active runtime at ``SpeakSwiftly/Runtime/normalizer``.

The normalizer splits its public API into two focused handles:

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

Profile inspection lives on ``SpeakSwiftly/Normalizer/Profiles``:

```swift
let active = await normalizer.profiles.active()
let stored = await normalizer.profiles.list()
let effective = await normalizer.profiles.effective()
```

Use the active profile when you want the currently selected custom profile, the stored list when you want the saved profiles on disk or in memory, and the effective profile when you want the merged result after built-in style and custom replacements are applied together.

## Create Or Update Profiles

Create a stored profile with ``SpeakSwiftly/Normalizer/Profiles/create(id:name:replacements:)``:

```swift
let profile = try await normalizer.profiles.create(
    id: "logs",
    name: "Logs",
    replacements: []
)
```

Store a whole profile without activating it:

```swift
try await normalizer.profiles.store(profile)
```

Or store and activate one profile in a single step:

```swift
try await normalizer.profiles.use(profile)
```

Use ``SpeakSwiftly/Normalizer/Profiles/setBuiltInStyle(_:)`` when the broad built-in normalization style should change for all later effective output.

## Manage Replacement Rules

Replacement rules can be managed on either the active profile or a specific stored profile:

```swift
let replacement = TextForSpeech.Replacement(
    id: "swiftpm",
    pattern: "SwiftPM",
    replacement: "Swift P M"
)

try await normalizer.profiles.add(replacement)
try await normalizer.profiles.replace(replacement)
try await normalizer.profiles.removeReplacement(id: "swiftpm")
```

When you want to target a stored profile instead of the active one, use the overloads that take `toStoredProfileID`, `inStoredProfileID`, or `fromStoredProfileID`.

For broad cleanup work, ``SpeakSwiftly/Normalizer/Profiles/clearReplacements()`` and ``SpeakSwiftly/Normalizer/Profiles/clearReplacements(fromStoredProfileID:)`` remove every replacement rule from the selected profile surface.

## Persist State

Persistence lives on ``SpeakSwiftly/Normalizer/Persistence``:

```swift
try await normalizer.persistence.save()
try await normalizer.persistence.load()
```

Use ``SpeakSwiftly/Normalizer/Persistence/save(to:)`` or ``SpeakSwiftly/Normalizer/Persistence/load(from:)`` when you need an explicit alternate location. Use ``SpeakSwiftly/Normalizer/Persistence/state()`` and ``SpeakSwiftly/Normalizer/Persistence/restore(_:)`` when you need the full persisted snapshot rather than the file-oriented helpers.

## Where To Look Next

Once a normalizer is configured the way you want, pass its profile identifiers into generation calls with the `textProfileName` parameter so speech or file generation uses that stored normalization behavior.
