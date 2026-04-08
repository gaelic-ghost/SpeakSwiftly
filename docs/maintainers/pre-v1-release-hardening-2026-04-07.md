# Pre-v1 Release Hardening

This note captures the remaining release-hardening work we want to land before the first full `v1.0.0` release.

The goal is not to widen `SpeakSwiftly` into a new service or packaging subsystem. These are targeted hardening changes around:

- test observability and retained artifacts
- tagged-release verification
- published runtime ergonomics for local consumers and other developers

## Apple / Swift Alignment

These follow-on tasks should stay aligned with the platform APIs we already depend on.

- Foundation `Process` makes `executableURL`, `currentDirectoryURL`, and `environment` explicit launch inputs rather than implicit process state. Runtime launchers and test helpers should keep launch configuration explicit instead of depending on ambient shell state.
  Source: [Process.executableURL](https://developer.apple.com/documentation/foundation/process/executableurl?changes=_3_3&language=objc)
- Foundation `Bundle` exposes `resourceURL`, `privateFrameworksURL`, and resource lookup APIs such as `url(forResource:withExtension:subdirectory:in:)`. Runtime consumption should prefer bundle-aware resource discovery over assumptions about the caller's current working directory.
  Sources: [Bundle.executableURL](https://developer.apple.com/documentation/foundation/bundle/executableurl), [Bundle.url(forResource:withExtension:subdirectory:in:)](https://developer.apple.com/documentation/foundation/bundle/url%28forresource%3Awithextension%3Asubdirectory%3Ain%3A%29?language=objc)
- Foundation `FileManager` is the supported path for publishing, replacing, moving, and symlinking local runtime directories. If we add stable aliases such as `current-debug` and `current-release`, create and inspect them through `FileManager` and URL resource values instead of hand-parsing paths.
  Sources: [FileManager](https://developer.apple.com/documentation/foundation/filemanager), [URLResourceKey.isSymbolicLinkKey](https://developer.apple.com/documentation/foundation/urlresourcekey/issymboliclinkkey)

Dash was checked first for the Foundation surfaces above, but the local Apple docset was sparse for the exact Swift symbol lookups we needed here, so the links above use the current Apple developer documentation pages directly.

## Current State

Today we already have:

- runtime stderr logging that emits process and MLX memory fields such as `process_resident_bytes`, `process_phys_footprint_bytes`, `mlx_active_memory_bytes`, `mlx_cache_memory_bytes`, and `mlx_peak_memory_bytes`
- a local release flow that publishes both Debug and Release runtimes through `scripts/repo-maintenance/release.sh`
- a stable published runtime directory layout under `.local/xcode/<Configuration>` with a metadata manifest and the copied `mlx-swift_Cmlx.bundle/.../default.metallib`

This release-hardening pass is complete inside this repository.

## Required Before Full v1.0.0

### 1. Persist real e2e worker artifacts for later inspection

Status: done on 2026-04-07 for retained stdout or stderr JSONL, compact summary artifacts, and CPU accounting through the same unprivileged process snapshot path already used for runtime memory metrics.

We should retain per-run artifacts for real-model e2e runs instead of keeping stdout and stderr only in memory.

Target behavior:

- create a per-run artifact directory such as `.local/e2e-runs/<run-id>/`
- tee worker stdout and stderr into durable JSONL files while preserving the current in-memory recorder used by test assertions
- write one compact run summary JSON with:
  - start and finish timestamps
  - wall-clock duration
  - test name
  - worker executable path and runtime metadata
  - final process / MLX memory summary
  - CPU summary if available

CPU and GPU expectations:

- CPU summary is now retained through the same unprivileged process-accounting path we already use for runtime memory snapshots.
- GPU memory is already partially represented through MLX memory fields.
- GPU utilization should not become a default release gate unless we have a stable, permissionless, Apple-supported way to gather it. We should avoid adding a privileged or flaky metrics dependency to routine local and CI test runs.

### 2. Enforce Debug and Release runtime publication on tagged prereleases and releases

Status: done on 2026-04-07 for tagged CI publication and verification of both configurations.

The repo-maintenance release flow already publishes both configurations, but our tagged-release path is not currently CI-enforced.

Target behavior:

- tag-triggered CI should build and verify both Debug and Release Xcode-backed runtimes
- CI should fail if either published runtime is missing:
  - the executable
  - `mlx-swift_Cmlx.bundle`
  - `default.metallib`
  - the metadata manifest
- prerelease and final release notes should clearly state whether both configurations were built and verified

This is a release-hardening change, not a new runtime architecture.

### 3. Make published runtimes easier to consume correctly

Status: done on 2026-04-07 for launcher scripts, stable aliases, and manifest-first consumption inside this repository.

The current `.local/xcode/<Configuration>` layout is much better than relying on raw DerivedData paths, but downstream local consumers still have to reconstruct too much launch wiring manually.

Target behavior:

- publish a small launcher script inside each runtime directory that:
  - sets `DYLD_FRAMEWORK_PATH`
  - launches the matching `SpeakSwiftly` binary
- add stable aliases such as:
  - `.local/xcode/current-debug`
  - `.local/xcode/current-release`
- prefer manifest-first consumption:
  - consumers should read `.local/xcode/SpeakSwiftly.debug.json` or `.local/xcode/SpeakSwiftly.release.json` first
  - launchers and test helpers should stop rebuilding executable and metallib paths by hand when the manifest already knows them
- consider attaching the published Release runtime as a release asset so a fresh clone or adjacent local consumer can use a known-good runtime without rebuilding first

This is a durable building-block cleanup because it removes current launch friction for every local consumer while keeping the same published runtime model.

### 4. Tighten runtime resource lookup around bundle reality, not cwd guesses

Status: done on 2026-04-07 for published-runtime consumers in this repository.

The worker and its consumers should continue moving away from any behavior that silently depends on the process launch directory.

Target behavior:

- resource and bundle lookup should be anchored to the published runtime bundle layout
- downstream launch paths should prefer bundle-relative or manifest-provided locations for `default.metallib`
- path reconstruction logic should be centralized in one place instead of repeated across tests and adjacent local consumers

This should stay a concrete cleanup of the existing published-runtime model, not a new packaging layer.

## Follow-Through Note

The previously deferred queued-playback audible e2e gap is now closed too:

- the strict multi-request audible live-playback e2e lane now pre-queues several jobs on one worker and validates queued drain behavior directly

That work was tracked separately from the release-hardening items above, but it is now complete as well.
