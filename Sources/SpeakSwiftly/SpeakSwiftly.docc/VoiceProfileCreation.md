# Voice Profile Creation

Create, inspect, and maintain stored voice profiles through the runtime's voice-management surface.

## Overview

SpeakSwiftly keeps voice-profile management on ``SpeakSwiftly/Voices``. That handle owns the operator-facing lifecycle for stored profiles: create them, list them, rename them, reroll them from their saved source inputs, and delete them when they are no longer needed.

The package supports two creation paths:

- Voice design, where you provide source text plus a descriptive prompt.
- Voice cloning, where you provide reference audio and an optional transcript.

Both creation paths return a ``SpeakSwiftly/RequestHandle`` because profile creation is queued runtime work, not a synchronous local file write.

## Start From A Runtime

Voice profiles live behind the shared runtime:

```swift
import SpeakSwiftly

let runtime = await SpeakSwiftly.liftoff()
```

From there, use ``SpeakSwiftly/Runtime/voices`` for profile work.

## Create A Designed Voice

Use ``SpeakSwiftly/Voices/create(design:from:vibe:voice:outputPath:)`` when you want a new stored profile generated from text and a prompt:

```swift
let handle = await runtime.voices.create(
    design: "guide-femme",
    from: "A calm narrator with crisp pacing.",
    vibe: .femme,
    voice: "Warm, clear, confident, and measured."
)
```

This path is best when you want to author a reusable voice without recording reference audio first.
If you pass `outputPath`, SpeakSwiftly uses that as an export-audio file path for the generated reference sample after the profile has been stored.

## Create A Cloned Voice

Use ``SpeakSwiftly/Voices/create(clone:from:vibe:transcript:)`` when you already have reference audio:

```swift
let handle = await runtime.voices.create(
    clone: "archive-guide",
    from: URL(fileURLWithPath: "/tmp/reference.wav"),
    vibe: .androgenous,
    transcript: "The transcript of the recorded sample."
)
```

This path keeps the source audio and related metadata as part of the stored profile so the profile can be rerolled later.

## Observe Completion

Both creation paths return a request handle, so completion is observed the same way as speech generation:

```swift
for try await event in handle.events {
    print(event)
}
```

When you need the retained snapshot after the request has moved on, inspect it from the runtime side with ``SpeakSwiftly/Runtime/request(id:)`` or ``SpeakSwiftly/Runtime/updates(for:)``.

## Manage Existing Profiles

Once profiles exist, ``SpeakSwiftly/Voices`` exposes the rest of the lifecycle:

- ``SpeakSwiftly/Voices/list()`` lists the stored profiles known to the runtime.
- ``SpeakSwiftly/Voices/rename(_:to:)`` changes the stored profile name.
- ``SpeakSwiftly/Voices/reroll(_:)`` rebuilds a profile from its persisted source inputs.
- ``SpeakSwiftly/Voices/delete(named:)`` removes a stored profile.

That split keeps creation and later maintenance on one focused handle instead of scattering profile lifecycle work across generation APIs.

## Where To Look Next

After a profile exists, the most common next step is to use it with ``SpeakSwiftly/Generate/speech(text:with:textProfileName:textContext:sourceFormat:)`` or ``SpeakSwiftly/Generate/audio(text:with:textProfileName:textContext:sourceFormat:)``.
