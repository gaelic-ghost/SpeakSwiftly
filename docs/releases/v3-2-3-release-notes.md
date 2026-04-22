# v3.2.3 Release Notes

## What changed

- aligned SpeakSwiftly's Qwen generation token budget with the upstream
  `mlx-audio-swift` default by using `4096` max tokens for resident generation
  and profile generation instead of SpeakSwiftly's local word-count-derived cap
- applied that same upstream-default token budget to the direct Qwen testing
  probe path in `SpeakSwiftlyTesting`
- updated the resident generation-parameter unit coverage to assert the new
  upstream-aligned Qwen token budget

## Breaking changes

- none

## Migration or upgrade notes

- this is a patch release focused on Qwen backend behavior alignment
- long-form Qwen generations now inherit the upstream token budget instead of
  SpeakSwiftly's shorter local heuristic cap

## Verification performed

```bash
swift test
```

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

```bash
sh scripts/repo-maintenance/run-e2e.sh --suite qwen
```
