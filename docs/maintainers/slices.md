# Text Profiles, Replacements, and Slices

## Why this exists

This note explains the current normalization model in maintainer terms.

The concepts that most often get conflated are:

- built-in style
- custom text profiles
- summarization
- deep-trace slices

The first three share one state owner. Deep-trace slices remain a separate analysis concern.

## The current model

`SpeakSwiftly.Normalizer` is the single actor that owns normalization state and lifecycle. It exposes four lightweight handles:

- `style` owns the active built-in narration posture.
- `profiles` owns stored custom profiles, their active selection, and incremental replacement mutations.
- `summarization` owns the active summarization-provider selection.
- `persistence` owns state snapshots and disk reads and writes.

The internal, non-vended `SpeakSwiftlyNormalization` target owns pure normalization and summarization algorithms plus their value models. `SpeakSwiftly` owns the public API, mutable state, persistence lifecycle, and generation integration. This keeps one production path without making package consumers import an implementation target.

Live playback and retained-file generation both call `SpeakSwiftly.Normalizer.speechText(...)`. Explicit whole-source callers use `speechSource(_:as:...)`. Both entry points delegate to the same internal typed normalization request.

## Built-In Style

Built-in style is the broad normalization posture applied before custom profile rules.

It answers:

> “How verbose should built-in code and text narration be before custom rules are layered on top?”

The setting is runtime-owned, persisted, and independent of the active custom profile.

Swift operations:

- `normalizer.style.getActive()`
- `normalizer.style.list()`
- `normalizer.style.setActive(to:)`

JSONL operations:

- `get_active_text_profile_style`
- `list_text_profile_styles`
- `set_active_text_profile_style`

## Custom Text Profiles

Custom text profiles are stored reusable rule sets layered over the built-in style. Stored profiles are addressed by stable identifier rather than mutable display name.

Each profile has:

- a stable `profileID`, encoded as `profile_id` in profile payloads
- a mutable human-facing `name`
- a typed `replacements` array

The public Swift models are `SpeakSwiftly.TextProfileSummary` and `SpeakSwiftly.TextProfileDetails`. Their concrete value storage lives in the internal target, but callers stay on the `SpeakSwiftly` namespace.

## Profile Lifecycle

Swift operations:

- `normalizer.profiles.getActive()`
- `normalizer.profiles.get(id:)`
- `normalizer.profiles.list()`
- `normalizer.profiles.getEffective()`
- `normalizer.profiles.create(name:)`
- `normalizer.profiles.rename(profile:to:)`
- `normalizer.profiles.setActive(id:)`
- `normalizer.profiles.delete(id:)`
- `normalizer.profiles.reset(id:)`
- `normalizer.profiles.factoryReset()`

JSONL operations:

- `get_active_text_profile`
- `get_text_profile`
- `list_text_profiles`
- `get_effective_text_profile`
- `create_text_profile`
- `update_text_profile_name`
- `set_active_text_profile`
- `delete_text_profile`
- `reset_text_profile`
- `factory_reset_text_profiles`

Creation is name-only and derives a stable identifier. Names remain editable labels. Resetting is the supported coarse replacement cleanup; whole-profile replacement and duplicate store/use paths are not part of the API.

## Replacements

Replacement rules use `SpeakSwiftly.TextReplacement` and are mutated incrementally.

Swift operations:

- `normalizer.profiles.addReplacement(_:)`
- `normalizer.profiles.addReplacement(_:toProfile:)`
- `normalizer.profiles.patchReplacement(_:)`
- `normalizer.profiles.patchReplacement(_:inProfile:)`
- `normalizer.profiles.removeReplacement(id:)`
- `normalizer.profiles.removeReplacement(id:fromProfile:)`

JSONL operations:

- `create_text_replacement`
- `replace_text_replacement`
- `delete_text_replacement`

For those profile-management operations, optional `text_profile_id` means “mutate this stored profile”; omitting it means “mutate the active profile.” This is the operation's identifier field, not the removed generation-request alias.

## Effective Normalization

For one request, the normalizer:

1. snapshots the active built-in style
2. selects the requested stored profile or the active profile
3. snapshots the active summarization provider
4. processes text or explicitly typed whole-source input with its request context

Generation callers use `textProfile` to select a stored profile by stable identifier and `requestContext` to carry caller metadata and path context. They do not provide source-format hints through the worker. SpeakSwiftly detects ordinary input structure from text and path context; direct Swift callers can use `speechSource(_:as:...)` when they intentionally possess a whole-source language type.

Markdown tables are projected before inline-code and link normalization. A recognized header and delimiter become a concise column introduction, and each data row becomes labeled speech. Visual pipe and alignment syntax is removed, escaped cell pipes remain content, and ordinary non-table pipe prose is left unchanged.

Summarization is opt-in per normalization call through `summarize: true`. Provider selection remains independent:

- `normalizer.summarization.get()`
- `normalizer.summarization.list()`
- `normalizer.summarization.set(_:)`

## Persistence

Persistence covers the complete normalization state rather than ad hoc profile blobs.

Swift operations:

- `normalizer.persistence.url()`
- `normalizer.persistence.state()`
- `normalizer.persistence.restore(_:)`
- `normalizer.persistence.load()`
- `normalizer.persistence.load(from:)`
- `normalizer.persistence.save()`
- `normalizer.persistence.save(to:)`

JSONL operations:

- `get_text_profile_persistence`
- `load_text_profiles`
- `save_text_profiles`

The public persisted shape is `SpeakSwiftly.TextNormalizationState`. Version 1 preserves the existing profile-state location and reads the former `summaryProvider` key during state migration, but writes only canonical `summarizationProvider` state.

## Wire Shapes

Generation uses only these profile-selection keys:

- `voice_profile`
- `text_profile`

Removed generation aliases `profile_name` and `text_profile_id` are rejected with actionable diagnostics. Text-profile management continues to use `text_profile_id` where the operation genuinely targets a profile resource.

Current text-profile response fields include:

- `text_profile`
- `text_profiles`
- `text_profile_style`
- `text_profile_style_options`
- `text_profile_path`

Nested profile payloads preserve `profile_id` and `replacement_count` coding keys.

## Slices

“Slices” are not part of text normalization. They belong to SpeakSwiftly's deep-trace analysis of already-normalized content: sections, windows, forensic features, and chunk-to-text analysis.

The ownership boundary is:

- `SpeakSwiftlyNormalization` owns pure normalization and summarization algorithms and value models.
- `SpeakSwiftly.Normalizer` owns state, lifecycle, persistence, and the public normalization API.
- SpeakSwiftly generation and playback own speech production and delivery.
- `SpeakSwiftly.DeepTrace` owns post-normalization slicing and analysis.

## What changed from the old model

The removed model had an independent package boundary, duplicate runtime ownership, leaked dependency types, generation compatibility aliases, and parallel decoding paths.

The current model has:

- one package graph and one state owner
- one typed normalization processing path
- four focused public handles
- SpeakSwiftly-owned public names
- stable profile identifiers and incremental replacement edits
- canonical generation wire keys with removed aliases rejected
- an internal target that can evolve with generation without a separate package release cycle
