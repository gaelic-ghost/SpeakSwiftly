# Queue Persistence Core Data Plan

## Goal

Persist generation and playback queue state so a future runtime can explain, recover, or intentionally discard queued work after a worker restart.

The first persisted version should restore only work that is safe to replay. It should not pretend an interrupted model stream or partially played audio buffer can resume from the exact sample where the previous process stopped.

## Apple API Rule

Apple documents `NSPersistentContainer` as the object that sets up the Core Data model, context, and store coordinator together. Apple also documents `NSManagedObjectContext` as queue-confined: work that touches managed objects belongs on the context queue through `perform`, `performAndWait`, or the async `perform` API.

For SpeakSwiftly, that means queue persistence should be owned by a small persistence component that receives value snapshots from the runtime and writes them through one Core Data context boundary. Runtime queue actors should pass plain `Sendable` values into that component, not managed objects.

## Scope

Persist these queue records:

- generation queued records
- playback queued records
- active generation markers
- active playback markers
- terminal cancellation or discard reason for records removed during recovery

Do not persist:

- resident model objects
- live model stream iterators
- `AVAudioEngine` state
- queued PCM buffers
- task handles, continuations, or actor-isolated runtime objects

## Data Model

Use one Core Data store for runtime queue state.

`QueueRecord`

- `requestID: String`
- `queueType: String`, either `generation` or `playback`
- `operation: String`
- `state: String`, such as `queued`, `active`, `completed`, `cancelled`, or `discarded`
- `position: Int64`
- `createdAt: Date`
- `updatedAt: Date`
- `payloadJSON: Data`
- `requestContextJSON: Data?`
- `recoveryPolicy: String`
- `terminalReason: String?`

`QueueRecoveryEvent`

- `id: UUID`
- `requestID: String`
- `queueType: String`
- `event: String`
- `reason: String`
- `createdAt: Date`

## Runtime Write Points

Write or update records at these runtime moments:

- request accepted into the generation queue
- generation job reserved as active
- generation job finishes, fails, or is cancelled
- playback state created for live speech
- playback state enters the waiting queue
- playback starts
- playback finishes, fails, or is cancelled
- queue-specific clear operations remove waiting work
- queue-specific cancel operations remove active or waiting work

The persistence call should be best-effort for status updates, but request acceptance should fail loudly if the future configuration declares durable queue persistence mandatory.

## Recovery Policy

On startup, load persisted records before accepting new work.

Handle records this way:

- `generation` + `queued`: restore only if the request payload can be decoded into a current `WorkerRequest`.
- `generation` + `active`: mark discarded with a clear recovery event; the previous model stream cannot be resumed.
- `playback` + `queued`: restore only if the dependent generation has already completed and the audio source is a retained artifact.
- `playback` + `active`: mark discarded; partially played live audio should not restart without explicit operator action.

A future operator command can expose these recovery events so hosts can explain what was restored or discarded after restart.

## Public Surface

Keep the current queue-specific controls as the operator vocabulary:

- `clear_generation_queue`
- `clear_playback_queue`
- `cancel_generation`
- `cancel_playback`
- `list_generation_queue`
- `list_playback_queue`

Add persistence inspection later as a separate surface, for example:

- `get_queue_persistence`
- `list_queue_recovery_events`

Do not overload `list_generation_queue` or `list_playback_queue` with historical recovery events; those should stay snapshots of current runtime work.

## Validation Plan

Add unit coverage with an in-memory Core Data store first:

- enqueue generation, persist, restore queued generation
- reserve generation as active, restart, mark active generation discarded
- enqueue playback for retained artifact, persist, restore playback
- active playback on restart becomes discarded
- `clear_generation_queue` writes generation cancellation events only
- `clear_playback_queue` writes playback cancellation events only
- `cancel_generation` and `cancel_playback` preserve queue-specific terminal reasons

Add one file-backed persistence test after the model shape stabilizes, using a temporary store directory and no real MLX model.
