# TextForSpeech Consumer Audit

This audit records the organization-wide dependency state after TextForSpeech
normalization and summarization moved into the internal
`SpeakSwiftlyNormalization` target in SpeakSwiftly 12.

## Result

No active consumer resolves or imports TextForSpeech.

The standalone TextForSpeech repository remains the frozen historical source.
Its own package, source, tests, and retirement documentation necessarily retain
the name. Historical release notes and migration documents in other
repositories also retain the name as provenance; those references are not
dependency edges.

## Active Consumer Inventory

| Repository or lane | Authoritative state | Result |
| --- | --- | --- |
| SpeakSwiftly | `main` at merge commit `ea4fdd2a2c082250be2d410ead8e5e4a123d7c8d` | Owns `SpeakSwiftlyNormalization`; no TextForSpeech package dependency or import. |
| SpeakSwiftlyServer | `main` at the SpeakSwiftlyServer 12 release merge commit `8c8bf17ad27aaf5dcef14b4b053939ee9d202bc8` | Resolves SpeakSwiftly 12 and exposes its normalization models without TextForSpeech. |
| SayBar | `main` at merge commit `2355db724a04d6b7396581fd42e1d4eefaaa0b19` | Resolves SpeakSwiftlyServer 12; its direct TextForSpeech pin is removed. |
| SpeakSwiftlyMobile | default branch and organization code search | Contains historical planning references only; no package dependency or import. |
| SpeakSwiftlyPrivate active research lane | `research/demodokos-foundry-v4` at `0ee5e8d1f4a80b5904f32915c1af2d968d142a10` | Merged SpeakSwiftly 12 specifically to remove the standalone dependency; no active package dependency or import remains. |

## SpeakSwiftlyPrivate Default-Branch Exception

`SpeakSwiftlyPrivate/main` remains at the older June 2026 research snapshot
`fe1c6dfce7c678cacaa6f3c66d60603086bef1a2`. That dormant snapshot predates
SpeakSwiftly 12 and still declares TextForSpeech. It is not the active research
lane and no repository in the organization resolves SpeakSwiftlyPrivate.

The repository has exactly two branches. The checked-out and most recently
updated research branch is `research/demodokos-foundry-v4`; commit `0ee5e8d`
merged SpeakSwiftly 12 into that lane with the explicit breaking-change note
that the standalone TextForSpeech dependency was removed. Promoting the entire
research lane to the default branch solely to erase a code-search result would
also promote more than 52,000 lines of unrelated restricted model research, so
this audit records the branch distinction instead of changing research history
or scope.

## Verification Method

The audit used GitHub organization code search over default branches for all of
the following dependency signals:

- `import TextForSpeech`
- TextForSpeech references in `Package.swift`
- TextForSpeech references in `Package.resolved`
- the canonical `github.com/gaelic-ghost/TextForSpeech` dependency URL

It then inspected both SpeakSwiftlyPrivate branches directly because GitHub
organization code search only reports the default branch. The active research
branch's manifest, resolved graph, source tree, and tests contain no dependency
or import; its remaining matches are historical documentation.

A reverse organization search found no package manifest, resolved graph, or
source reference that consumes SpeakSwiftlyPrivate. The audit therefore treats
its stale default branch as a dormant source snapshot, not an active consumer.

## Retirement Boundary

This audit does not archive, delete, or rewrite TextForSpeech. GitHub archival
remains a separate explicit decision. The complete unfinished-roadmap mapping
is recorded in
`textforspeech-roadmap-migration-2026-07-19.md`.
