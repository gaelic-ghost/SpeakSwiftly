# Runtime Inventory

Scan target: repository-wide scan of `SpeakSwiftly` at commit `e36845d177fa`.

## Product Surfaces

- Swift package library product `SpeakSwiftly`.
- JSONL executable product `SpeakSwiftlyTool`.
- Probe executable product `SpeakSwiftlyProbeTool`.
- SwiftPM command plugin `UpsertSystemVoiceProfile`.
- GitHub Actions package validation and tagged runtime-publication workflows.
- Repo-maintenance shell scripts for validation, E2E, live-service model unload/reload, runtime publishing, and release operations.

## Trust Boundaries

- Public Swift API callers into generation, playback, voice-profile, text-normalization, runtime observation, generated-file, and queue-control surfaces.
- JSONL stdin callers into `SpeakSwiftlyTool`.
- Configured filesystem roots: state root, profile root compatibility alias, generated-file root, generation-job root, and system-profile resource roots.
- SwiftPM plugin callers into package-directory writes through SwiftPM's explicit write permission gate.
- Maintainer/operator shell environment into repo-maintenance scripts.
- GitHub Actions runner and third-party action code into validation and tagged runtime-publication jobs.

## High-Impact Sinks And Controls

- Filesystem writes and reads in `ProfileStore`, `GeneratedFileStore`, `GenerationJobStore`, text-profile persistence, voice clone source loading, profile audio export, and system-profile resource seeding.
- JSONL operation allowlist in `ToolRequest+Decoding.swift`.
- Queue admission, cancellation, resident model control, and playback control in `WorkerRuntimeLifecycle.swift`, `GenerationQueue.swift`, and `RuntimePlaybackQueueCommands.swift`.
- Structured stderr logs in `WorkerRuntime+EventLogging.swift`.
- Process launch in `UpsertSystemVoiceProfile.swift`.
- Shell execution, curl calls, GitHub release/push operations, and Xcode runtime publishing in `scripts/repo-maintenance/`.
- GitHub Actions reusable action refs and runtime artifact upload in `.github/workflows/`.

## Exclusions

- Tests and docs were used as supporting evidence but are not treated as deployed runtime attack surfaces.
- Checked-in MLX bundle resources were treated as trusted package resources for this scan; binary provenance was not reverse engineered.
- Downstream `SpeakSwiftlyServer` HTTP/MCP exposure was not scanned here. Findings that depend on untrusted network reachability are marked with that precondition.

