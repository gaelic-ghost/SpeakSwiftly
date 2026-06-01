# Runtime Quick Start

Create one runtime, use its focused handles, and keep long-lived work attached to that shared state.

## Overview

The main entry point into SpeakSwiftly is ``SpeakSwiftly/liftoff(configuration:stateRootURL:)``.
That call starts a shared ``SpeakSwiftly/Runtime`` and applies startup-only
choices from ``SpeakSwiftly/Configuration``, such as which speech backend to
load, whether to duck supported media apps during playback, and whether a custom
``SpeakSwiftly/Normalizer`` should be installed up front. By default,
SpeakSwiftly stores runtime state in the platform Application Support directory.
Pass `stateRootURL` only when a host needs an isolated state directory for
profiles, configuration, and text profiles.

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

Media-app volume ducking is off by default. On macOS, set
``SpeakSwiftly/Configuration/duckMediaVolume`` to ``SpeakSwiftly/DuckMediaVolume/aLittle``,
``SpeakSwiftly/DuckMediaVolume/default``, or ``SpeakSwiftly/DuckMediaVolume/aLot``
when SpeakSwiftly should lower running Spotify and Music instances while local
speech playback is active, then restore the original app volume afterward.
Hosts that enable this should include `NSAppleEventsUsageDescription` in their
Info.plist; ``SpeakSwiftly/DuckMediaVolume/automationUsageDescription`` provides
suggested copy.

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

Use ``SpeakSwiftly/Generate/speech(text:voiceProfile:textProfile:requestContext:qwenPreModelTextChunking:output:)`` when you want audio to enter the live playback queue:

```swift
let handle = await runtime.generate.speech(
    text: "Hello from SpeakSwiftly."
)
```

Pass an explicit nonlocal `output:` when a host is ready to route generated
audio to an HTTP response or LAN transport. The output modules expose framing
and discovery primitives, while the host-owned server boundary is responsible
for attaching those bytes to a response or network connection.

Hosts that want selectable LAN audio receivers can use
``SpeakSwiftly/NetworkAudioDestinationBrowser`` to keep an in-memory list of
Bonjour-advertised audio receivers. A receiver host can attach
``SpeakSwiftly/NetworkAudioServiceAdvertisement/listenerService`` to its
Network.framework listener so other SpeakSwiftly instances can discover it.
Use ``SpeakSwiftly/NetworkAudioStreamSender`` to send generated chunks to a
selected endpoint, ``SpeakSwiftly/NetworkAudioStreamListener`` to accept
token-authenticated inbound streams, and ``SpeakSwiftly/LocalGeneratedAudioPlayer``
to play the received chunk stream on the local machine.

Use ``SpeakSwiftly/Generate/audio(text:voiceProfile:textProfile:requestContext:format:)`` when you want retained file output instead:

```swift
let handle = await runtime.generate.audio(
    text: "Keep this as a generated artifact."
)
```

Pass `format: .m4a` when you want Apple-native AAC compression instead of the default WAV artifact.

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

For live playback milestones, subscribe to ``SpeakSwiftly/Playback/updates()`` and branch on ``SpeakSwiftly/PlaybackUpdate/event``. ``SpeakSwiftly/PlaybackEvent`` reports stable operator-facing milestones such as active request changes, queue changes, first chunk, preroll readiness, rebuffer start and recovery, completion, output-device changes, and interruption changes. Detailed trace diagnostics remain internal logs.

## Where To Look Next

After the runtime is up, the next question is usually whether you care about live playback or retained output:

- For live queue control and playback milestones, continue with ``SpeakSwiftly/Playback``, ``SpeakSwiftly/PlaybackState``, and ``SpeakSwiftly/PlaybackEvent``.
- For stored output and later inspection, continue with <doc:RetainedArtifacts>.
- For stored voice-profile management, continue with ``SpeakSwiftly/Voices``.
