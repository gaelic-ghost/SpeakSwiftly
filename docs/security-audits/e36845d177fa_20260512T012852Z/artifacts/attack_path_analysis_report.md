# Attack Path Analysis Report

## F-001: Qwen live chunk logging records full request text

- In-scope status: in scope. The JSONL worker and local speech library are primary product surfaces.
- Attack path:
  1. A caller submits speech text that contains sensitive material.
  2. The runtime plans Qwen live chunks.
  3. `logQwenLiveChunkPlan` or `logQwenLiveChunkStarted` records full chunk text in structured stderr logs.
  4. A parent process, host app, or operator log collector retains stderr output, making spoken content available outside the intended speech flow.
- Counterevidence: not every host retains logs; the finding is limited to Qwen live chunk paths.
- Severity: medium.
- Final policy decision: report.

## F-002: Retained file and batch generation can be queued without a non-playback admission cap

- In-scope status: in scope. Generation and JSONL worker operations are primary product surfaces.
- Attack path:
  1. A less-trusted local caller or downstream host client submits many retained file or batch generation requests.
  2. The runtime applies the playback queue cap only to `requiresPlayback` requests.
  3. Retained generation jobs are persisted and appended to `GenerationQueue` without queue-length or batch-size admission limits.
  4. The worker accumulates queued work, persisted manifests, model work, generated audio, and memory/disk pressure.
- Counterevidence: generation concurrency is capped to one active job; this limits simultaneous GPU/CPU execution but not accepted queue growth or persisted payload growth.
- Severity: medium.
- Final policy decision: report.

## F-003: Tagged runtime-publication workflow uses mutable action refs

- In-scope status: in scope. CI and tag-triggered runtime publication are release-integrity surfaces.
- Attack path:
  1. The repository receives a tag push matching `v*`.
  2. GitHub Actions resolves tag-like action refs for checkout, Xcode setup, and artifact upload.
  3. If a referenced action tag or third-party action account is compromised, attacker-controlled action code runs in the publication workflow.
  4. That code can tamper with runtime artifacts or abuse available workflow token permissions.
- Counterevidence: workflows do not reference secrets, PR workflows do not use `pull_request_target`, and the shell release script uses `gh release create --verify-tag`. The tag publication job still produces uploaded runtime artifacts, so mutable action code remains a release-integrity risk.
- Severity: medium.
- Final policy decision: report.

