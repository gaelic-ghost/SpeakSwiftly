# Validation Report

## Validation Rubric

- [x] Identify the exact attacker-controlled source or privileged boundary.
- [x] Identify the root broken control or dangerous sink.
- [x] Check the closest countercontrol for the same instance.
- [x] Calibrate whether the issue crosses a real trust boundary in this repository.
- [x] Preserve suppressed/deferred rows with exact proof gaps.

## Finding Validation

### F-001: Qwen live chunk logging records full request text

- Confidence: high.
- Method: static source-to-sink trace.
- Evidence:
  - `logQwenLiveChunkPlan` merges `qwenLiveChunkTextDetails` into per-chunk structured log details at `WorkerRuntime+EventLogging.swift:21-28`.
  - `logQwenLiveChunkStarted` also merges the same details at `WorkerRuntime+EventLogging.swift:45-49`.
  - `qwenLiveChunkTextDetails` writes `chunk.text` into `text` and `text_visible_breaks` at `WorkerRuntime+EventLogging.swift:348-357`.
- Remaining uncertainty: whether all production hosts retain stderr logs and whether Qwen pre-model live chunking is enabled in each deployment.
- Minimal next step: remove raw text from these structured logs and keep only counts, chunk indexes, and segmentation metadata.

### F-002: Retained file and batch generation can be queued without a non-playback admission cap

- Confidence: high for missing cap, medium for security severity.
- Method: static control-flow trace.
- Evidence:
  - `WorkerRuntimeLifecycle.swift:239-247` rejects only requests where `request.requiresPlayback` and the playback queue has reached `maxAcceptedSpeechJobs`.
  - The code creates a persisted generation job if needed and then calls `generationQueue.enqueue` at `WorkerRuntimeLifecycle.swift:249-268`.
  - `GenerationQueue.enqueue` appends to an in-memory array without a queue-length or payload-size guard at `GenerationQueue.swift:30-33`.
- Remaining uncertainty: downstream host exposure. In this package alone, callers are trusted local library/worker clients; if a host exposes the worker to less-trusted clients, the issue becomes a cross-client resource exhaustion risk.
- Minimal next step: add retained-generation queue and batch-size admission limits, and surface descriptive rejection errors.

### F-003: Tagged runtime-publication workflow uses mutable action refs

- Confidence: medium-high.
- Method: workflow source review.
- Evidence:
  - The tag-triggered runtime publication job starts at `.github/workflows/swift.yml:116-119`.
  - The publication job uses `actions/checkout@v5`, `maxim-lobanov/setup-xcode@v1`, and `actions/upload-artifact@v6` at `.github/workflows/swift.yml:130-147`.
  - The workflows do not define explicit top-level or job-level `permissions`.
- Remaining uncertainty: repository-level default `GITHUB_TOKEN` permissions were not queried in this scan.
- Minimal next step: pin actions to immutable SHAs and add explicit least-privilege workflow permissions.

## Validation Closure Table

| Ledger Row | Instance Key | Root Control | Entrypoint / Source | Sink / Control | Disposition | Counterevidence Or Proof Gap | Survives |
|---|---|---|---|---|---|---|---|
| RW-001 | `sensitive-log:Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:348` | `WorkerRuntime+EventLogging.swift:348-357` | Caller-controlled speech text | Structured stderr log details | reportable | Direct raw-text log sink found. | yes |
| RW-002 | `resource-exhaustion:Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift:239` | `WorkerRuntimeLifecycle.swift:239-247` | Retained file/batch generation | Unbounded generation queue append | reportable | Playback cap exists, non-playback cap absent. | yes |
| RW-003 | `supply-chain:.github/workflows/swift.yml:131` | `.github/workflows/swift.yml:130-147` | GitHub Action refs at workflow runtime | Mutable action code in tag publication | reportable | No secrets found, but publication integrity remains in scope. | yes |
| RW-004 | `cancel:Sources/SpeakSwiftly/Playback/RuntimePlaybackQueueCommands.swift:83` | `RuntimePlaybackQueueCommands.swift:83-105` | Caller-controlled cancel | Active generation task not cancelled | suppressed | Real reliability issue; security impact duplicates F-002 and does not add a stronger attack path. | no |
| RW-005 | `clone-path:Sources/SpeakSwiftly/Generation/VoiceProfileAudioSupport.swift:173` | `VoiceProfileAudioSupport.swift:173-217` | Caller-controlled clone audio path | Worker-readable audio load and transcript storage | deferred | Requires less-trusted caller exposure not established in this repo. | uncertain |
| RW-006 | `export-path:Sources/SpeakSwiftly/Generation/VoiceProfileCreation.swift:144` | `VoiceProfileCreation.swift:144-158` | Caller-controlled export path | New WAV file creation | suppressed | Intended trusted-caller export behavior; no overwrite and no arbitrary content. | no |
| RW-007 | `system-profile-seed:Sources/SpeakSwiftly/Storage/ProfileStore+SystemProfiles.swift:54` | `ProfileStore+SystemProfiles.swift:46-72` | Configured resource-root manifest | Destination path from manifest profile name | deferred | Requires malicious configured/bundled resource root; ordinary profile operations validate names. | uncertain |
| RW-008 | `manifest-artifact-path:Sources/SpeakSwiftly/Storage/ProfileStore.swift:360` | `ProfileStore.swift:360-366` | Tampered profile manifest | Artifact filename appended for reads | deferred | Requires manifest write or malicious resource root; new writes use constants/sanitizers. | uncertain |
| RW-009 | `jsonl-op-dispatch:Sources/SpeakSwiftlyTool/ToolRequest+Decoding.swift:27` | `ToolRequest+Decoding.swift:27-318` | Caller-controlled op | Closed operation switch | not_applicable | Unsupported operations are rejected. | no |
| RW-010 | `encoded-ids:Sources/SpeakSwiftly/Storage/GeneratedFileStore.swift:249` | `GeneratedFileStore.swift:249-263` | Caller-controlled artifact ID | Hex-encoded directory name | suppressed | Path separators do not survive hex encoding. | no |
| RW-011 | `plugin-process:Plugins/UpsertSystemVoiceProfile/UpsertSystemVoiceProfile.swift:42` | `UpsertSystemVoiceProfile.swift:42-67` | Plugin CLI args | Process launch | suppressed | Uses executable URL and argument array, not shell interpolation. | no |
| RW-012 | `scripts:scripts/repo-maintenance` | `scripts/repo-maintenance/` | Maintainer env/config | Quoted shell/curl/git/gh operations | suppressed | Operator-controlled sources and quoted arguments; no attacker source identified. | no |

