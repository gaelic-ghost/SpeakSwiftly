# Retained Artifacts

Inspect retained artifacts and generation jobs after synthesis finishes, without reaching into runtime internals.

## Overview

SpeakSwiftly separates live playback control from retained generation output. Playback work belongs to ``SpeakSwiftly/Player``. Retained output belongs to ``SpeakSwiftly/Jobs`` and ``SpeakSwiftly/Artifacts``.

That split keeps the public API honest about ownership. A request may pass through the generation queue even when you never plan to play the result immediately, and a playback request may not leave behind the same retained output you care about for later inspection or reuse.

## Jobs Versus Artifacts

Use ``SpeakSwiftly/Jobs`` when you want to understand what happened to a generation request. Jobs tell you about queue position, status, and the metadata that ties one retained run back to the request that created it.

Use ``SpeakSwiftly/Artifacts`` when you want the retained result itself. Artifacts expose retained generated-audio outputs as operator-facing resources you can list and inspect after the work completes.

In practice, that means:

- ``SpeakSwiftly/Jobs`` answers "what did this request do?"
- ``SpeakSwiftly/Artifacts`` answers "what did this request leave behind?"

## Create Retained Output

The most direct path to a retained artifact is ``SpeakSwiftly/Generate/audio(text:voiceProfile:textProfile:sourceFormat:requestContext:)``:

```swift
let handle = await runtime.generate.audio(
    text: "Persist this clip for later use."
)
```

You can also queue several retained outputs together with ``SpeakSwiftly/Generate/batch(_:voiceProfile:)`` when the work belongs together as one generation job:

```swift
let batchHandle = await runtime.generate.batch(
    [
        .text("Intro clip"),
        .text("Outro clip")
    ]
)
```

Pass `voiceProfile:` only when a request should override `runtime.defaultVoiceProfile`.

## Inspect Stored Results

The retained-query APIs return ``SpeakSwiftly/RequestHandle`` values. Their terminal success events carry the stored payload you asked for.

For example, listing retained artifacts looks like this:

```swift
let artifactsHandle = await runtime.artifacts()

for try await event in artifactsHandle.events {
    if case .completed(.artifacts(let artifacts)) = event {
        print(artifacts)
    }
}
```

The same pattern applies to retained jobs:

- ``SpeakSwiftly/Jobs/list()`` completes with `generationJobs`.
- ``SpeakSwiftly/Artifacts/callAsFunction()`` completes with `artifacts`.
- ``SpeakSwiftly/Artifacts/list()`` is the explicit list convenience.
- ``SpeakSwiftly/Runtime/artifact(id:)`` completes with one retained artifact projection.

``SpeakSwiftly/GenerationJob`` is the canonical retained-work model for both file and batch generation. ``SpeakSwiftly/GenerationArtifact`` is the public typed Swift model for retained generated-audio outputs.

If you already know the stable identifier for a retained job, use ``SpeakSwiftly/Jobs/job(id:)`` instead of scanning the full collection first.

## Choosing The Right Surface

Reach for the retained-artifacts surface when you need any of the following:

- A generated clip needs to be inspected after the original request has completed.
- You are building an operator view that lists prior outputs.
- You want grouped retained output from one batch request.
- You need stored metadata without coupling your code to runtime internals.

When the work is really about current speaker behavior instead of stored output, go back to ``SpeakSwiftly/Player`` or the request stream on ``SpeakSwiftly/RequestHandle``.
