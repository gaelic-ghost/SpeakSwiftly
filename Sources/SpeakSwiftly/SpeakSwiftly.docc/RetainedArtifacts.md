# Retained Artifacts

Inspect generated files and batches after synthesis finishes, without reaching into runtime internals.

## Overview

SpeakSwiftly separates live playback control from retained generation output. Playback work belongs to ``SpeakSwiftly/Player``. Retained output belongs to ``SpeakSwiftly/Jobs`` and ``SpeakSwiftly/Artifacts``.

That split keeps the public API honest about ownership. A request may pass through the generation queue even when you never plan to play the result immediately, and a playback request may not leave behind the same retained output you care about for later inspection or reuse.

## Jobs Versus Artifacts

Use ``SpeakSwiftly/Jobs`` when you want to understand what happened to a generation request. Jobs tell you about queue position, status, and the metadata that ties one retained run back to the request that created it.

Use ``SpeakSwiftly/Artifacts`` when you want the retained result itself. Artifacts expose generated files and batches as operator-facing resources you can list and inspect after the work completes.

In practice, that means:

- ``SpeakSwiftly/Jobs`` answers "what did this request do?"
- ``SpeakSwiftly/Artifacts`` answers "what did this request leave behind?"

## Create Retained Output

The most direct path to a retained file is ``SpeakSwiftly/Generate/audio(text:with:textProfileID:textContext:sourceFormat:)``:

```swift
let handle = try await runtime.generate.audio(
    text: "Persist this clip for later use.",
    with: "default-femme"
)
```

You can also queue several retained outputs together with ``SpeakSwiftly/Generate/batch(_:with:)`` when the work belongs together as one generated batch:

```swift
let batchHandle = try await runtime.generate.batch(
    [
        .text("Intro clip"),
        .text("Outro clip")
    ],
    with: "default-femme"
)
```

## Inspect Stored Results

The retained-query APIs return ``SpeakSwiftly/RequestHandle`` values. Their terminal success events carry the stored payload you asked for.

For example, listing retained files looks like this:

```swift
let filesHandle = await runtime.artifacts.files()

for try await event in filesHandle.events {
    if case .completed(let success) = event {
        print(success.generatedFiles ?? [])
    }
}
```

The same pattern applies to retained jobs and batches:

- ``SpeakSwiftly/Jobs/list()`` completes with `generationJobs`.
- ``SpeakSwiftly/Artifacts/files()`` completes with `generatedFiles`.
- ``SpeakSwiftly/Artifacts/batches()`` completes with `generatedBatches`.
- ``SpeakSwiftly/Artifacts/file(id:)`` and ``SpeakSwiftly/Artifacts/batch(id:)`` complete with one stored resource.

``SpeakSwiftly/GeneratedFile`` represents one retained audio file. ``SpeakSwiftly/GeneratedBatch`` represents a grouped generation result that keeps related retained files together.

If you already know the stable identifier for a stored resource, use the matching `get` API on ``SpeakSwiftly/Artifacts`` instead of scanning the full collection first.

## Choosing The Right Surface

Reach for the retained-artifacts surface when you need any of the following:

- A generated clip needs to be inspected after the original request has completed.
- You are building an operator view that lists prior outputs.
- You want grouped retained output from one batch request.
- You need stored metadata without coupling your code to runtime internals.

When the work is really about current speaker behavior instead of stored output, go back to ``SpeakSwiftly/Player`` or the request stream on ``SpeakSwiftly/RequestHandle``.
