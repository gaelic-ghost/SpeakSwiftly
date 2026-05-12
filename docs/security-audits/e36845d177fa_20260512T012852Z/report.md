# SpeakSwiftly Security Audit

Scan ID: `e36845d177fa_20260512T012852Z`

Scope: repository-wide source audit of the standalone `SpeakSwiftly` Swift package at commit `e36845d177fa`.

## Summary

The scan found three reportable issues:

- Qwen live chunk logging records full request text in structured stderr logs.
- Retained file and batch generation can be queued without a non-playback admission cap.
- The tag-triggered runtime publication workflow uses mutable GitHub Action refs.

No secrets, local dependency paths, shell command injection, dynamic JSONL operation dispatch, or ordinary profile/artifact ID path traversal survived validation.

## Finding: Qwen live chunk logging records full request text

- Priority: P2
- Severity: medium
- Confidence: high
- CWE: CWE-532, Insertion of Sensitive Information into Log File
- Affected lines:
  - `Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:21-28`
  - `Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:45-49`
  - `Sources/SpeakSwiftly/Runtime/WorkerRuntime+EventLogging.swift:348-357`

### Summary

Qwen live chunk tracing logs full caller-provided speech text. Most chunk metadata is count-based, but `qwenLiveChunkTextDetails` adds both `text` and `text_visible_breaks` into structured stderr log details.

### Validation

Static tracing confirmed that `logQwenLiveChunkPlan` and `logQwenLiveChunkStarted` merge `qwenLiveChunkTextDetails` into structured log events. That helper writes the raw chunk text directly.

### Reachability Analysis

This is reachable from normal speech generation paths when Qwen live chunk planning is used. The impact depends on host log retention, but the repository already treats worker logs as operator-facing runtime evidence, so sensitive utterances should not be logged by default.

### Attack Path

1. A caller submits sensitive text for local speech.
2. The runtime splits the text into Qwen live chunks.
3. The worker writes chunk text into stderr structured logs.
4. A parent process, host app, or operator log collector retains the text outside the intended speech flow.

### Attack Path Facts

- Vector: local library or JSONL worker request.
- Auth scope: caller with speech-generation access.
- Cross-boundary behavior: request content moves into logs.
- Impact surface: sensitive text disclosure through local log retention.
- Strongest counterevidence: not every host retains stderr logs; issue is limited to Qwen live chunk paths.

### Severity Analysis

Medium severity is appropriate because the issue exposes potentially sensitive spoken text but does not by itself grant code execution, privilege escalation, or remote access. Priority is P2 because the fix is narrow and protects privacy-by-default behavior.

### Remediation

Remove raw text fields from Qwen live chunk logs. Keep chunk index, total, segmentation, word count, character count, sentence count, paragraph count, and timing fields. Add a focused regression test that asserts planned/started chunk log details do not include raw text.

## Finding: Retained file and batch generation can be queued without a non-playback admission cap

- Priority: P2
- Severity: medium
- Confidence: medium-high
- CWE: CWE-770, Allocation of Resources Without Limits or Throttling
- Affected lines:
  - `Sources/SpeakSwiftly/API/Generation.swift:69`
  - `Sources/SpeakSwiftly/API/Generation.swift:96`
  - `Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift:239-247`
  - `Sources/SpeakSwiftly/Runtime/WorkerRuntimeLifecycle.swift:249-268`
  - `Sources/SpeakSwiftly/Generation/GenerationQueue.swift:30-33`

### Summary

The runtime caps accepted live playback jobs, but retained audio-file and batch generation jobs bypass that admission cap. Those requests can still create persisted job records and enqueue model work.

### Validation

Static tracing confirmed that `WorkerRuntimeLifecycle` rejects only `request.requiresPlayback` jobs at the live queue cap. Non-playback generation continues through persisted job creation and `generationQueue.enqueue`, whose queue append has no queue-length or payload-size guard.

### Reachability Analysis

This is most security-relevant when a downstream host exposes retained file or batch generation to less-trusted local or network clients. In the package alone, the caller is a trusted library/worker client, so the issue is best framed as a resource-safety control that downstream hosts should inherit by default.

### Attack Path

1. A less-trusted caller submits many retained file or batch generation requests.
2. The live playback queue cap does not apply because these requests do not require playback.
3. The runtime persists job records and appends each job to the generation queue.
4. The worker accumulates queued work, manifests, generated audio output, and CPU/GPU work pressure.

### Attack Path Facts

- Vector: local library or JSONL worker request, especially through a downstream host.
- Auth scope: caller with retained-generation access.
- Cross-boundary behavior: one caller can consume shared worker resources.
- Impact surface: memory, disk, and model execution availability.
- Strongest counterevidence: generation concurrency is capped to one active job, limiting simultaneous model execution.

### Severity Analysis

Medium severity is appropriate because this can disrupt a shared local speech worker when exposed across a trust boundary, but it does not create direct data compromise or code execution. Priority is P2 because admission control belongs close to the package runtime rather than every host re-implementing it.

### Remediation

Add retained-generation admission limits for queued file and batch jobs. Consider separate limits for queued job count, batch item count, total queued text size, and retained artifact storage. Return descriptive `invalidRequest` errors when limits are hit, and add tests for playback-capped and non-playback-capped request families.

## Finding: Tagged runtime-publication workflow uses mutable action refs

- Priority: P2
- Severity: medium
- Confidence: medium-high
- CWE: CWE-829, Inclusion of Functionality from Untrusted Control Sphere; CWE-494, Download of Code Without Integrity Check
- Affected lines:
  - `.github/workflows/swift.yml:130-147`
  - `.github/workflows/swift.yml:24-30`
  - `.github/workflows/swift.yml:52-58`
  - `.github/workflows/validate-repo-maintenance.yml:17`

### Summary

The tag-triggered runtime publication job uses mutable action refs such as `actions/checkout@v5`, `maxim-lobanov/setup-xcode@v1`, and `actions/upload-artifact@v6`. The workflows also do not declare explicit least-privilege `permissions`.

### Validation

Workflow review confirmed the tag publication job runs on `v*` tag pushes, builds runtime artifacts, verifies them, and uploads the runtime directory with `actions/upload-artifact@v6`. The workflow uses action tags instead of immutable commit SHAs.

### Reachability Analysis

This is a release-integrity risk, not an application runtime bug. If an action tag or publisher account is compromised, action code can run in the workflow that publishes runtime artifacts.

### Attack Path

1. A `v*` tag push starts the runtime publication job.
2. GitHub resolves mutable action refs at workflow runtime.
3. A compromised action ref runs attacker-controlled code on the runner.
4. That code can tamper with uploaded runtime artifacts or use available workflow token permissions.

### Attack Path Facts

- Vector: GitHub Actions supply chain.
- Auth scope: action code executing in repository workflow context.
- Cross-boundary behavior: third-party action code participates in release artifact publication.
- Impact surface: runtime artifact integrity and workflow token permissions.
- Strongest counterevidence: no `secrets.*` references were found, and PR workflows do not use `pull_request_target`.

### Severity Analysis

Medium severity is appropriate because this affects release integrity but requires action supply-chain compromise. Priority is P2 because SHA pinning and explicit permissions are low-risk hardening with high release-safety value.

### Remediation

Pin third-party and first-party actions to immutable commit SHAs. Add top-level or job-level `permissions`, using `contents: read` for build/validation jobs unless a job needs more. Consider separating runtime artifact publication permissions from ordinary CI.

## Coverage Closure

| Row | Disposition | Reason |
|---|---|---|
| Active cancel does not cancel active generation work | Suppressed | Real reliability issue, but security impact overlaps retained-generation resource exhaustion and does not add a stronger standalone attack path. |
| Voice clone can read/transcribe arbitrary readable audio paths | Deferred | Requires less-trusted caller exposure to clone creation; this package intentionally exposes path-based clone creation to trusted callers. |
| Voice profile export creates caller-chosen new files | Suppressed | Intentional trusted-caller export API; destination must be new and content is canonical WAV, not arbitrary bytes. |
| System profile seeding trusts manifest profile names | Deferred | Requires malicious configured/bundled system-profile resource root. Ordinary profile operations validate names. |
| Profile manifests trust artifact filenames for reads | Deferred | Requires manifest tampering or malicious resource root. Newly-created profiles use constant or sanitized filenames. |
| JSONL dynamic operation injection | Not applicable | JSONL decoding uses a closed operation switch and rejects unsupported operations. |
| Profile/artifact/job ID path traversal | Suppressed | Profile names are regex-validated; artifact and generation-job IDs are hex-encoded before directory construction. |
| SwiftPM plugin command injection | Suppressed | Plugin launches `SpeakSwiftlyTool` through `Process.executableURL` and argument arrays, not shell interpolation. |
| Repo-maintenance shell injection and live-service SSRF | Suppressed | Reviewed sources are maintainer/operator-controlled; commands are quoted and live-service URL defaults to loopback. |

## Follow Up Prompts

- Audit downstream `SpeakSwiftlyServer` HTTP/MCP exposure for whether retained file/batch generation, clone creation, profile export, queue controls, and system-profile authoring are reachable from less-trusted clients.
- Run a focused storage hardening pass on `ProfileStore+SystemProfiles.swift` and profile manifest artifact filenames to decide whether manifest-loaded names should be revalidated even for trusted bundled resources.
- Run a release-integrity hardening pass on `.github/workflows/swift.yml` and `.github/workflows/validate-repo-maintenance.yml` to pin actions and set explicit permissions.
