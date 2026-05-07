# Runtime Quick Start

Create one runtime, use its focused handles, and keep long-lived work attached to that shared state.

## Overview

The main entry point into SpeakSwiftly is ``SpeakSwiftly/liftoff(configuration:stateRootURL:)``. That call starts a shared ``SpeakSwiftly/Runtime`` and applies startup-only choices from ``SpeakSwiftly/Configuration``, such as which speech backend to load and whether a custom ``SpeakSwiftly/Normalizer`` should be installed up front. By default, SpeakSwiftly stores runtime state in the platform Application Support directory. Pass `stateRootURL` only when a host needs an isolated state directory for profiles, configuration, and text profiles.

Once you have a runtime, the package expects you to work through narrow concern handles instead of one large method namespace. Use ``SpeakSwiftly/Runtime/generate`` to request speech or retained audio output, ``SpeakSwiftly/Runtime/playback`` to inspect or control playback, ``SpeakSwiftly/Runtime/voices`` to manage stored voice profiles, and ``SpeakSwiftly/Runtime/jobs`` or ``SpeakSwiftly/Runtime/artifacts`` when you want to inspect work that stays around after generation finishes.

This shape matters because the runtime owns the worker process, playback pipeline, and retained metadata. The handles are lightweight views onto that same shared state rather than separate subsystems with their own lifecycle.

## Start The Runtime

If you do not need custom startup behavior, liftoff with the default configuration:

```swift
import SpeakSwiftly

let runtime = await SpeakSwiftly.liftoff()
```

When you do need a specific backend or a custom normalizer, build a ``SpeakSwiftly/Configuration`` first and then pass it to liftoff:

```swift
import SpeakSwiftly

let normalizer = try SpeakSwiftly.Normalizer(
    builtInStyle: .balanced
)

let runtime = await SpeakSwiftly.liftoff(
    configuration: .init(
        speechBackend: .qwen3_smol,
        textNormalizer: normalizer
    )
)
```

Use ``SpeakSwiftly/SpeechBackend/qwen3_BIG`` when the runtime should load the
larger Qwen 1.7B 8-bit resident model instead of the default Qwen 0.6B 8-bit
model. The Qwen backend family also includes explicit 6-bit, 8-bit, and bf16
cases for both sizes.

When a host needs isolated persisted state, pass the state root at startup:

```swift
let runtime = await SpeakSwiftly.liftoff(
    stateRootURL: URL(fileURLWithPath: "/tmp/SpeakSwiftly-Isolated")
)
```

When a host package owns generated system profiles, bundle them under that
host target's resources and pass the bundled root at startup:

```swift
let systemProfileRoots = [
    SpeakSwiftly.SupportResources.systemProfileRootURL(in: .module),
].compactMap(\.self)

let runtime = await SpeakSwiftly.liftoff(
    configuration: .init(systemProfileResourceRoots: systemProfileRoots)
)
```

SpeakSwiftly seeds those bundled system profiles into its writable profile store
during liftoff. After startup, callers use them by name like any other available
voice profile.

`SPEAKSWIFTLY_PROFILE_ROOT` remains accepted only as a deprecated compatibility
alias for older hosts. New hosts should pass `stateRootURL`, pass `--state-root`
to the worker executable, or use `SPEAKSWIFTLY_STATE_ROOT` when startup
arguments are not available.

## Generate Playback Or Files

Use ``SpeakSwiftly/Generate/speech(text:voiceProfile:textProfile:sourceFormat:requestContext:qwenPreModelTextChunking:)`` when you want audio to enter the live playback queue:

```swift
let handle = await runtime.generate.speech(
    text: "Hello from SpeakSwiftly."
)
```

Use ``SpeakSwiftly/Generate/audio(text:voiceProfile:textProfile:sourceFormat:requestContext:)`` when you want retained file output instead:

```swift
let handle = await runtime.generate.audio(
    text: "Keep this as a generated artifact."
)
```

If a call omits `voiceProfile:`, SpeakSwiftly uses `runtime.defaultVoiceProfile`. The package fallback is `swift-signal`.

Both calls return a ``SpeakSwiftly/RequestHandle``. That handle is your typed anchor for the specific request you just queued, including later status lookups and update streams.

## Observe Request Progress

For the common submit-and-wait path, call ``SpeakSwiftly/RequestHandle/completion()``:

```swift
let completion = try await handle.completion()
print(completion)
```

You can watch a request move through queueing, warmup, generation, and completion by iterating the lifecycle stream on its ``SpeakSwiftly/RequestHandle``:

```swift
for try await event in handle.events {
    if case .completed(let completion) = event {
        print(completion)
    }
}
```

If you want sequenced request snapshots from the runtime side instead, subscribe with ``SpeakSwiftly/Runtime/updates(for:)`` and the handle's identifier:

```swift
for try await update in runtime.updates(for: handle.id) {
    print(update.state)
}
```

When you want the broader runtime view instead of one request, use ``SpeakSwiftly/Runtime/snapshot()`` for resident state, backend, default voice profile, and resolved storage paths. Use ``SpeakSwiftly/Generate/snapshot()`` for generation queue state and ``SpeakSwiftly/Playback/snapshot()`` for playback state and queued playback work.

## Where To Look Next

After the runtime is up, the next question is usually whether you care about live playback or retained output:

- For live queue control, continue with ``SpeakSwiftly/Playback`` and ``SpeakSwiftly/PlaybackState``.
- For stored output and later inspection, continue with <doc:RetainedArtifacts>.
- For stored voice-profile management, continue with ``SpeakSwiftly/Voices``.
