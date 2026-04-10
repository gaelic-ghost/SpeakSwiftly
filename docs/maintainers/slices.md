# TextForSpeech Profiles, Replacements, and Slices

## Why this exists

This note explains the current `TextForSpeech` model in maintainer terms, with special attention to three ideas that are easy to conflate:

- normalization profiles
- text replacements
- slices

The first two are now first-class public API in the extracted `TextForSpeech` package and are wired through `SpeakSwiftly.Runtime`. The third is still only partially formalized, but it now lives squarely in SpeakSwiftly's own `DeepTrace` surface instead of pretending to be a public `TextForSpeech` responsibility.

## Normalization profile

A normalization profile is the reusable custom rule set that rides on top of the always-on base normalizer.

Today that type is `TextForSpeech.Profile`. It stays intentionally small:

- `id`
- `name`
- `replacements`

The important design choice is that a profile is not the whole normalization engine. It does not carry request-local path context, detected format, or runtime-owned persistence state. It answers a narrower question:

> "What custom rewrite rules should run around the built-in speech-safe normalizer?"

That keeps the responsibilities clean:

- `TextForSpeech.Context` carries request-local environment like `cwd`, `repoRoot`, and optional `format`.
- `TextForSpeech.Profile` carries the reusable custom replacement policy.
- `TextForSpeechRuntime` owns the active custom profile, stored named profiles, and persistence.
- the built-in normalizer remains always on through the base profile and the concrete normalization passes.

So when a normalization job starts, the mental model is:

1. choose or detect the input format
2. snapshot the effective profile for that job
3. run the built-in normalizer plus the selected custom replacements

## Text replacements

Text replacements are the custom rules inside a profile.

Today that type is `TextForSpeech.Replacement`. Each replacement describes:

- what text to match
- what spoken text to substitute
- how to match it
- when to run it
- which formats it applies to
- how strongly it should win against other rules

The important fields are:

- `text`
  The source text to look for.
- `replacement`
  The spoken form you want after the rule runs.
- `match`
  Exact phrase matching or whole-token matching.
- `phase`
  Either `beforeNormalization` or `afterNormalization`.
- `formats`
  A format filter for rules that should only apply to some input families.
- `priority`
  Higher priority wins first within the same phase.
- `isCaseSensitive`
  Whether matching should stay strict.

The simplest way to think about a replacement is:

> "If this source text shows up in this kind of input, rewrite it to this more speakable form at this point in the pipeline."

Good replacement use cases include:

- project-specific proper nouns
- acronyms the built-in normalizer says badly
- identifiers or symbols that need a preferred spoken form
- repeated annoying phrases in logs or CLI output
- downstream app terminology that should sound natural when read aloud

## Replacement phases

The phase split is still the part that matters most architecturally.

`beforeNormalization` means:

- run this rule before the built-in normalizer rewrites paths, identifiers, links, and code-ish text
- use this when you need to protect or rename hard-to-speak source text before the built-ins touch it

`afterNormalization` means:

- run this rule after the built-in normalizer has already made the text more speakable
- use this when you want final-pass polish on the spoken output

That is why the runtime executes phase-aware selections instead of treating replacements as one flat bag of rules.

## Input formats

Formats are the coarse input taxonomy.

Today that type is `TextForSpeech.Format`, with cases such as:

- `plain`
- `markdown`
- `html`
- `source`
- `swift`
- `python`
- `rust`
- `log`
- `cli`
- `list`

The important behavior is that formats can match hierarchically. For example, `.source` matches `.swift`, `.python`, and `.rust`.

The second important behavior is that format is now optional in `TextForSpeech.Context`. Callers can provide it when they know better, but the package can also detect a likely format when it is omitted.

So the model gives us a useful middle ground:

- one rule can target all source code
- another rule can target only Swift source
- a caller can skip format selection entirely and let `TextForSpeech` infer it

## Runtime ownership

The runtime-owned profile holder is `TextForSpeechRuntime`.

It now owns:

- `baseProfile`
  The always-on built-in normalization layer.
- `customProfile`
  The active custom profile layered on top of the base profile.
- `profiles`
  Stored named custom profiles.
- `persistenceURL`
  The configured persistence location, when persistence is enabled.

The core runtime operations are:

- `snapshot(named:)`
- `profile(named:)`
- `storedProfiles()`
- `use(_:)`
- `store(_:)`
- `createProfile(id:named:replacements:)`
- `removeProfile(named:)`
- `addReplacement(_:)`
- `addReplacement(_:toStoredProfileNamed:)`
- `replaceReplacement(_:)`
- `replaceReplacement(_:inStoredProfileNamed:)`
- `removeReplacement(id:)`
- `removeReplacement(id:fromStoredProfileNamed:)`
- `load()`
- `save()`
- `restore(_:)`

The concurrency model is still snapshot-per-job:

- UI or config reload can change the active profile immediately
- already-started jobs keep the snapshot they began with
- later jobs see the updated effective profile

## What a package consumer can do today

Today a `SpeakSwiftly` consumer can use the text-profile system end to end.

At the `TextForSpeech` layer, a consumer can:

- construct `TextForSpeech.Profile` values
- construct `TextForSpeech.Replacement` values
- normalize text directly through `TextForSpeech.normalize`
- manage active and stored profiles through `TextForSpeechRuntime`
- persist or reload text-profile state through `TextForSpeechRuntime`

At the `SpeakSwiftly` layer, a consumer can now:

- inspect `activeTextProfile()`
- inspect `baseTextProfile()`
- inspect `textProfile(named:)`
- inspect `textProfiles()`
- inspect `effectiveTextProfile(named:)`
- create and store named text profiles
- select an active text profile
- add, replace, and remove text replacements on both the active profile and stored named profiles
- pass `textProfileName` and `textContext` into `speak(...)`

So the earlier “public model exists, but the speech runtime does not actually use it” gap is closed now.

## How profiles and replacements are added today

Profiles can still be built as plain value types, but the runtime editing workflow is now first-class.

Value-style setup still works:

1. build a `TextForSpeech.Profile`
2. put `TextForSpeech.Replacement` values into its `replacements` array
3. hand that profile to `TextForSpeechRuntime` through `use(_:)` or `store(_:)`

But the runtime-owned editing path is now available too:

- `createProfile(id:named:replacements:)`
- `addReplacement(_:)`
- `addReplacement(_:toStoredProfileNamed:)`
- `replaceReplacement(_:)`
- `replaceReplacement(_:inStoredProfileNamed:)`
- `removeReplacement(id:)`
- `removeReplacement(id:fromStoredProfileNamed:)`

That means callers no longer have to rebuild whole profile values for every small persisted edit.

## Default profile behavior

There are now three profile concepts that matter:

- `TextForSpeech.Profile.base`
  The always-on built-in base behavior.
- `TextForSpeech.Profile.default`
  The default empty custom profile.
- `TextForSpeechRuntime.customProfile`
  The currently active custom profile for that runtime.

The effective profile for a job is:

1. `baseProfile`
2. merged with the selected stored profile, if one was requested
3. otherwise merged with `customProfile`

So the system is intentionally hybrid:

- the built-in normalization behavior is never accidentally disabled
- custom profiles extend or override that base behavior
- the active custom profile still behaves like the editable default layer for a runtime

## Persistence

Yes, `TextForSpeech` profiles are now persisted by the package when a runtime is configured with a `persistenceURL`.

Persistence is JSON-backed today through:

- `TextForSpeech.PersistedState`
- `TextForSpeech.PersistenceError`
- `TextForSpeechRuntime.load()`
- `TextForSpeechRuntime.save()`
- `TextForSpeechRuntime.restore(_:)`

In `SpeakSwiftly`, the live runtime wires that persistence into the speech-facing text-profile helpers. The adjacent `TextForSpeech` runtime state is loaded on startup and saved after text-profile edits.

YAML and hot reload are still future work; the persisted model today is intentionally smaller and package-owned.

## What “slices” means today

There is still not a first-class public type literally named `Slice`.

But the slice-like structure is no longer private implementation detail either. The public `TextForSpeech` surface now exposes:

- `TextForSpeech.ForensicFeatures`
- `TextForSpeech.Section`
- `TextForSpeech.SectionWindow`
- `TextForSpeech.sections(originalText:)`
- `TextForSpeech.sectionWindows(originalText:totalDurationMS:totalChunkCount:)`

Those sectioning APIs still behave like the first real draft of a slice system:

1. split by Markdown headers if present
2. otherwise split by paragraphs
3. otherwise fall back to one full-request section

So “slice” is still best understood as a maintainer concept rather than a public product name. But the structural data behind that idea now lives in `TextForSpeech`, not in a private `SpeakSwiftly`-only normalizer.

## Practical mental model

If you only need one concise model in your head, it should be this:

- `Context`
  Request-local environment and optional format hint.
- `Format`
  The broad input family, either caller-specified or detected.
- `Profile.base`
  The always-on built-in normalization layer.
- `customProfile`
  The active editable custom layer for a runtime.
- `profiles`
  Stored named custom layers.
- `Replacement`
  One custom rewrite rule inside a profile.
- `snapshot(named:)`
  The effective profile captured for one job.
- `Section` and `SectionWindow`
  Public forensic structure that already behaves like the first draft of slices.

The thing to avoid conceptually is blurring “always-on base normalization,” “active custom edits,” and “stored named custom profiles” into one flat bucket. The current system is cleaner than that on purpose.
