# Non-Streaming Backend Chunked Live Playback Plan

## Status

The first implementation of this model landed on 2026-04-17 for the Chatterbox backend.

What is implemented now:

- normalized text is segmented into speakable chunks up front
- Chatterbox synthesizes those chunks sequentially
- each completed chunk waveform is yielded into the existing live playback buffer immediately

What still remains follow-up work:

- tighten chunk sizing and scheduling heuristics for clone-heavy paths
- widen the same chunked live model to other non-streaming backends as they land
- clean up this file later into a shorter historical maintainer note once the broader docs pass happens

## Why This Exists

This is a durable building-block change, not a Chatterbox-specific hack.

`SpeakSwiftly` already has one live-playback model that works well for genuinely incremental backends:

- generate audio progressively
- feed chunks into the playback buffer
- let the player move from buffering to preroll to normal drain

That model is still the right target for non-streaming backends.

The mistake would be to mirror the upstream non-streaming behavior too literally and wait for a full waveform before playback can begin. That would preserve the worst part of the backend limitation instead of adapting around it.

The right move is simpler:

- split the input text into playback-safe text chunks up front
- run those text chunks through the non-streaming model sequentially
- as each synthesized audio chunk completes, feed it into the existing playback buffer
- overlap chunk synthesis and chunk playback at the request level even though the backend itself is not incrementally streaming within a chunk

That gives us the behavior we actually want:

- early audible startup
- continuous playback once the first chunk is ready
- no fake claim that the backend itself streams token-by-token

## Confirmed Current Limitation

The current local wrapper is already forwarding upstream audio events correctly.

`SpeakSwiftly.Runtime.chatterboxGenerationStream(...)` in `Sources/SpeakSwiftly/Generation/ChatterboxSpeechGeneration.swift` immediately forwards each upstream `.audio` event into the live playback continuation.

The limitation is upstream Chatterbox behavior:

- `ChatterboxModel.generateStream(...)` calls full `generate(...)`
- waits for all synthesis stages to complete
- yields one final waveform

So the current Chatterbox path is stream-shaped at the API level, but not incremental in behavior.

That does not mean `SpeakSwiftly` should adopt a deferred whole-waveform live model.

It means `SpeakSwiftly` needs to create its own chunked live delivery plan on top of non-streaming backend calls.

## Core Conclusion

`SpeakSwiftly` should distinguish between two backend capabilities:

- native incremental audio generation
- chunk-at-a-time audio generation

For the second group, the package should synthesize text chunks one after another and stream those completed chunk waveforms into playback as they become available.

That is still a streaming live-playback experience from the caller's point of view.

The only thing that changes is where chunking happens:

- incremental backends chunk in model generation
- non-streaming backends chunk in request orchestration

## Design Goals

- Keep the public `generate_speech` surface unchanged.
- Preserve the existing playback queue and `PlaybackController`.
- Preserve the current fast path for genuinely streaming backends.
- Give non-streaming backends a live path that starts early and stays continuous.
- Keep segmentation and chunk scheduling in generation or runtime code, not in playback.
- Avoid introducing a second playback subsystem or a fake deferred-live abstraction.

## Recommended Internal Model

### One Live Generation Strategy Per Request

The runtime should stop assuming that every backend maps directly to one raw `AsyncThrowingStream<[Float], Error>` coming from the model.

Instead, it should choose one internal live-generation strategy:

- native incremental streaming
- orchestrated chunked synthesis

The important distinction is not whether the output eventually reaches playback as chunks.

The real distinction is:

- does the backend produce those chunks itself during generation
- or does the runtime have to segment the text and synthesize each segment separately

One reasonable internal enum would look conceptually like:

- `.incremental(AsyncThrowingStream<[Float], Error>)`
- `.chunkedText([LiveSpeechTextChunk])`

Another reasonable shape would resolve chunks lazily instead of up front, but the model should stay the same:

- incremental backend: one model stream
- non-streaming backend: many sequential model calls over one segmented request

## Chunked Live Playback Model

For non-streaming backends, one live speech request should become a sequence of text chunks.

The runtime should:

1. normalize the full request text
2. segment that normalized text into speakable chunks
3. synthesize chunk 1
4. feed chunk 1 audio into playback
5. while chunk 1 is draining, synthesize chunk 2
6. feed chunk 2 audio into playback
7. continue until the chunk list is exhausted

That is the package-side equivalent of streaming.

It does not require the backend to decode partial audio within a chunk. It only requires the runtime to keep chunk boundaries and synthesis order under its own control.

## Chunking Requirements

The chunking pass should be text-first, not waveform-first.

That means:

- split on paragraph and sentence boundaries when possible
- keep chunks large enough to avoid choppy cadence
- keep chunks small enough that first audible response does not take too long
- preserve natural pauses instead of arbitrarily slicing by character count alone

This chunking should live alongside the normalization and generation policy work, not in playback.

Playback should only receive audio chunks that are already ready to schedule.

## Why This Is Better Than Whole-Waveform Deferral

Waiting for the whole response waveform before playback starts would give us:

- the full first-response delay of the backend
- worse interactive feel
- no meaningful advantage unless we needed offline-only rendering semantics

Chunked synthesis avoids that.

It keeps the user-facing behavior closer to the current Qwen path:

- first audible output starts after the first chunk finishes
- later chunks continue arriving during playback
- the playback system still operates on real buffer growth rather than one giant tail buffer

## Ownership Boundary

The cleanest ownership split is:

- generation or runtime owns text segmentation and chunk synthesis order
- playback owns buffering, preroll, rebuffer, drain, and output-device behavior

`PlaybackController` should not be asked to understand text segments or backend chunk strategy.

It should still just consume audio chunks.

The likely seams for the new behavior are:

- `AnySpeechModel`
- the resident-generation helper currently named `residentGenerationStream(...)`
- `handleQueueSpeechLiveGeneration(...)`
- generation policy helpers that already know about text shape

## Progress Model

The current progress stages are too playback-centric for orchestrated chunk synthesis.

For non-streaming chunked backends, the runtime should add one chunk-generation stage such as:

- `generating_live_audio_chunk`

That stage should mean:

- the live request is active
- playback may or may not already be draining earlier chunks
- the runtime is currently synthesizing the next text chunk

That stage is more honest than pretending the request is in `buffering_audio` before any chunk audio exists.

One likely event flow for the first chunk:

- `loading_profile`
- `starting_playback`
- `generating_live_audio_chunk`
- `buffering_audio`
- `preroll_ready`

For later chunks, the runtime could emit chunk-generation trace or info events without resetting the whole playback lifecycle.

## Suggested Internal Shape

One concrete implementation direction:

1. Add an internal live-generation strategy enum.
2. Keep the current stream-based path for native incremental backends.
3. Add a segmented text plan for non-streaming backends.
4. Add one runtime helper that turns a segmented text plan into sequential backend synthesis tasks.
5. Yield each completed chunk waveform into the existing playback continuation as soon as it is ready.
6. Keep playback logic unchanged except for any event wording that needs to acknowledge chunked synthesis progress.

This keeps the architecture thin:

- one runtime
- one generation subsystem
- one playback subsystem
- one player
- one additional internal strategy split

## Validation Plan

The first implementation pass should prove behavior in three layers.

### Unit Coverage

- one test for native incremental backends keeping the current path
- one test for chunked backend segmentation order
- one test for chunk synthesis feeding playback chunks in order
- one test for preserving chunk text boundaries and final concatenation semantics

### Runtime Coverage

- one runtime test for first chunk reaching playback before later chunks finish synthesis
- one runtime test for cancellation during chunk 1 synthesis
- one runtime test for cancellation between chunk syntheses
- one runtime test for chunk-N failure after earlier playback has already begun

### E2E Coverage

- keep the Chatterbox audible lane
- update it to assert that playback begins after the first synthesized chunk rather than after full-request synthesis
- add trace expectations showing multiple synthesized chunk windows feeding one live playback request

## Near-Term Recommendation

Do not widen the player into a deferred whole-waveform live system.

The next implementation pass should instead:

- add the internal live-generation strategy split
- add text segmentation for non-streaming backends
- synthesize those chunks sequentially
- feed completed chunk waveforms into the existing playback buffer as they finish
- keep the public `generate_speech` surface unchanged

That gives `SpeakSwiftly` one honest and useful live-playback story for both:

- genuinely streaming backends
- non-streaming backends that can still behave like streaming systems once the runtime owns text chunking and synthesis order
