# Voice Profile Creation

Create, inspect, and maintain stored voice profiles through the runtime's voice-management surface.

## Overview

SpeakSwiftly keeps voice-profile management on ``SpeakSwiftly/Voices``. That handle owns the operator-facing lifecycle for stored profiles: create them, list them, rename them, reroll them from their saved source inputs, and delete them when they are no longer needed.

The public library surface supports two end-user creation paths:

- Voice design, where you provide source text plus a descriptive prompt.
- Voice cloning, where you provide reference audio and an optional transcript.

All creation paths return a ``SpeakSwiftly/RequestHandle`` because profile creation is queued runtime work, not a synchronous local file write.

## Start From A Runtime

Voice profiles live behind the shared runtime:

```swift
import SpeakSwiftly

let runtime = await SpeakSwiftly.liftoff()
```

From there, use ``SpeakSwiftly/Runtime/voices`` for profile work.

## Create A Designed Voice

Use ``SpeakSwiftly/Voices/create(design:from:vibe:voiceDescription:outputPath:)`` when you want a new stored profile generated from text and a prompt:

```swift
let handle = await runtime.voices.create(
    design: "guide-femme",
    from: "A calm narrator with crisp pacing.",
    vibe: .femme,
    voiceDescription: "Warm, clear, confident, and measured."
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
    vibe: .femme,
    transcript: "The transcript of the recorded sample."
)
```

This path keeps the source audio and related metadata as part of the stored profile so the profile can be rerolled later.

System-authored profiles are package-owned defaults generated through
`SpeakSwiftlyTool` into bundled profile resources, then seeded into the writable
profile store when the runtime starts. They are not part of the ordinary end-user
library creation surface. Ordinary rename, delete, and in-place reroll operations
reject them with explicit errors. If a user rerolls a system profile, SpeakSwiftly
creates a user-owned copy instead so the built-in default remains stable.

Consumer packages can insert or update system profiles with the SwiftPM command plugin:

```bash
swift package plugin --allow-writing-to-package-directory upsert-system-voice-profile \
  --target SpeakSwiftlyServer \
  --name server-announcer \
  --text "A clear server status voice." \
  --vibe femme \
  --voice-description "Clear, bright, steady, and concise."
```

The target that owns those generated resources should declare
`.copy("Resources/SystemProfiles")` and pass its bundled root into liftoff:

```swift
let systemProfileRoots = [
    SpeakSwiftly.SupportResources.systemProfileRootURL(in: .module),
].compactMap(\.self)

let runtime = await SpeakSwiftly.liftoff(
    configuration: .init(systemProfileResourceRoots: systemProfileRoots)
)
```

## Observe Completion

Both creation paths return a request handle, so completion is observed the same way as speech generation:

```swift
for try await event in handle.events {
    if case .completed(.voiceProfile(let name, let path)) = event {
        print(name ?? "")
        print(path ?? "")
    }
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

After a profile exists, the most common next step is to use it with ``SpeakSwiftly/Generate/speech(text:voiceProfile:textProfile:sourceFormat:requestContext:qwenPreModelTextChunking:)`` or ``SpeakSwiftly/Generate/audio(text:voiceProfile:textProfile:sourceFormat:requestContext:)``.
