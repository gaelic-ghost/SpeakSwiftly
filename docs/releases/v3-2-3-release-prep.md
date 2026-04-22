# v3.2.3 Release Prep

Date: 2026-04-21

This note captures the intended scope and validation story for the `v3.2.3`
patch release.

## Intended Scope

The release should be framed as:

- a Qwen3 token-budget alignment pass
- a small backend-default correction so SpeakSwiftly matches the current
  upstream `mlx-audio-swift` behavior more closely

Included work on the current branch:

- remove SpeakSwiftly's local word-count-derived Qwen max-token cap for
  resident generation
- remove SpeakSwiftly's local word-count-derived Qwen max-token cap for profile
  generation
- keep the direct Qwen testing probe path on the same upstream-default
  generation token budget
- update the resident-generation parameter test to assert the upstream-aligned
  token budget

Not included:

- a new public API surface
- a change to current Chatterbox or Marvis backend semantics
- a dependency bump or MLX bundle refresh

## SemVer Framing

- this should ship as a patch release
- the change corrects a backend default but does not add or break a public API

## Validation Performed

Shared package validation:

```bash
swift test
```

Documented Xcode-backed macOS package validation:

```bash
xcodebuild build-for-testing -quiet \
  -scheme SpeakSwiftly-Package \
  -destination 'platform=macOS' \
  -derivedDataPath .local/derived-data/validation \
  -clonedSourcePackagesDirPath .local/source-packages
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/derived-data/validation/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/WorkerRuntimePlaybackTests'
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/derived-data/validation/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/LibrarySurfaceTests'
```

```bash
xcodebuild test-without-building -quiet \
  -xctestrun "$(find .local/derived-data/validation/Build/Products -name '*.xctestrun' -maxdepth 1 | head -n 1)" \
  -destination 'platform=macOS' \
  -only-testing:'SpeakSwiftlyTests/ModelClientsTests'
```

Qwen real-model e2e coverage:

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen
```

## Release Checklist

- keep the notes focused on Qwen token-budget alignment, not as a broader
  architecture release
- call out that SpeakSwiftly now matches the upstream Qwen default max-token
  budget instead of using its own shorter local heuristic
- mention that the Qwen e2e lane passed after the alignment change
