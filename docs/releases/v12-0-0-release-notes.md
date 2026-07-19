# v12.0.0 Release Notes

SpeakSwiftly 12 integrates text normalization, summarization, profiles, and persistence into the SpeakSwiftly package so those features can evolve with speech generation through one package graph and one release cycle.

## What Changed

- Added the internal, non-vended `SpeakSwiftlyNormalization` target for pure normalization and summarization algorithms and their value models.
- Made `SpeakSwiftly.Normalizer` the single actor that owns built-in style, summarization-provider selection, stored profiles, active profile selection, and persistence.
- Added focused `style`, `profiles`, `summarization`, and `persistence` handles.
- Added one typed internal processing path for ordinary text and explicitly typed whole-source input.
- Moved shared `RequestContext`, `TextFormat`, and `SourceFormat` values into `SpeakSwiftlyCore` so vended output products do not expose an internal target.
- Removed the external TextForSpeech dependency and now resolve Swift Markdown and SwiftSoup directly.
- Preserved normalization-state version 1 and the existing persistence location. Existing state using `summaryProvider` is read and rewritten with canonical `summarizationProvider`.
- Preserved text-profile worker coding keys such as `profile_id` and `replacement_count`.
- Migrated the standalone normalization and summary-provider security tests into the SpeakSwiftly test graph.
- Renamed the OpenAI summary-model override to `SPEAKSWIFTLY_NORMALIZATION_OPENAI_SUMMARY_MODEL`.

## Breaking Changes

- Swift callers use `SpeakSwiftly.TextReplacement`, `SpeakSwiftly.TextProfile`, `SpeakSwiftly.RequestContext`, `SpeakSwiftly.TextFormat`, `SpeakSwiftly.SourceFormat`, and the other SpeakSwiftly-owned normalization names instead of importing TextForSpeech.
- Generation JSONL accepts only `voice_profile` and `text_profile`. Removed generation aliases `profile_name` and `text_profile_id` now return an actionable invalid-request error.
- Text-profile management retains `text_profile_id` where it is the actual identifier for the profile resource being read or mutated.
- Consumers that depended directly on TextForSpeech must remove that package dependency and route normalization state and operations through `SpeakSwiftly.Normalizer`.
- The former `TEXT_FOR_SPEECH_OPENAI_SUMMARY_MODEL` environment variable is not read.

## Migration

1. Remove TextForSpeech from the consumer package manifest.
2. Replace direct imports and types with their `SpeakSwiftly` equivalents.
3. Obtain the runtime-owned normalizer from `runtime.normalizer`, or construct `SpeakSwiftly.Normalizer` and inject it through `SpeakSwiftly.Configuration`.
4. Use `normalizer.style`, `.profiles`, `.summarization`, and `.persistence` for state operations.
5. Use `normalizer.speechText(...)` for ordinary text and `normalizer.speechSource(_:as:...)` for explicitly typed whole-source input.
6. Update generation JSONL payloads to `voice_profile` and `text_profile`.
7. Rename any OpenAI summarization model override to `SPEAKSWIFTLY_NORMALIZATION_OPENAI_SUMMARY_MODEL`.

## Security

Summarization remains opt-in per call. Provider input and output are bounded, caller text is marked as untrusted prompt content, `.codexExec` execution is timeout- and cancellation-bound, and the OpenAI provider sends `store: false`. Callers still own redaction and provider selection for sensitive input; prompt boundaries do not guarantee prompt-injection removal.

## Verification

- `swift package dump-package`
- `swift build`
- `swift test`
- `bash scripts/repo-maintenance/validate-all.sh`
- release workflow validation for `v12.0.0`
