# SpeakSwiftly

Local speech for Swift apps, desktop tools, and agent workflows that need text read aloud on-device.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Development](#development)
- [Repo Structure](#repo-structure)
- [Release Notes](#release-notes)
- [License](#license)

## Overview

### Status

SpeakSwiftly is actively available as a macOS-first local speech package, with iOS library support in progress.

### What This Project Is

TBD

### Motivation

TBD

## Quick Start

SpeakSwiftly is for local, on-device speech. It is useful when an app, automation, or agent needs speech output without handing every utterance to a remote service.

Most people should start from a higher-level host that already embeds SpeakSwiftly. Use this repository directly when you are building a Swift app, local tool, or agent runtime that needs to own speech generation itself.

For contributors and maintainers, setup and validation live in [CONTRIBUTING.md](./CONTRIBUTING.md).

## Usage

SpeakSwiftly can be used in two ways:

- inside apps and tools that want to speak text locally
- behind agent workflows that need a long-running local speech helper

The project is designed around named voices, reusable text handling, visible speech queues, saved generated audio, and local resident models.

Host-integration details live in [WorkerContract.md](./Sources/SpeakSwiftly/SpeakSwiftly.docc/WorkerContract.md).

## Development

For setup, local workflow, validation, contribution expectations, and maintainer operations, see [CONTRIBUTING.md](./CONTRIBUTING.md).

Agent-facing maintainer guidance lives in [AGENTS.md](./AGENTS.md).

## Repo Structure

```text
.
|-- Package.swift
|-- Sources/SpeakSwiftly/
|   |-- API/
|   |-- Generation/
|   |-- Normalization/
|   |-- Playback/
|   |-- Runtime/
|   `-- SpeakSwiftly.docc/
|-- Tests/SpeakSwiftlyTests/
|-- docs/maintainers/
|-- docs/releases/
`-- scripts/repo-maintenance/
```

## Release Notes

Use GitHub releases and repository tags for the authoritative release history. The active local release notes live in [docs/releases/v5-0-0-release-notes.md](./docs/releases/v5-0-0-release-notes.md), and older local release notes are consolidated in [docs/releases/release-history.md](./docs/releases/release-history.md).

## License

Apache License 2.0. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
