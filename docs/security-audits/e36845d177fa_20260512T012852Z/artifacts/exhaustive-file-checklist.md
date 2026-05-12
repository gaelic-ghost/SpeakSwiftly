# Exhaustive File Checklist

The repo-wide review used subagent shard reads plus local targeted validation. Entries marked checked were reviewed in the audit pass; tests and documentation are intentionally excluded from the runtime checklist unless used as supporting evidence.

## Checked Product And Privileged Surfaces

- [x] `Package.swift`
- [x] `Package.resolved`
- [x] `.github/workflows/swift.yml`
- [x] `.github/workflows/validate-repo-maintenance.yml`
- [x] `Plugins/UpsertSystemVoiceProfile/UpsertSystemVoiceProfile.swift`
- [x] `Sources/SpeakSwiftlyTool/SpeakSwiftlyTool.swift`
- [x] `Sources/SpeakSwiftlyTool/ToolJSONLOutput.swift`
- [x] `Sources/SpeakSwiftlyTool/ToolRequest+Decoding.swift`
- [x] `Sources/SpeakSwiftlyTool/ToolRequest+RawRequests.swift`
- [x] `Sources/SpeakSwiftlyTool/ToolRequest.swift`
- [x] `Sources/SpeakSwiftly/API/Generation.swift`
- [x] `Sources/SpeakSwiftly/API/Playback.swift`
- [x] `Sources/SpeakSwiftly/API/TextNormalization.swift`
- [x] `Sources/SpeakSwiftly/API/Tool.swift`
- [x] `Sources/SpeakSwiftly/API/VoiceProfiles.swift`
- [x] `Sources/SpeakSwiftly/API/Names.swift`
- [x] `Sources/SpeakSwiftly/Generation/`
- [x] `Sources/SpeakSwiftly/Normalization/`
- [x] `Sources/SpeakSwiftly/Playback/`
- [x] `Sources/SpeakSwiftly/Runtime/`
- [x] `Sources/SpeakSwiftly/Storage/`
- [x] `scripts/repo-maintenance/`

## Excluded From Runtime Checklist

- [ ] `Tests/` - test-only, used only as supporting evidence.
- [ ] `docs/` - documentation-only, used only as supporting evidence.
- [ ] `Sources/SpeakSwiftly/SpeakSwiftly.docc/` - documentation-only, used only as supporting evidence.
- [ ] `Sources/SpeakSwiftly/Resources/` - package resources; binary/resource provenance was outside this source scan.
- [ ] `Sources/SpeakSwiftlyProbeTool/` - developer probe executable, not a normal runtime integration surface.
- [ ] `Sources/SpeakSwiftlyTestSupport/` - test support target.

