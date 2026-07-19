# TextForSpeech Roadmap Migration

This ledger records where every unfinished item in the frozen TextForSpeech
`ROADMAP.md` moved after normalization and summarization became the internal
`SpeakSwiftlyNormalization` target in SpeakSwiftly 12.

## Issue Inventory

TextForSpeech has no open GitHub issues. Its only historical issue, #33,
was already closed before retirement. SpeakSwiftly issues
[#111](https://github.com/gaelic-ghost/SpeakSwiftly/issues/111) and
[#112](https://github.com/gaelic-ghost/SpeakSwiftly/issues/112) already tracked
the two downstream Markdown projection requests and were updated in place
instead of duplicated.

## Roadmap Mapping

| TextForSpeech source | SpeakSwiftly destination | Coverage |
| --- | --- | --- |
| Product principles | Milestone 35 and issues [#114](https://github.com/gaelic-ghost/SpeakSwiftly/issues/114), [#116](https://github.com/gaelic-ghost/SpeakSwiftly/issues/116), and [#117](https://github.com/gaelic-ghost/SpeakSwiftly/issues/117) | Deterministic shared normalization, namespace-first API discovery, and detection plus documented style behavior are acceptance constraints rather than separate feature work. |
| Milestone 5: Structured Source Normalization | [#114](https://github.com/gaelic-ghost/SpeakSwiftly/issues/114) | SwiftSyntax adoption, structured Swift traversal, generic fallback, representative tests, Python and Rust category decision, documentation, and future language-lane extensibility. |
| Milestone 7: Release and Maintainability Polish | [#118](https://github.com/gaelic-ghost/SpeakSwiftly/issues/118) | Post-consolidation source-role audit, scanability, and current public and maintainer architecture docs. |
| Milestone 8: Summary-Aware Normalization Requests | [#115](https://github.com/gaelic-ghost/SpeakSwiftly/issues/115) | Live provider checks or examples, caller guidance, and the first-class summary-model-selection decision. |
| Milestone 8.1 deferred follow-up | [#119](https://github.com/gaelic-ghost/SpeakSwiftly/issues/119) | Conditional Foundation Models prompt-risk preflight with its downstream-need trigger preserved. |
| Milestone 9: Public API Model Cleanup | [#116](https://github.com/gaelic-ghost/SpeakSwiftly/issues/116) | Persistence archive contract, narrower lifecycle APIs, common replacement authoring, advanced rule access, docs, tests, and release guidance. |
| Milestone 10: Style-Based Normalization Behavior | [#117](https://github.com/gaelic-ghost/SpeakSwiftly/issues/117) | Semantic-run audit, additional `NSDataDetector` kinds, default-spoken-kind decision, developer-token independence, per-family tests, and compact, balanced, and explicit behavior. |
| Milestone 10: Codex Hook Review | [#111](https://github.com/gaelic-ghost/SpeakSwiftly/issues/111), [#112](https://github.com/gaelic-ghost/SpeakSwiftly/issues/112), and [#119](https://github.com/gaelic-ghost/SpeakSwiftly/issues/119) | Proven shared Markdown table and section projection needs are concrete issues; any additional hook behavior remains trigger-gated. |
| Backlog: languages beyond Swift | [#119](https://github.com/gaelic-ghost/SpeakSwiftly/issues/119), with implementation shaped by [#114](https://github.com/gaelic-ghost/SpeakSwiftly/issues/114) | Preserve the decision without adding speculative parsers before Swift proves the shared shape. |
| Backlog: public nested source-format inspection | [#119](https://github.com/gaelic-ghost/SpeakSwiftly/issues/119) | Preserve the concrete-caller trigger without expanding the public API now. |

## Explicitly Retired Items

- The TextForSpeech “next minor release” work completed with the final
  `v0.23.0` retirement release. It is not carried forward as a false
  SpeakSwiftly task.
- GitHub repository archival remains unchecked in TextForSpeech because it
  requires separate explicit approval. It is not part of Milestone 35 and this
  migration does not archive, delete, or rewrite the frozen repository.

## Completion Rule

Milestone 35 is complete when each mapped issue is implemented, explicitly
retired with durable rationale, or remains intentionally trigger-gated in
#119, and when an organization-wide dependency audit confirms no active
consumer still resolves or imports TextForSpeech.
