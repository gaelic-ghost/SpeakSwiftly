# Runtime Quick Start

Create one runtime, use its focused handles, and keep long-lived work attached to that shared state.

## Overview

The main entry point into SpeakSwiftly is ``SpeakSwiftly/liftoff(configuration:)``. That call starts a shared ``SpeakSwiftly/Runtime`` and applies startup-only choices from ``SpeakSwiftly/Configuration``, such as which speech backend to load and whether a custom ``SpeakSwiftly/Normalizer`` should be installed up front.

Once you have a runtime, the package expects you to work through narrow concern handles instead of one large method namespace. Use ``SpeakSwiftly/Runtime/generate`` to request speech or retained audio output, ``SpeakSwiftly/Runtime/player`` to inspect or control playback, ``SpeakSwiftly/Runtime/voices`` to manage stored voice profiles, and ``SpeakSwiftly/Runtime/jobs`` or ``SpeakSwiftly/Runtime/artifacts`` when you want to inspect work that stays around after generation finishes.

This shape matters because the runtime owns the worker process, playback pipeline, and retained metadata. The handles are lightweight views onto that same shared state rather than separate subsystems with their own lifecycle.

## Start The Runtime

If you do not need custom startup behavior, liftoff with the default configuration:

```swift
import SpeakSwiftly

let runtime = try await SpeakSwiftly.liftoff()
```

When you do need a specific backend or a custom normalizer, build a ``SpeakSwiftly/Configuration`` first and then pass it to liftoff:

```swift
import SpeakSwiftly

let normalizer = try await SpeakSwiftly.Normalizer(
    builtInStyle: .balanced,
    profile: nil
)

let runtime = try await SpeakSwiftly.liftoff(
    configuration: .init(
        speechBackend: .qwen3,
        textNormalizer: normalizer
    )
)
```

## Generate Playback Or Files

Use ``SpeakSwiftly/Generate/speech(text:with:textProfileName:textContext:sourceFormat:)`` when you want audio to enter the live playback queue:

```swift
let handle = try await runtime.generate.speech(
    text: "Hello from SpeakSwiftly.",
    with: "default-femme"
)
```

Use ``SpeakSwiftly/Generate/audio(text:with:textProfileName:textContext:sourceFormat:)`` when you want retained file output instead:

```swift
let handle = try await runtime.generate.audio(
    text: "Keep this as a generated artifact.",
    with: "default-femme"
)
```

Both calls return a ``SpeakSwiftly/RequestHandle``. That handle is your typed anchor for the specific request you just queued, including later status lookups and update streams.

## Observe Request Progress

You can watch a request move through queueing, warmup, generation, and completion by iterating the lifecycle stream on its ``SpeakSwiftly/RequestHandle``:

```swift
for try await event in handle.events {
    print(event)
}
```

If you want sequenced request snapshots from the runtime side instead, subscribe with ``SpeakSwiftly/Runtime/updates(for:)`` and the handle's identifier:

```swift
for try await update in runtime.updates(for: handle.id) {
    print(update.state)
}
```

When you want the broader runtime view instead of one request, use ``SpeakSwiftly/Player/state()`` for playback and ``SpeakSwiftly/Jobs/list()`` for retained generation-job snapshots.

## Where To Look Next

After the runtime is up, the next question is usually whether you care about live playback or retained output:

- For live queue control, continue with ``SpeakSwiftly/Player`` and ``SpeakSwiftly/PlaybackState``.
- For stored output and later inspection, continue with <doc:RetainedArtifacts>.
- For stored voice-profile management, continue with ``SpeakSwiftly/Voices``.
