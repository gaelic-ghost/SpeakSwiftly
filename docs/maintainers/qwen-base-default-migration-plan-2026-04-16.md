## Qwen Base Default Migration Plan

Date: 2026-04-16

### Why this change exists

This is a durable building-block cleanup, not a local stopgap.

The near-term use case it unlocks is a cleaner and more accurate Qwen clone story in `SpeakSwiftly`: one resident Qwen backend built around the Base model's documented reference-conditioning path, with reusable prepared conditioning enabled by default for clone-style generation.

The simpler path considered first was: leave `qwen3_custom_voice` in place, point callers toward `qwen3` informally, and slowly stop mentioning the custom-voice backend in docs. That path would leave a misleading runtime surface behind, keep benchmarks aimed at the wrong comparison, and make stored config and artifact semantics harder to reason about over time.

### Documentation relied on

- Apple `Decodable.init(from:)`: https://developer.apple.com/documentation/swift/decodable/init%28from%3A%29
- Apple `RawRepresentable`: https://developer.apple.com/documentation/swift/rawrepresentable
- Apple "Encoding and Decoding Custom Types": https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types
- Qwen3-TTS GitHub README: https://github.com/QwenLM/Qwen3-TTS
- Qwen 0.6B Base model card: https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base

The Swift rule this plan relies on is straightforward: `Decodable` permits custom `init(from:)` implementations, and raw-representable enums already decode through raw values. That means we can safely keep the public runtime config shape stable while explicitly mapping legacy serialized values such as `qwen3_custom_voice` to the surviving `.qwen3` case.

### Current mismatch

Today the package still treats `qwen3` and `qwen3_custom_voice` as separate resident backends even though the clone-focused runtime path is the Qwen prepared-conditioning flow, which already behaves like a reusable clone prompt.

That creates three kinds of drift:

- docs still describe resident backend switching across `qwen3`, `qwen3_custom_voice`, and `marvis`
- runtime config and stored Qwen conditioning artifacts can persist `qwen3_custom_voice`
- the opt-in benchmark suite compares two Qwen model repos instead of comparing the two Qwen conditioning strategies we actually care about

### Decision

Collapse the standalone `qwen3_custom_voice` backend into `qwen3`.

After this change:

- `.qwen3` is the only Qwen resident backend
- the resident Qwen repo is the Base model repo
- clone-oriented Qwen generation defaults to prepared conditioning
- legacy serialized `qwen3_custom_voice` values continue to decode and are normalized onto `.qwen3`

### Compatibility plan

#### Runtime configuration

- keep `SpeakSwiftly.Configuration` as the persisted shape
- add explicit decode compatibility so old `speechBackend: "qwen3_custom_voice"` values load as `.qwen3`
- always re-encode the normalized `.qwen3` value

#### Stored profile materializations and conditioning artifacts

- keep existing profile manifests readable when a materialization or conditioning artifact still says `qwen3_custom_voice`
- normalize that legacy backend to `.qwen3` when loading manifests and artifacts
- let later saves rewrite normalized manifests so the legacy backend tag gradually disappears from disk

#### Environment surface

- accept `SPEAKSWIFTLY_SPEECH_BACKEND=qwen3_custom_voice` as a legacy alias for `qwen3`
- keep the operator-facing result normalized to `qwen3`

### Implementation steps

1. Remove the `qwen3CustomVoice` enum case from the public backend surface.
2. Add explicit legacy alias decoding for config and environment parsing.
3. Remove the custom-voice resident repo constant and route resident Qwen loading only through the Base model repo.
4. Normalize stored backend materializations and stored Qwen conditioning artifacts onto `.qwen3` during load.
5. Make `preparedConditioning` the default Qwen conditioning strategy.
6. Rewrite docs and tests around one Qwen backend.
7. Replace the Qwen benchmark comparison from backend-vs-backend to conditioning-strategy-vs-conditioning-strategy.

### Validation target

The intended validation lane for this pass is the fast SwiftPM lane first:

- `swift test --filter ProfileStoreTests`
- `swift test --filter LibrarySurfaceTests`
- `swift test --filter QwenBenchmarkSuite` only if the benchmark suite still compiles after the comparison rewrite

If the known vendored parser snag blocks the SwiftPM lane, fall back to the documented Xcode-backed lane afterward.
