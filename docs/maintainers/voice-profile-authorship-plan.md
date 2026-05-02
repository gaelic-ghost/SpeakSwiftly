# Voice Profile Authorship Plan

## Purpose

This note captures the `SpeakSwiftly` side of package-owned default voice support.

`SpeakSwiftlyServer` wants to ship broad-appeal built-in defaults named `swift-signal` and
`swift-anchor`. The server can own its install command and seed catalog, but this package owns the
stored voice-profile type, profile persistence, profile mutation rules, and reroll behavior. That
means authorship and system-profile immutability need to be modeled here first.

## Goals

- keep ordinary profile creation flows user-owned by default
- let downstream packages install package-owned default voices without mixing them with personal
  voice profiles
- preserve stable seed identity separately from the visible profile name
- make package-owned system profiles refreshable without overwriting user intent
- keep public API additions narrow and only expose metadata application consumers need

## Initial Downstream Built-Ins

`SpeakSwiftlyServer` plans to install two package-owned defaults:

- `swift-signal`: a bright, clear, responsive voice with crisp articulation, quick but controlled
  pacing, and an accessible technical-assistant tone.
- `swift-anchor`: a grounded, steady, warm voice with strong articulation, calm pacing, and a
  reassuring technical-narrator tone.

If the preferred visible name is already occupied by a user profile, `SpeakSwiftlyServer` should
install the package-owned profile with a `-builtin` suffix, such as `swift-signal-builtin`. That
fallback name is a server install policy; the stable seed identity should still be `swift.signal`.

## Authorship Model

Add an author concept to the stored voice profile model:

- `.user`: the default author for all normal voice-design and voice-clone creation flows
- `.system`: package-owned built-ins installed from a trusted seed catalog

The author value should be part of the persisted profile metadata so it survives list, reload,
rename, and runtime restart flows. Existing profiles should migrate as `.user`.

The profile should also be able to carry seed metadata when it comes from a package-owned catalog:

- seed id, such as `swift.signal` or `swift.anchor`
- seed version
- intended profile name
- fallback profile name when one was used
- installed timestamp
- source package or producer
- source package version or commit when available
- sample media path when downstream docs include a preview

The visible profile name remains the operator-facing identifier users type into APIs and tools. The
seed id is the stable package identity used for refresh and provenance.

## Mutation Rules

User-authored profiles keep the current behavior:

- rename mutates the selected profile name
- delete removes the selected profile
- reroll rebuilds the selected profile in place from its persisted source inputs

System-authored profiles should be immutable to ordinary user mutation wherever `SpeakSwiftly` can
enforce that cleanly:

- rename should reject `.system` profiles with an explicit message
- delete should reject `.system` profiles with an explicit message unless a future explicit system
  maintenance operation opts into removal
- reroll should not rebuild a `.system` profile in place

When a user asks to reroll a system-authored profile, `SpeakSwiftly` should create or target a
user-owned copy instead. The copy should use `.user` authorship and should not retain system
immutability. If a system profile was installed as `swift-signal-builtin` because `swift-signal` was
already occupied, a user reroll can naturally target `swift-signal` when that name is available. If
the system profile already owns the preferred name, the copy needs a clear conflict-safe user name.

## Refresh Direction

Refresh should be treated as seed maintenance, not ordinary profile reroll.

A future refresh command should compare installed seed metadata against the current seed catalog and
then report what it would change before mutating anything. Useful commands or surfaces include:

- list installed package seeds
- install missing package seeds
- refresh one seed by seed id
- refresh all seeds
- dry-run refresh
- force replace after explicit confirmation

Refresh should never infer intent from profile names alone. It should use seed id, seed version, and
author metadata so renamed or copied user profiles are not mistaken for package-owned defaults.

## Public API Caution

This package should add public fields only when application consumers need them for user-visible
decisions. Likely useful public metadata:

- visible profile name
- author kind when apps need to distinguish system defaults from user-created profiles
- seed id and seed version when apps present update or refresh choices

Contributor-facing and runtime-maintenance metadata can remain documented and persisted without
being forced into every public response payload.

## Implementation Slices

1. Add persisted author and optional seed metadata to the profile manifest, migrating existing
   manifests as `.user`.
2. Thread author and seed metadata into profile summaries only where consumers need it.
3. Enforce mutation rules for `.system` profiles in rename, delete, and reroll paths.
4. Add reroll-as-user-copy behavior for system profiles.
5. Add tests for migration, list summaries, mutation rejection, and system reroll copy behavior.
6. Coordinate a tagged `SpeakSwiftly` release before `SpeakSwiftlyServer` depends on the new
   authorship behavior.

## Open Questions

- Should seed metadata live directly on the profile manifest, or in a nested provenance object?
- Should system-profile deletion require a dedicated API, or should downstream installers own
  system uninstall by removing their own seeded profiles?
- What conflict-safe user copy name should reroll use when both the preferred name and the
  `-builtin` name are occupied?
- Should public profile summaries expose author metadata immediately, or should that wait until an
  app consumer needs to display it?
