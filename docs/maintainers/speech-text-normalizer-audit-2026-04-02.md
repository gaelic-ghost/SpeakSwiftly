# Speech Text Normalizer Audit

## Purpose

This note explains the current `SpeechTextNormalizer` flow in [SpeechTextNormalizer.swift](/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift), what each detector and normalization pass does today, where the current implementation is weak, and what follow-up options exist.

## End-to-end flow

The current entry point is `SpeechTextNormalizer.normalize(_:)`.

The flow is:

1. Normalize line endings and tabs first.
2. Ask `containsCorrectableText(_:)` whether the text looks like it needs any intervention.
3. If the answer is yes, run the normalization passes in this exact order:
   - `normalizeFencedCodeBlocks(_:)`
   - `normalizeInlineCode(_:)`
   - `normalizeMarkdownLinks(_:)`
   - `normalizeFilePaths(_:)`
   - `normalizeIdentifierTokens(_:)`
4. After those targeted passes, run `looksCodeHeavy(_:)` again on the transformed text.
5. If the text still looks code-heavy, run the broad fallback `spokenCode(_:)`.
6. Collapse whitespace.
7. Collapse whitespace again in the final return path and fall back to the original input only if the final normalized output is empty.

Two important consequences of that ordering:

- Targeted replacements happen before the broad code fallback, which is good because it gives paths and identifiers a chance to become more speakable first.
- The broad `looksCodeHeavy(_:)` detector still has the final say, which means a false positive there can push otherwise plain text through `spokenCode(_:)`.

## Detection overview

There are really two detection layers today.

### `containsCorrectableText(_:)`

This is the coarse gate that decides whether any normalization should run at all.

It returns `true` when:

- the text contains one of these markers:
  - `` ``` ``
  - `` ` ``
  - `[`
  - `](`
  - `->`
  - `=>`
  - `::`
  - `?.`
  - `??`
- or `looksCodeHeavy(_:)` returns `true`

Current issue:

- This gate is intentionally simple, but it is very broad. A string with markdown section headers or a single inline-code span gets routed into the full normalization path even if the rest of the text is ordinary prose.

Alternate approach:

- Replace the current yes-or-no gate with a small scored feature model, then only run heavier passes when the score crosses a threshold.

### `looksCodeHeavy(_:)`

This is the stronger detector that currently affects both forensics and the broad fallback pass.

It returns `true` if:

- the text contains any obvious marker from this list:
  - `` ``` ``
  - `` ` ``
  - `->`
  - `=>`
  - `::`
  - `&&`
  - `||`
  - `==`
  - `!=`
  - `{`
  - `}`
  - `</`
  - `/>`
  - `func `
  - `let `
  - `var `
  - `const `
  - `class `
  - `struct `
  - `enum `
  - `return `
- or the ratio of selected code-ish punctuation to letters is at least `0.12`

Current issue:

- This detector is currently too eager for sectioned markdown prose. The new conversational forensic probes still logged `looks_code_heavy: true` and landed in the `extended` complexity class even though the code-specific counters were all zero.

Likely cause:

- Markdown header structure plus punctuation density appears to be enough to trip the detector even when the content itself is plain prose.

Alternate approach:

- Split the current code-heaviness check into separate signals for:
  - markdown structure
  - identifier density
  - operator density
  - path density
  - actual code keywords
- Then require a stronger combination than "section headers plus punctuation."

## Normalization passes

### 1. `normalizeFencedCodeBlocks(_:)`

What it detects:

- Triple-backtick fenced code blocks with an optional language tag.
- Pattern: `(?s)```(?:[\w.+-]+)?\n?(.*?)````.

What it does:

- Extracts the fenced body.
- Runs `spokenCode(_:)` on the body.
- Wraps the result in spoken markers:
  - `"Code sample. ... . End code sample."`

Example:

- Input:
  - ```` ```swift\nlet greeting = user?.displayName ?? "friend"\n``` ````
- Output:
  - `Code sample. let greeting equals user optional chaining display Name nil coalescing "friend". End code sample.`

Current issues:

- The regex is intentionally lightweight and does not handle more complex markdown edge cases.
- It does not support indented code blocks.
- It does not distinguish between code fences that should be read literally and code fences that should maybe be skipped or summarized.

Potential edge cases:

- Nested fences or mismatched fences.
- Four-backtick fences used to embed triple-backtick text.
- Large multi-paragraph code fences where flattening all newlines into sentence-like pauses may sound unnatural.

Test coverage:

- Indirect coverage exists through `speechTextForensicFeaturesCaptureCodeHeavyAndWeirdTextShapes()` in [ModelClientsTests.swift](/Users/galew/Workspace/SpeakSwiftly/Tests/SpeakSwiftlyTests/ModelClientsTests.swift).
- Indirect e2e coverage exists through the code-heavy forensic probes in [SpeakSwiftlyE2ETests.swift](/Users/galew/Workspace/SpeakSwiftly/Tests/SpeakSwiftlyTests/SpeakSwiftlyE2ETests.swift).
- There is no dedicated unit test that asserts the exact transformed output of a fenced code block by itself.

Alternate approach:

- Parse markdown more structurally and preserve block intent explicitly instead of using one regex.

### 2. `normalizeInlineCode(_:)`

What it detects:

- Single-backtick inline code spans.
- Pattern: `(?s)`([^`]+)``.

What it does:

- Extracts the code body.
- Runs `spokenCode(_:)`.
- Replaces the span with the spoken form surrounded by spaces.

Example:

- Input:
  - ``Please read `profile?.sampleRate ?? 24000`. ``
- Output:
  - `Please read profile optional chaining sample Rate nil coalescing 24000.`

Current issues:

- It only handles the simplest markdown inline-code form.
- It does not support multi-backtick inline spans.
- It may flatten punctuation more aggressively than desired for some short technical phrases.

Potential edge cases:

- Inline spans that intentionally contain backticks.
- Markdown that uses double-backtick or longer delimiters.
- Code spans adjacent to punctuation where surrounding spaces change phrasing more than intended.

Test coverage:

- Indirect coverage exists in:
  - `speechTextForensicFeaturesCaptureCodeHeavyAndWeirdTextShapes()`
  - `speechTextNormalizationMakesPathsAndIdentifiersMoreSpeakable()`
- There is no dedicated unit test that asserts exact inline-code-only output.

Alternate approach:

- Use a markdown parser or a small token scanner that recognizes inline-code delimiters more faithfully.

### 3. `normalizeMarkdownLinks(_:)`

What it detects:

- Basic markdown links.
- Pattern: `\[([^\]]+)\]\(([^)]+)\)`.

What it does:

- If a label exists, replaces the link with:
  - `label, link URL`
- If the label is empty, keeps only the link target.

Example:

- Input:
  - `[the docs](https://example.com/docs)`
- Output:
  - `the docs, link https://example.com/docs`

Current issues:

- The pattern is intentionally simple and will not handle nested parentheses in URLs correctly.
- It does not distinguish between links that should be spoken as URLs and links that should maybe just speak the label.

Potential edge cases:

- URLs containing parentheses.
- Reference-style markdown links.
- Autolinks like `<https://example.com>`, which are not handled here.

Test coverage:

- Indirect forensic feature coverage exists in `speechTextForensicFeaturesCaptureCodeHeavyAndWeirdTextShapes()`.
- There is no exact output assertion for markdown-link normalization alone.

Alternate approach:

- Add a user-tunable policy for links:
  - speak only label
  - speak label plus "link"
  - speak full URL

### 4. `normalizeFilePaths(_:)`

What it detects:

- Absolute or tilde-prefixed paths.
- Pattern: `(?<!\w)(~|/)[^\s`),;]+`

What it does:

- Replaces the matched path with `spokenPath(_:)`.
- `spokenPath(_:)` currently turns:
  - `~` into `home` when it appears at the start
  - `/` into `slash`
  - `\` into `backslash`
  - `.` into `dot`
  - `_` into `underscore`
  - `-` into `dash`

Example:

- Input:
  - `/Users/galew/Workspace/SpeakSwiftly/Sources/SpeakSwiftly/SpeechTextNormalizer.swift`
- Output:
  - `Users slash galew slash Workspace slash SpeakSwiftly slash Sources slash SpeakSwiftly slash SpeechTextNormalizer dot swift`

Current issues:

- It does not handle relative paths like `Sources/SpeakSwiftly`.
- It can still be a little too literal for long paths, especially when every separator is spoken.
- It does not currently collapse repeated directory patterns or recognize common filesystem landmarks more naturally.

Potential edge cases:

- URLs that contain slash-heavy paths after markdown-link normalization.
- Paths followed by punctuation that is intentionally part of the path.
- Shell globs or escaped spaces.

Test coverage:

- Exact output coverage exists in `speechTextNormalizationMakesPathsAndIdentifiersMoreSpeakable()`.
- Indirect forensic feature coverage exists in `speechTextForensicFeaturesCaptureCodeHeavyAndWeirdTextShapes()`.
- Indirect e2e coverage exists in the code-heavy segmented probes.

Alternate approach:

- Add path-specific modes such as:
  - fully literal
  - condensed directory mode
  - basename-priority mode

### 5. `normalizeIdentifierTokens(_:)`

What it detects:

- Dotted identifiers first:
  - pattern: `\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\b`
- Then snake_case identifiers:
  - pattern: `\b[a-z0-9]+(?:_[a-z0-9]+)+\b`
- Then camelCase identifiers:
  - pattern: `\b[a-z]+(?:[A-Z][a-z0-9]+)+\b`

What it does:

- Replaces each match with `spokenIdentifier(_:)`.
- `spokenIdentifier(_:)` currently turns:
  - `.` into `dot`
  - `_` into `underscore`
  - `-` into `dash`
  - lower-to-upper boundaries into spaces

Examples:

- Input:
  - `NSApplication.didFinishLaunchingNotification`
- Output:
  - `NSApplication dot did Finish Launching Notification`

- Input:
  - `camelCaseStuff`
- Output:
  - `camel Case Stuff`

- Input:
  - `snake_case_stuff`
- Output:
  - `snake underscore case underscore stuff`

Current issues:

- Dotted identifiers are only partially humanized. `NSApplication` stays fused, which may or may not be desirable.
- Objective-C selector-like forms with colons are not directly normalized by this pass.
- Hyphenated identifiers are only handled if another pattern captures them first; there is no dedicated kebab-case detector.
- The dotted-identifier regex can also catch non-code dotted tokens such as certain hostnames or abbreviations.

Potential edge cases:

- Acronyms like `URLSession.shared`.
- Mixed-case identifiers with digits.
- Selector-like Objective-C method names with colons.
- Domain names that are not code identifiers but still match dotted-token structure closely enough.

Test coverage:

- Exact output coverage exists in `speechTextNormalizationMakesPathsAndIdentifiersMoreSpeakable()`.
- Indirect forensic feature coverage exists in `speechTextForensicFeaturesCaptureCodeHeavyAndWeirdTextShapes()`.
- Indirect e2e coverage exists in the code-heavy segmented probes.

Alternate approach:

- Replace the regex-only approach with a tokenizer that classifies segments into:
  - acronym
  - word
  - number
  - separator
- Then let the spoken form preserve better distinctions like `N S Application` versus `NSApplication`.

### 6. Broad fallback: `spokenCode(_:)`

What it detects:

- This is not a detector by itself. It is the broad fallback used after `looksCodeHeavy(_:)` returns `true` late in the pipeline.

What it does:

- Replaces a fixed set of operators and punctuation with spoken phrases.
- Inserts spaces at lower-to-upper boundaries.
- Collapses whitespace.

Examples:

- Input:
  - `profile?.sampleRate ?? 24000`
- Output:
  - `profile optional chaining sample Rate nil coalescing 24000`

- Input:
  - `user.name == "Gale" && isReady`
- Output:
  - `user dot name equals equals "Gale" and is Ready`

Current issues:

- It is intentionally blunt.
- It can over-normalize plain text if `looksCodeHeavy(_:)` fires too eagerly.
- It flattens line structure aggressively by turning newlines into sentence-like pauses.
- Some spoken replacements are mechanically correct but not especially natural.

Potential edge cases:

- Plain markdown prose with headings.
- Math or symbolic prose that is not actually code.
- Text where preserving punctuation rhythm matters more than verbalizing every symbol.

Test coverage:

- Indirect coverage exists through:
  - fenced code normalization
  - inline code normalization
  - path and identifier normalization tests where inline code is present
  - code-heavy e2e probes
- There is no dedicated exact-output unit test for `spokenCode(_:)` as a standalone function.

Alternate approach:

- Split fallback behavior into multiple narrower modes:
  - operator-heavy expression mode
  - structured snippet mode
  - path-and-identifier mode
- That would avoid routing all remaining code-ish text through one blunt conversion table.

## Formatting helpers

### `collapseWhitespace(_:)`

What it does:

- Collapses repeated spaces.
- Converts repeated blank lines into `. `
- Removes whitespace before punctuation.

Current issues:

- It flattens paragraph structure very aggressively.
- It can make longer prose sound more uniform than intended.
- It is one likely reason that normalized text often reports `normalized_paragraph_count: 1` even for strongly sectioned inputs.

Potential edge cases:

- Deliberate pauses or paragraph breaks in prose.
- Poetry-like or script-like text.
- Lists where a stronger spoken break than `. ` would be preferable.

Test coverage:

- Only indirect coverage through the higher-level normalization tests.

Alternate approach:

- Preserve stronger structural markers through the normalization pipeline and let the speech side decide whether to turn them into pauses, sentences, or stronger boundaries.

## Forensic-only helpers

These helpers do not directly change the text fed into generation, but they affect what we infer from traces.

### `forensicFeatures(originalText:normalizedText:)`

What it does:

- Computes request-level counters for:
  - markdown headers
  - fenced code blocks
  - inline code spans
  - markdown links
  - file paths
  - dotted identifiers
  - camelCase tokens
  - snake_case tokens
  - Objective-C-ish symbols
  - repeated-letter weird words
  - punctuation-heavy lines
  - `looksCodeHeavy`

Current issue:

- It reports useful raw counts, but `looksCodeHeavy` is currently too blunt, so that one feature should not be over-trusted yet.

Coverage:

- Direct unit coverage exists in `speechTextForensicFeaturesCaptureCodeHeavyAndWeirdTextShapes()`.

### `forensicSections(originalText:)` and `forensicSectionWindows(...)`

What they do:

- Split the original request into:
  - markdown-header sections first
  - paragraph sections second
  - one full-request fallback section otherwise
- Weight each section by normalized character count.
- Estimate section time and chunk windows from final playback duration and chunk count.

Current issue:

- The resulting windows are estimated, not aligned to actual token or audio boundaries.

Coverage:

- Direct unit coverage exists in `speechTextForensicSectionsAndWindowsTrackSegmentedMarkdownStructure()`.
- Direct e2e coverage exists through the segmented forensic probes.

Alternate approach:

- If upstream ever exposes token-to-audio alignment or per-span chunk attribution, replace the weighted estimate with true alignment data.

## Coverage summary

Current direct unit coverage is strongest for:

- forensic feature counting
- section splitting and section-window estimation
- path normalization
- identifier normalization

Current direct unit coverage is weaker or absent for:

- fenced code block exact output
- inline code exact output
- markdown link exact output
- `spokenCode(_:)` exact output
- `collapseWhitespace(_:)` exact output
- `containsCorrectableText(_:)` exact behavior
- `looksCodeHeavy(_:)` edge behavior on markdown-only prose

## Most important current issues

### 1. Markdown-sectioned prose still looks code-heavy

This is the biggest present detector issue.

Evidence:

- The new conversational sectioned forensic probes had:
  - `file_path_count: 0`
  - `dotted_identifier_count: 0`
  - `camel_case_token_count: 0`
  - `snake_case_token_count: 0`
  - `objc_symbol_count: 0`
  - `repeated_letter_run_count: 0`
- But they still logged:
  - `looks_code_heavy: true`
  - `text_complexity_class: "extended"`

Impact:

- Ordinary prose may get more aggressive fallback normalization than intended.
- Playback policy seeding may be more conservative than warranted for plain speech.

### 2. The broad fallback is still very blunt

`spokenCode(_:)` is useful, but it is a catch-all hammer.

Impact:

- Naturalness can suffer if a false positive routes text into that fallback.

### 3. Structure gets flattened too early

`collapseWhitespace(_:)` turns many structural breaks into sentence-like output.

Impact:

- The spoken rhythm may lose some of the original text's intended shape.

## Recommended next steps

1. Tune `looksCodeHeavy(_:)` so markdown section headers alone do not make plain prose look code-heavy.
2. Add direct unit tests for:
   - fenced code output
   - inline code output
   - markdown link output
   - markdown-only prose that should stay non-code-heavy
3. Consider splitting the broad fallback into smaller fallback modes instead of one monolithic `spokenCode(_:)`.
4. Add user-tunable normalization preferences once the detectors are a little more trustworthy, especially for:
   - paths
   - identifiers
   - links
   - how literal or natural code speech should be
