# Finding Discovery Report

Repository-wide discovery produced three reportable candidates and several hardening/deferred rows.

## Reportable Candidates

### F-001: Qwen live chunk logging records full request text

- Instance key: `sensitive-log:Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:348`
- Ledger row: RW-001
- Affected locations:
  - entrypoint/wrapper: `Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:21-28`
  - entrypoint/wrapper: `Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:45-49`
  - root_control/sink: `Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:348-357`
- Attacker-controlled source: speech text supplied by a Swift API or JSONL worker caller.
- Broken control: chunk text is added verbatim to structured stderr logging rather than summarized as counts.
- Impact: sensitive text spoken through the local worker can be copied into logs.
- Closest control: related chunk details log word/character/sentence counts, but `qwenLiveChunkTextDetails` adds the raw text.
- Validation recommended: yes.
- CWE: CWE-532.

### F-002: Retained file and batch generation can be queued without a non-playback admission cap

- Instance key: `resource-exhaustion:Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift:239`
- Ledger row: RW-002
- Affected locations:
  - entrypoint/wrapper: `Sources/SpeakSwiftly/API/Generation.swift:69`
  - entrypoint/wrapper: `Sources/SpeakSwiftly/API/Generation.swift:96`
  - root_control: `Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift:239-247`
  - sink: `Sources/SpeakSwiftly/Generation/GenerationQueue.swift:30-33`
- Attacker-controlled source: retained audio-file and batch generation requests.
- Broken control: playback jobs are capped at 24 accepted jobs, but non-playback retained generation jobs are not capped before queueing or persisted job creation.
- Impact: less-trusted callers can create memory, disk, and model-work pressure.
- Closest control: generation concurrency is capped to one active job, but queued work and persisted job metadata are not capped by that control.
- Validation recommended: yes.
- CWE: CWE-770.

### F-003: Tagged runtime-publication workflow uses mutable action refs

- Instance key: `supply-chain:.github/workflows/swift.yml:131`
- Ledger row: RW-003
- Affected locations:
  - root_control: `.github/workflows/swift.yml:130-147`
  - sibling controls: `.github/workflows/swift.yml:24-30`, `.github/workflows/swift.yml:52-58`, `.github/workflows/validate-repo-maintenance.yml:17`
- Attacker-controlled source: upstream code served for mutable GitHub Action refs if an action tag or action publisher is compromised.
- Broken control: workflow uses tag-like action refs and lacks explicit least-privilege `permissions`.
- Impact: CI/runtime publication integrity risk for tag-triggered artifacts.
- Closest control: workflows do not reference repository secrets and use `pull_request`, not `pull_request_target`, but the tag publication job builds and uploads runtime artifacts.
- Validation recommended: yes.
- CWE: CWE-829, CWE-494.

## Suppressed Or Deferred Discovery Rows

- H-001 active cancellation does not cancel active generation task: real reliability issue, but final security impact overlaps F-002.
- H-002 voice clone can read and transcribe arbitrary readable audio paths: deferred pending downstream trust boundary; intentional local trusted-caller API in this package.
- H-003 voice profile export creates caller-chosen new files: suppressed as intentional trusted-caller export API with no overwrite and WAV-only content.
- H-004 system profile seeding trusts manifest profile names: deferred pending malicious configured resource root or compromised package resource.
- H-005 profile manifests trust artifact filenames for reads: deferred pending local manifest write or malicious configured resource root.
- JSONL operation injection: not applicable due closed switch allowlist.
- Profile, artifact, and job ID traversal: suppressed by profile-name regex or hex-encoded directory names.
- Plugin command injection: suppressed because `Process` uses executable URL plus arguments, not a shell.
- Maintainer script shell injection/SSRF: suppressed because sources are maintainer/operator-controlled and quoted.

