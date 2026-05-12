# SpeakSwiftly Repository Threat Model

## Overview

SpeakSwiftly is a Swift package for local, on-device speech generation and playback. It exposes a public Swift library, a JSONL-driven worker/tool executable, a probe executable, and a SwiftPM command plugin for authoring bundled system voice profiles. The repository also includes maintainer scripts for validation, runtime publishing, E2E testing, live-service model unload/reload helpers, and release operations.

The primary assets are local audio output behavior, generated speech artifacts, voice profile material, runtime state under Application Support or explicit state roots, bundled system profiles, local model resources, generated conditioning data, package release integrity, and operator trust in maintainer scripts. Because the package is local-first, the most realistic security failures are local privilege/safety boundary mistakes, filesystem writes outside intended roots, unsafe handling of untrusted JSONL input, dependency or bundled-resource integrity mistakes, accidental exposure of private voice/audio material, and maintainer tooling that disrupts Gale's live speech/accessibility environment.

The repository is not a network server by itself. Web classes such as CSRF, browser XSS, HTTP session fixation, and multi-tenant authorization are generally out of scope unless a downstream host exposes SpeakSwiftly operations over a network API. Downstream hosts may raise the severity of any SpeakSwiftly bug if they pass remote user input directly into the worker, profile store, text normalizer, file generation API, or plugin authoring surface.

## Threat Model, Trust Boundaries, and Assumptions

The public Swift API boundary separates trusted host application code from SpeakSwiftly internals. Host code is assumed to choose state roots, system profile roots, text inputs, backend configuration, and lifecycle operations deliberately. A hostile or careless host can already request local speech, create profiles, and write generated artifacts; the library's job is to keep those powers constrained to the configured roots and explicit operations.

The JSONL worker/tool boundary separates line-oriented operator or host input from runtime request handling. Each JSONL request should be treated as attacker-controlled unless the embedding host has authenticated and authorized it before forwarding it. Operation names, request IDs, text, profile names, state root paths, system profile resource roots, output file names, and backend controls are all security-relevant inputs.

The filesystem boundary separates configured writable state from the rest of the user's machine and package checkout. Runtime profile stores, text profiles, generation job manifests, generated audio files, retained artifacts, temporary directories, and plugin-authored system profile resources must stay under intended roots. Path traversal, symlink following, stale lock handling, and confused "system profile" versus "user profile" writes are the main concerns.

The package-resource boundary separates reviewed, bundled resources from generated local state. Bundled `SystemProfiles`, `default.metallib`, and `mlx-swift_Cmlx.bundle` are trusted as part of the package build. The command plugin is allowed to write generated system voice profiles into a target package only through SwiftPM's explicit plugin permission surface.

The runtime/live-service boundary separates ordinary package validation from Gale's day-to-day local speech accessibility environment. E2E tests and maintainer scripts can unload resident models, generate audible playback, publish runtime artifacts, and interact with a live `SpeakSwiftlyServer` service. Those operations are intentionally opt-in and must remain clear, reversible, and operator-controlled.

The dependency boundary includes `TextForSpeech`, `mlx-audio-swift`, and `mlx-swift`. Package dependency URLs and versions must remain fetchable, reviewable, and not machine-local. The vendored MLX bundle and Metal library are binary/resource trust points; accidental replacement or mismatch can cause runtime failure or unexpected native-code/resource behavior.

## Attack Surface, Mitigations, and Attacker Stories

Public library callers can pass untrusted text and configuration into generation, playback, normalization, profile creation, profile storage, generated-file retention, runtime observation, and queue control APIs. The most important security invariant is that user-controlled names and paths do not escape configured stores, silently overwrite unrelated files, or confuse profile/resource ownership.

The JSONL worker surface accepts request objects that control runtime operations. Realistic attacker stories include a downstream host exposing the worker to remote input without filtering, a local process feeding malformed or oversized requests, or a developer tool passing an unintended state root or system profile root. Mitigations should include strict decoding, explicit operation allowlists, descriptive rejection errors, and careful path normalization at storage boundaries.

The SwiftPM command plugin has package-directory write permission for generated system voice profiles. A realistic attacker story is misuse of plugin arguments to write outside the intended target resource root, poison bundled profiles, or leave coordination artifacts in the package. SwiftPM's permission gate and the plugin/tool split are important mitigations, but the plugin and tool must still validate target roots and profile names.

Filesystem-backed storage is a broad sink family. Profile manifests, job manifests, generated audio files, temporary directories, Qwen conditioning artifacts, and retained files should use root-relative resource names rather than trusting raw path strings. Writes should be atomic where practical, should avoid following attacker-controlled symlinks when overwriting sensitive files, and should preserve clear failure messages when a root is missing, unreadable, or outside policy.

Maintainer scripts are developer-controlled, but they can affect releases, local runtimes, and live resident models. The main attacker stories are accidental execution from the wrong directory, environment-variable injection into shell commands, writing release artifacts from stale state, or disrupting live speech. Existing repo-maintenance wrappers and validation lanes are mitigations when they consistently resolve the repository root, quote paths, fail clearly, and make live-service effects opt-in.

Tests and fixture resources include voice/audio material and generated conditioning JSON. They are not secrets by default, but retained real-user audio, private voice clones, or generated artifacts would become sensitive if added accidentally. Public-report and release workflows should avoid committing machine-local state roots, personal voice recordings, API tokens, or private runtime logs.

## Severity Calibration (Critical, High, Medium, Low)

Critical issues require realistic code execution, arbitrary filesystem write outside intended roots with high-impact overwrite, supply-chain compromise of package dependencies or bundled native resources, or an unauthenticated remote host exposing these local powers broadly. Because this repository is not itself a network service, critical severity usually depends on a downstream host making the worker remotely reachable or a release artifact shipping compromised resources.

High issues include path traversal or symlink bugs that let JSONL or plugin inputs write outside configured roots, confusion that lets ordinary runtime voice APIs mutate package-owned system profiles, unsafe release/runtime publishing that can replace trusted executables with unreviewed artifacts, or worker operations that let untrusted callers trigger disruptive resident-model or playback behavior without host consent.

Medium issues include denial of service through oversized JSONL requests, unbounded queueing, expensive model warmups from unauthenticated local callers, ambiguous profile names causing overwrite or data mixing inside the intended store, weak cleanup of temporary generated files, or maintainer scripts that can disrupt live service state when run in the wrong context.

Low issues include confusing diagnostics, stale documentation that nudges operators into unsafe launch paths, test fixture hygiene gaps, overly broad file permissions on generated artifacts without cross-user exposure, and developer-only script footguns that are unlikely to affect release artifacts or live runtime behavior.
