# Speech Text Normalizer Audit

## Purpose

This note describes the current `SpeechTextNormalizer` implementation in [SpeechTextNormalizer.swift](/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift) after the functional cleanup pass. The goal of the normalizer is to take text that often makes the local model spiral into bad generations, parse it into recognizable problem shapes, and rewrite only those shapes into more speakable text.

## Current shape

The normalizer is now one path in and one path out:

1. `normalize(_:)` canonicalizes line endings and tabs.
2. It runs a fixed ordered pipeline of pure transformation passes.
3. It collapses whitespace once at the end and falls back to the original input only if the final result is empty.

The pipeline order is:

1. `normalizeFencedCodeBlocks(_:)`
2. `normalizeInlineCodeSpans(_:)`
3. `normalizeMarkdownLinks(_:)`
4. `normalizeFilePaths(_:)`
5. `normalizeDottedIdentifiers(_:)`
6. `normalizeSnakeCaseIdentifiers(_:)`
7. `normalizeCamelCaseIdentifiers(_:)`
8. `normalizeCodeHeavyLines(_:)`
9. `normalizeSpiralProneWords(_:)`
10. `collapseWhitespace(_:)`

That ordering is intentional:

- block-level code gets normalized before smaller inline shapes
- explicit structured shapes get normalized before broader code-line fallback
- repeated-letter cleanup runs late so it can operate on the near-final spoken text

## Framework usage

The implementation now relies on two Apple text APIs:

- `NaturalLanguage.NLTokenizer`
  - Used for word tokenization in `naturalLanguageTokenRanges(in:)` and `naturalLanguageWords(in:)`.
  - Apple documents `NLTokenizer` as a tokenizer that segments natural language text into semantic units and exposes token ranges through `tokens(for:)` and `enumerateTokens(in:using:)`.
  - Source: [NLTokenizer](http://127.0.0.1:53593/Dash/dash-apple-api/load?request_key=ls/documentation/naturallanguage/nltokenizer)
  - Source: [enumerateTokens(in:using:)](http://127.0.0.1:53593/Dash/dash-apple-api/load?request_key=ls/documentation/naturallanguage/nltokenizer/enumeratetokens(in:using:))
- `RegexBuilder`
  - Used for the code-marker detector so the broad code signal is expressed with Swift’s regex DSL instead of string regex literals.
  - Apple documents `RegexBuilder` as a DSL for building regexes for searching and replacing in text.
  - Source: [RegexBuilder](http://127.0.0.1:53593/Dash/dash-apple-api/load?request_key=ls/documentation/regexbuilder)

## Pass-by-pass behavior

### `normalizeFencedCodeBlocks(_:)`

This pass scans line-by-line for triple-backtick fences, extracts the body, and rewrites it with `spokenCodeBlock(_:)`.

Current spoken wrapper:

- `Code sample. ... . End code sample.`

This keeps large code blocks from falling through as raw punctuation-heavy text.

### `normalizeInlineCodeSpans(_:)`

This pass scans for single-backtick inline spans and replaces each span with `spokenInlineCode(_:)`.

Current behavior:

- strips the backticks
- rewrites operators and punctuation through `spokenCode(_:)`
- keeps the surrounding prose intact

### `normalizeMarkdownLinks(_:)`

This pass parses basic inline markdown links of the form `[label](destination)`.

Current output policy:

- labeled links become `label, link destination`
- unlabeled links fall back to just the destination

### `normalizeFilePaths(_:)`

This pass rewrites path-like tokens with `spokenPath(_:)`.

Current path behavior:

- keeps path segments readable with `NLTokenizer`
- says separators explicitly:
  - `/` as `slash`
  - `\` as `backslash`
  - `.` as `dot`
  - `_` as `underscore`
  - `-` as `dash`
  - leading `~` as `home`

The current path rendering intentionally favors stable spoken delimiters over pretty prose because the model behaves better when the structure is explicit.

### `normalizeDottedIdentifiers(_:)`

This pass rewrites dot-separated symbol tokens such as `NSApplication.didFinishLaunchingNotification`.

Current output policy:

- preserve identifier order
- say `dot` explicitly
- split internal word boundaries into natural spoken words

### `normalizeSnakeCaseIdentifiers(_:)`

This pass rewrites `snake_case` tokens.

Current output policy:

- preserve each segment
- say `underscore` explicitly

### `normalizeCamelCaseIdentifiers(_:)`

This pass rewrites `camelCase` or mixed-case identifier tokens.

Current output policy:

- insert word breaks at lower-to-upper transitions
- keep the original token ordering

### `normalizeCodeHeavyLines(_:)`

This is the broad fallback for lines that still look structurally code-like after the more targeted passes.

Current trigger:

- the line contains enough punctuation-heavy structure and code markers to satisfy `isLikelyCodeLine(_:)`

Current output:

- the whole line runs through `spokenCode(_:)`

This keeps the broad fallback local to obviously code-heavy lines instead of flattening the entire request when only one region is noisy.

### `normalizeSpiralProneWords(_:)`

This pass targets words with repeated letter runs that often cause unstable or runaway speech.

Current trigger:

- `containsRepeatedLetterRun(_:)` finds three or more repeated letters in sequence

Current output:

- the word is spelled out character-by-character, for example `q q q w w e e r r t y y`

This is intentionally blunt. The goal is not to preserve lexical elegance. The goal is to stop the model from getting trapped in garbage continuations.

## Helper model

The supporting helpers are deliberately small and local:

- `spokenCode(_:)` handles operator and delimiter speech
- `spokenPath(_:)` handles path separators and segment readability
- `spokenIdentifier(_:)` handles dots, underscores, dashes, and internal word breaks
- `insertWordBreaks(in:)` adds boundaries between lower-uppercase and letter-digit transitions
- `transformTokens(in:transform:)` applies token-local rewrites without introducing a new abstraction layer

That shape is intentionally conservative. No extra manager, scorer, protocol, coordinator, or wrapper was added. The normalizer remains one file with straight top-down flow.

## Detection model

The current detector strategy is intentionally split into narrow shape detectors plus a single broad fallback signal:

- narrow shape detectors:
  - fenced code
  - inline code
  - markdown links
  - file paths
  - dotted identifiers
  - snake case
  - camel case
  - repeated-letter words
- broad fallback signal:
  - `looksCodeHeavy(_:)`
  - `isLikelyCodeLine(_:)`

`looksCodeHeavy(_:)` still exists because the forensic payload needs a coarse code-heaviness flag. The difference is that normalization no longer uses a global “all or nothing” gate before doing anything useful.

## Forensics

The forensic APIs were preserved:

- `forensicFeatures(originalText:normalizedText:)`
- `forensicSections(originalText:)`
- `forensicSectionWindows(originalText:totalDurationMS:totalChunkCount:)`

The current counters now derive from the same parsing helpers that the normalizer uses, instead of separate regex-only counting paths. That keeps the feature report more aligned with the real transformations.

## Test coverage

The current tests now include dedicated helper coverage in [SpeechTextNormalizerTests.swift](/Users/galew/Workspace/SpeakSwiftly/Tests/SpeakSwiftlyTests/SpeechTextNormalizerTests.swift):

- fenced code blocks
- inline code spans
- markdown links
- file paths
- dotted identifiers
- snake case identifiers
- camel case identifiers
- code-heavy lines
- spiral-prone words
- mixed integration cases

Existing integration coverage remains in [ModelClientsTests.swift](/Users/galew/Workspace/SpeakSwiftly/Tests/SpeakSwiftlyTests/ModelClientsTests.swift), and the package-level behavior is still exercised through [SpeakSwiftlyE2ETests.swift](/Users/galew/Workspace/SpeakSwiftly/Tests/SpeakSwiftlyTests/SpeakSwiftlyE2ETests.swift).

## Current known limits

The cleanup made the code much easier to read, but it did not try to solve every markdown or code-parsing edge case.

Current limits:

- fenced code parsing is still triple-backtick oriented and does not attempt full markdown compliance
- inline code parsing still assumes single backticks
- markdown links still target the common inline form rather than every markdown link variant
- repeated-letter detection is heuristic and intentionally aggressive
- path and identifier classification still operate on local token heuristics instead of a full parser

Those tradeoffs are deliberate. The current implementation is meant to be readable, modular, and effective against the actual prompt shapes that have been causing bad speech generations.
