# Text Profiles, Replacements, and Slices

## Why this exists

This note explains the current post-`TextForSpeech 0.18.9` model in maintainer terms.

The three concepts that most often get conflated are:

- built-in style
- custom text profiles
- deep-trace slices

Those now live in three different places on purpose.

## The current model

`SpeakSwiftly` now treats text normalization as one shared `TextForSpeech.Runtime` with three public handles exposed through `SpeakSwiftly.Normalizer`:

- `style`
  The built-in narration style such as `balanced`, `compact`, or `explicit`.
- `profiles`
  The stored custom profile library plus the active custom profile.
- `persistence`
  The persisted runtime state on disk or in memory.

That split is the public simplification. Generation then uses one shared `SpeakSwiftly.Normalizer.speechText(...)` entry point to call the async `TextForSpeech.Normalize` APIs, so live playback, retained files, source-format handling, custom profiles, built-in style, and summarization-provider selection all pass through the same package-owned path.

We no longer expose a mixed bag of “style plus active profile plus stored profiles plus raw replacement list” helpers on one surface, and we no longer support whole-profile replace/store/use workflows through `SpeakSwiftly`.

## Built-In Style

Built-in style is the broad normalization posture provided by `TextForSpeech`.

It answers:

> “How verbose should the built-in code-and-text narration be before any custom profile rules are layered on top?”

That setting is:

- runtime-owned
- persisted
- separate from the active custom profile

The maintainer-facing operations are now:

- `normalizer.style.getActive()`
- `normalizer.style.list()`
- `normalizer.style.setActive(to:)`

The JSONL transport mirrors that split:

- `get_active_text_profile_style`
- `list_text_profile_styles`
- `set_active_text_profile_style`

## Custom Text Profiles

Custom text profiles are the stored reusable rule sets layered on top of the built-in style.

The important point is that stored profiles are now addressed by stable identifier, not by mutable display name.

Each stored profile has:

- a stable identifier exposed as `profileID` in `SpeakSwiftly.TextProfileDetails` and `profile_id` in JSONL payloads
- a mutable human-facing `name`
- a `replacements` array

The transport models on the SpeakSwiftly side are:

- `SpeakSwiftly.TextProfileSummary`
- `SpeakSwiftly.TextProfileDetails`

Those are transport wrappers around the underlying `TextForSpeech.Runtime.Profiles.Summary` and `.Details` shapes.
They are also the public Swift return models for text-profile reads and mutations; the raw `TextForSpeech.Runtime.Profiles.*` models stay behind the `SpeakSwiftly` API boundary.

## Profile Lifecycle

The profile library is now intentionally small and explicit.

At the Swift surface:

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

At the JSONL surface:

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

Important consequences:

- profile creation is name-only
- the runtime derives the stable profile ID
- names are labels, not lookup keys
- “clear all replacements” is no longer a separate operation
- “store this whole profile object” is no longer a supported mutation path
- “replace the active profile with this raw profile payload” is no longer supported

If a caller wants an empty profile again, the supported operation is `reset`, not “clear replacements.”

## Replacements

Replacements are still `TextForSpeech.Replacement`.

They are still the custom rules inside a profile, but the allowed mutation path is now narrower:

- add one replacement
- patch one replacement
- remove one replacement

At the Swift surface:

- `normalizer.profiles.addReplacement(_:)`
- `normalizer.profiles.addReplacement(_:toProfile:)`
- `normalizer.profiles.patchReplacement(_:)`
- `normalizer.profiles.patchReplacement(_:inProfile:)`
- `normalizer.profiles.removeReplacement(id:)`
- `normalizer.profiles.removeReplacement(id:fromProfile:)`

At the JSONL surface:

- `create_text_replacement`
- `replace_text_replacement`
- `delete_text_replacement`

The optional `text_profile_id` on those JSONL operations means:

- omitted: mutate the active custom profile
- present: mutate that stored profile directly

## Effective Normalization

For any single generation request, the mental model is:

1. pick the built-in style
2. pick the requested stored custom profile, or the active custom profile when the request does not name one
3. snapshot the active TextForSpeech summarization provider
4. normalize the input text with request-local source format and `TextForSpeech.InputContext`

That is why the generation APIs now carry `textProfile` rather than `textProfileName`.

The generation request is selecting a stored profile by stable identifier, not by mutable label.

The typed generation surface also keeps text-shaping and caller metadata separate:

- `inputTextContext`: how to interpret the text itself
- `requestContext`: what app, agent, project, or topic the request belongs to

## Persistence

Persistence now belongs to the runtime state as a whole, not to ad hoc profile blobs.

At the Swift surface:

- `normalizer.persistence.url()`
- `normalizer.persistence.state()`
- `normalizer.persistence.restore(_:)`
- `normalizer.persistence.load()`
- `normalizer.persistence.load(from:)`
- `normalizer.persistence.save()`
- `normalizer.persistence.save(to:)`

At the JSONL surface:

- `get_text_profile_persistence`
- `load_text_profiles`
- `save_text_profiles`

The persisted shape is `TextForSpeech.PersistedState`.

## Wire Shapes

The worker success payload no longer exposes top-level replacement lists for text-profile reads.

The current text-profile response fields are:

- `text_profile`
- `text_profiles`
- `text_profile_style`
- `text_profile_style_options`
- `text_profile_path`

Inside those payloads, the important keys are:

- `text_profile.profile_id`
- `text_profile.summary`
- `text_profile.summary.replacement_count`
- `text_profiles[].id`
- `text_profiles[].replacement_count`

This keeps the JSONL surface aligned with the simplified runtime model instead of leaking older compatibility fields.

## Slices

“Slices” are not part of the text-profile model.

They belong to SpeakSwiftly’s deep-trace analysis of already-normalized content.

That work lives on the `SpeakSwiftly.DeepTrace` side and is still about:

- sections
- section windows
- forensic features
- chunk-to-text analysis

So maintainers should keep the boundary clear:

- `TextForSpeech` owns style, profiles, replacements, normalization, and persisted normalization state
- `SpeakSwiftly` owns generation, playback, runtime orchestration, and deep-trace slicing

## What changed from the old model

The old mental model mixed together:

- whole-profile store/use flows
- name-based profile targeting
- separate replacement-list reads
- broad “clear replacements” cleanup operations
- text-style operations phrased as generic profile-style reads and writes

That model is gone.

The new one is intentionally tighter:

- style is its own handle
- stored profiles are ID-addressed
- creation is name-only
- names are editable labels
- replacements are edited incrementally
- reset and factory-reset are the supported coarse cleanup actions
- transport names stay verb-first snake_case and mirror the real resource ownership
