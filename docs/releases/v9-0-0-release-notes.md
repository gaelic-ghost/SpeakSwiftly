# v9.0.0 Release Notes

## What Changed

- Raised the `TextForSpeech` dependency floor to `0.22.0`.
- Added request-purpose propagation for live speech, retained audio files, and
  generated batches.
- Defaulted live speech requests to preface source/topic provenance and retained
  audio-file requests to omit that preface.
- Preserved caller override control through `request_context.prefacePolicy`.
- Removed the public Swift normalizer `sourceFormat` argument. Text requests now
  rely on `TextForSpeech` source detection.
- Kept generated artifact metadata able to retain historical or detected source
  format values.

## Breaking Changes

- JSONL generation callers that provide `request_context` must include the
  required `reqPurpose` field.
- Swift callers constructing `SpeakSwiftly.RequestContext` must pass
  `reqPurpose`.
- Swift callers of `SpeakSwiftly.Normalizer.speechText` must stop passing
  `sourceFormat`.

## Migration Notes

- Use `request_context.reqPurpose: "speech"` for live playback.
- Use `request_context.reqPurpose: "audioFile"` for retained generated files and
  generated batches.
- Use `request_context.reqPurpose: "audioStream"` for stream-oriented callers.
- Omit `prefacePolicy` to follow the default policy, set `"always"` to force the
  source/topic preface, or set `"never"` to suppress it.
- Do not send `source_format` on generation requests. Source files should carry
  extensions, and text requests use auto-detection.

## Verification

- `swift test`
- `sh scripts/repo-maintenance/validate-all.sh`
