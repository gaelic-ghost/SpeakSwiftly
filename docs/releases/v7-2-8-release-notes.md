# v7.2.8 Release Notes

## What Changed

- Made Marvis `single_resident_dynamic` the runtime default.
- Moved Marvis resident-policy selection out of the public configuration API
  and kept it as a `SpeakSwiftlyTool` operator override for investigation and
  benchmarking.
- Removed legacy Qwen resident-model selection aliases from the public
  configuration API. Qwen resident model selection now belongs to the concrete
  backend value.
- Removed source-format hints from public generation requests and JSONL request
  decoding. `TextForSpeech` now detects text and source structure from request
  text and path context.
- Kept stored generation artifacts and retained job summaries able to report
  historical or detected source-format metadata.
- Preserved legacy voice-profile manifest loading by normalizing old Qwen
  backend tokens during manifest upgrade.

## Breaking Changes

- Swift generation callers must stop passing `sourceFormat`.
- JSONL generation callers must stop sending `source_format`.
- Public `SpeakSwiftly.Configuration` no longer accepts
  `marvisResidentPolicy` or legacy Qwen resident-model keys.

## Migration Notes

- Use `requestContext` or JSONL `request_context` for path and caller metadata.
- Select Qwen resident model variants with `speechBackend`.
- Use the bundled `SpeakSwiftlyTool --marvis-resident-policy ...` option only
  for local Marvis resident-policy investigation.

## Verification

- `swift build`
- `swift test`
- Quick E2E: pending live-service availability.
