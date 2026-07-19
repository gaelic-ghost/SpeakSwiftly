# Normalization Summarization Trust Boundary

Summary-aware normalization is opt-in. When a caller passes `summarize: true`, caller text leaves the deterministic normalization path and enters the selected provider before deterministic speech-safe normalization resumes.

## Caller responsibilities

- Treat live summarization providers as a data-disclosure boundary.
- Redact secrets and sensitive text before enabling summarization.
- Select a provider whose execution and data-handling model fits the caller's policy.
- Do not treat prompt boundaries as a guarantee that prompt injection has been removed.

## Package protections

- Provider prompts put caller text inside one escaped `SPEAKSWIFTLY_UNTRUSTED_NORMALIZATION_CONTENT` boundary and instruct the provider to treat it as data.
- Provider input is limited to 50,000 characters.
- Accepted provider output is limited to 64 KiB.
- `.codexExec` drains stdout and stderr while the child runs, limits stderr to 16 KiB, terminates on timeout or cancellation, and has a 20-second default timeout.
- `.openAIResponses` requires `OPENAI_API_KEY`, sends `store: false`, and limits output tokens.
- `.foundationModels` reports unavailable devices or builds explicitly instead of silently selecting another provider.
- `.test` remains deterministic and does not leave the process.

These protections bound execution and make the trust boundary visible. They do not redact caller content or promise prompt-injection immunity.

## Configuration

`SPEAKSWIFTLY_NORMALIZATION_OPENAI_SUMMARY_MODEL` selects the model used by `.openAIResponses`. Provider selection is persisted as part of `SpeakSwiftly.TextNormalizationState`; whether to summarize remains an explicit per-call choice.

## Verification

`SpeakSwiftlyNormalizationTests/Normalization/SummaryProviderSecurityTests.swift` covers prompt-boundary escaping, input limits, child-process output backpressure, timeout termination, and bounded error output.

The imported implementation descends from the standalone TextForSpeech security hardening completed in version 0.23.0. Its earlier May 2026 scan identified the pre-hardening `.codexExec` pipe deadlock; the migrated bounded runner and regression tests preserve that remediation inside SpeakSwiftly.
