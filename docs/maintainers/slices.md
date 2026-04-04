# TextForSpeech Profiles, Replacements, and Slices

## Why this exists

This note explains the current `TextForSpeech` model in maintainer terms, with special attention to three ideas that are easy to conflate:

- normalization profiles
- text replacements
- slices

The first two are first-class public API today. The third is only partially formalized today and mostly shows up through forensic sectioning in `SpeechTextNormalizer`.

## Normalization profile

A normalization profile is the top-level policy object for text cleanup before speech generation.

Today that type is [`TextForSpeech.Profile`](/Users/galew/Workspace/SpeakSwiftly/Sources/TextForSpeechCore/TextForSpeech.swift#L84). It is intentionally small:

- `id`
- `name`
- `replacements`

Conceptually, a profile answers the question:

> "Given this kind of input, what custom text-shaping rules should run around the built-in normalizer?"

The important design choice here is that the profile does not try to own everything about normalization. It does not currently carry path context, input text, or runtime state. It is just the reusable rule set.

That keeps the responsibilities clean:

- `TextForSpeech.Context` carries request-specific environment like `cwd` and `repoRoot`.
- `TextForSpeech.Kind` says what the input is, such as Markdown, plain text, or Swift source.
- `TextForSpeech.Profile` carries the reusable custom policy.

So when a normalization job starts, the mental model is:

1. identify the input kind
2. capture the current profile snapshot
3. apply the built-in normalizer with that profile and context

## Text replacements

Text replacements are the actual custom rules inside a profile.

Today that type is [`TextForSpeech.Replacement`](/Users/galew/Workspace/SpeakSwiftly/Sources/TextForSpeechCore/TextForSpeech.swift#L45). Each replacement describes:

- what text to match
- what spoken text to substitute
- how to match it
- when to run it
- which input kinds it applies to
- how strongly it should win against other rules

The important fields are:

- `text`
  This is the source text to look for.
- `replacement`
  This is the spoken form you want after the rule runs.
- `match`
  Right now this is either exact phrase matching or whole-token matching.
- `phase`
  This is either `beforeNormalization` or `afterNormalization`.
- `kinds`
  This scopes a rule to a subset of input kinds.
- `priority`
  Higher priority wins first within the same phase.
- `isCaseSensitive`
  This keeps the caller in control of whether matching should be strict.

The simplest way to think about a replacement is:

> "If this specific text shows up in this kind of input, rewrite it to this more speakable form at this point in the pipeline."

Examples of good replacement use cases:

- project-specific proper nouns
- acronyms the built-in normalizer says badly
- identifiers or symbols that need a preferred spoken form
- repeated annoying phrases in logs or CLI output
- downstream app terminology that should sound natural when read aloud

## Replacement phases

The phase split is the part that matters most architecturally.

`beforeNormalization` means:

- run this rule before the built-in normalizer starts rewriting paths, identifiers, links, and code-ish text
- use this when you need to protect or rename hard-to-speak source text before the built-ins touch it

`afterNormalization` means:

- run this rule after the built-in normalizer has already made the text more speakable
- use this when you want final-pass polish on the spoken output

The reason both phases exist is that these solve different problems.

`beforeNormalization` is for source-shape control.
Example:

- convert a product codename or model name into a safer phrase before token splitting or identifier cleanup changes it

`afterNormalization` is for spoken-form cleanup.
Example:

- replace an already-normalized phrase with a more human preferred wording

That is why the current profile API exposes `replacements(for:in:)` instead of one flat replacement list during execution. The runtime needs phase-aware selection, not just a bag of rules.

## Input kinds

Kinds are the coarse input taxonomy.

Today that type is [`TextForSpeech.Kind`](/Users/galew/Workspace/SpeakSwiftly/Sources/TextForSpeechCore/TextForSpeech.swift#L21), with cases such as:

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

The important behavior is that kinds can match hierarchically. For example, `.source` matches `.swift`, `.python`, and `.rust`.

That gives profiles a useful middle ground:

- one rule can target all source code
- another rule can target only Swift source

So the model is specific enough to be useful without exploding into dozens of narrowly coupled profile types.

## Runtime ownership

The current in-memory profile holder is [`TextForSpeechRuntime`](/Users/galew/Workspace/SpeakSwiftly/Sources/TextForSpeechCore/TextForSpeech.swift#L121).

It is intentionally small:

- `profile`
  The currently active profile.
- `profiles`
  Stored named profiles.
- `snapshot(named:)`
  Returns the profile a new job should use.
- `use(_:)`
  Replaces the active profile.
- `store(_:)`
  Adds or updates a named stored profile.
- `removeProfile(named:)`
  Removes a stored profile and resets the active one to default if needed.

The important model here is snapshot-per-job.

That means:

- UI or config reload can change the active profile immediately
- already-started jobs keep the snapshot they began with
- later jobs see the updated profile

This is the right concurrency boundary for the near-term use case because it keeps profile mutation out of the middle of active speech work.

## What a package consumer can do today

Yes, a consumer of this package can use the public `TextForSpeech` profile API today, but there is an important boundary:

- the `TextForSpeech` profile and runtime types are public
- the current `SpeakSwiftly.Runtime` speech path does not yet expose or own a public `TextForSpeechRuntime`

So today a consumer can:

- construct `TextForSpeech.Profile` values
- construct `TextForSpeech.Replacement` values
- create a `TextForSpeechRuntime`
- call `use(_:)`, `store(_:)`, `snapshot(named:)`, and `removeProfile(named:)`
- choose which profile instance they want to treat as active inside their own code

But today a consumer cannot yet:

- inject a `TextForSpeechRuntime` into `SpeakSwiftly.Runtime`
- tell the `SpeakSwiftly` live speech runtime to use a stored named `TextForSpeech` profile
- mutate normalization behavior for active `SpeakSwiftly.Runtime` speech requests through a public runtime-owned profile surface

That is because the current `SpeakSwiftly` runtime still calls the normalizer with the implicit default profile path rather than with a consumer-supplied `TextForSpeechRuntime` snapshot.

So the public API exists, but the end-to-end wiring into the speech runtime is not finished yet.

## How profiles and replacements are added today

Profiles are added in a value-oriented way:

1. build a `TextForSpeech.Profile`
2. put `TextForSpeech.Replacement` values into its `replacements` array
3. give that profile to a `TextForSpeechRuntime` through `use(_:)` or `store(_:)`

There is not yet a higher-level mutating convenience API such as:

- `appendReplacement(...)`
- `updateReplacement(...)`
- `removeReplacement(...)`

Those operations are currently done by constructing a new profile value with the desired replacement array and then replacing or storing that profile.

## Default profile behavior

Yes, there is a default profile concept today.

It exists in three ways:

- `TextForSpeech.Profile()` defaults to `id: "default"`, `name: "Default"`, and an empty replacement list
- `TextForSpeech.Profile.default` is a public convenience value
- `TextForSpeechRuntime` defaults its active profile to `.default`

What does not exist today is a mutable process-wide or package-wide global default profile registry. In other words:

- there is a default profile value
- there is an active profile on each `TextForSpeechRuntime`
- there is not yet a public global mechanism to redefine the package's default profile for every consumer automatically

If a caller wants a different effective default, the current way to do that is to create a `TextForSpeechRuntime` and set its active profile with `use(_:)`.

## Persistence

No, `TextForSpeech` profiles are not currently persisted to disk by the package.

Today the profile model is:

- public
- `Codable`
- in-memory only

That means:

- a consumer can serialize and persist profiles themselves if they want
- the package does not yet provide built-in file IO, YAML loading, hot reload, or profile-database management
- `TextForSpeechRuntime` stores profiles only in memory for the lifetime of that runtime object

This is separate from `SpeakSwiftly` voice profiles in the speech worker, which are persisted on disk through the voice-profile store. The two concepts are different:

- voice profiles are persisted audio+metadata assets used for speech synthesis
- text normalization profiles are currently in-memory rule sets used for text shaping

## What “slices” means today

There is not currently a first-class public `slice` type in `TextForSpeechCore`.

What does exist today is a slice-like concept inside [`SpeechTextNormalizer`](/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift):

- `forensicSections(originalText:)`
- `forensicSectionWindows(originalText:totalDurationMS:totalChunkCount:)`

Those functions currently split text into meaningful segments for playback forensics and observability. The current sectioning strategy is:

1. split by Markdown headers if present
2. otherwise split by paragraphs
3. otherwise fall back to one full-request section

So today, a "slice" is best understood as:

> "A meaningful segment of the original input that can be named, measured, and mapped onto playback."

The existing section model is not yet part of the public `TextForSpeech` namespace, but it already behaves like the first draft of a slice system.

## What slices would likely become

If we promote slices into the public `TextForSpeech` model later, I think they should become a real normalization primitive rather than staying only forensic metadata.

A likely slice model would answer:

- what segment of text is this
- what kind of segment is it
- what context applies inside this segment
- what profile or replacement subset should apply here

In practice, that could grow into something like:

- Markdown header sections
- paragraph slices
- code-block slices
- list-item slices
- log-entry slices
- CLI block slices
- HTML block slices

The important reason to add slices would not be “more structure for its own sake.” It would unlock real near-term behavior:

- apply different normalization strategies to prose versus code blocks in the same request
- preserve a stable mapping between playback diagnostics and the source text segment being spoken
- allow profile rules to target only certain slice kinds later
- make downstream UI or inspection tools show what part of the text was being spoken when playback struggled

That is a durable building-block change if we do it. It would not just be a forensic helper anymore.

## Current mental model

If you want the simplest maintainers’ summary, use this:

- `Context`
  Request-local environment for path shortening and similar context-aware cleanup.
- `Kind`
  What broad family of input this is.
- `Profile`
  The reusable custom normalization policy for a job.
- `Replacement`
  An individual rule inside that profile.
- `Runtime`
  The in-memory owner of the current profile state and named profile snapshots.
- `Sections`, today
  Slice-like forensic structure that exists in the normalizer but is not yet a public `TextForSpeech` model.

## What to avoid

Some boundaries are worth preserving as this grows.

- Do not make the profile carry request-specific path context.
- Do not make replacements own runtime mutation or file watching.
- Do not blur “current active profile state” with “pure normalization rules.”
- Do not describe slices as a shipped public API concept until they really are one.

That separation keeps the current model easy to reason about while still leaving room for a real slice system later.
