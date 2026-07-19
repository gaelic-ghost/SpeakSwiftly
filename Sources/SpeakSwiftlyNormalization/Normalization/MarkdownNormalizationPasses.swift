import Foundation
import Markdown

extension TextNormalizer {
    private struct MarkdownReplacement {
        let range: Range<String.Index>
        let text: String
    }

    // MARK: Markdown Code Normalization

    static func normalizePriorityListItems(_ text: String) -> String {
        let replacements = priorityListItemReplacements(in: text)
        return applyingMarkdownReplacements(replacements, to: text)
    }

    static func normalizeFencedCodeBlocks(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        let replacements = codeBlockReplacements(
            in: text,
            requestContext: requestContext,
            profile: profile,
        )
        return applyingMarkdownReplacements(replacements, to: text)
    }

    static func normalizeInlineCodeSpans(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        let replacements = inlineCodeReplacements(
            in: text,
            requestContext: requestContext,
            profile: profile,
        )
        return applyingMarkdownReplacements(replacements, to: text)
    }

    static func normalizeMarkdownLinks(_ text: String) -> String {
        let replacements = linkReplacements(in: text)
        return applyingMarkdownReplacements(replacements, to: text)
    }

    // MARK: Markdown Replacement Collection

    private static func codeBlockReplacements(
        in text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        profile: SpeakSwiftlyNormalization.Profile,
    ) -> [MarkdownReplacement] {
        var collector = CodeBlockReplacementCollector(
            source: text,
            requestContext: requestContext,
            profile: profile,
        )
        collector.visit(markdownDocument(from: text))
        return collector.replacements
    }

    private static func inlineCodeReplacements(
        in text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
        profile: SpeakSwiftlyNormalization.Profile,
    ) -> [MarkdownReplacement] {
        var collector = InlineCodeReplacementCollector(
            source: text,
            requestContext: requestContext,
            profile: profile,
        )
        collector.visit(markdownDocument(from: text))
        return collector.replacements
    }

    private static func linkReplacements(in text: String) -> [MarkdownReplacement] {
        var collector = LinkReplacementCollector(source: text)
        collector.visit(markdownDocument(from: text))
        return collector.replacements
    }

    private static func priorityListItemReplacements(in text: String) -> [MarkdownReplacement] {
        var collector = PriorityListItemReplacementCollector(source: text)
        collector.visit(markdownDocument(from: text))
        return collector.replacements
    }

    private static func applyingMarkdownReplacements(
        _ replacements: [MarkdownReplacement],
        to text: String,
    ) -> String {
        guard !replacements.isEmpty else { return text }

        let sorted = replacements.sorted { first, second in
            first.range.lowerBound > second.range.lowerBound
        }

        var result = text
        for replacement in sorted {
            guard replacement.range.lowerBound >= result.startIndex,
                  replacement.range.upperBound <= result.endIndex else {
                continue
            }

            result.replaceSubrange(replacement.range, with: replacement.text)
        }

        return result
    }

    private static func trimmedPriorityRemainder(_ remainder: Substring) -> String {
        var normalized = remainder.drop(while: \.isWhitespace)

        if let first = normalized.first, ":.-".contains(first) {
            normalized = normalized.dropFirst()
        }

        return String(normalized).trimmingCharacters(in: .whitespaces)
    }

    private static func spokenPriorityLevel(_ level: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let spokenLevel = formatter.string(from: NSNumber(value: level))?
            .capitalized ?? String(level)

        return "Priority Level \(spokenLevel)"
    }

    private struct CodeBlockReplacementCollector: MarkupWalker {
        let source: String
        let requestContext: SpeakSwiftlyNormalization.RequestContext?
        let profile: SpeakSwiftlyNormalization.Profile
        var replacements: [MarkdownReplacement] = []

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            guard let range = stringRange(for: codeBlock, in: source) else { return }

            replacements.append(
                MarkdownReplacement(
                    range: range,
                    text: spokenCodeBlock(
                        codeBlock.code,
                        requestContext: requestContext,
                        profile: profile,
                    ),
                ),
            )
        }
    }

    private struct InlineCodeReplacementCollector: MarkupWalker {
        let source: String
        let requestContext: SpeakSwiftlyNormalization.RequestContext?
        let profile: SpeakSwiftlyNormalization.Profile
        var replacements: [MarkdownReplacement] = []

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            guard let range = stringRange(for: inlineCode, in: source) else { return }

            replacements.append(
                MarkdownReplacement(
                    range: range,
                    text: spokenInlineCode(
                        inlineCode.code,
                        requestContext: requestContext,
                        profile: profile,
                    ),
                ),
            )
        }
    }

    private struct LinkReplacementCollector: MarkupWalker {
        let source: String
        var replacements: [MarkdownReplacement] = []

        mutating func visitLink(_ link: Link) {
            guard let range = stringRange(for: link, in: source),
                  let destination = link.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !destination.isEmpty else {
                return
            }

            let label = link.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = if label.isEmpty {
                " \(destination) "
            } else {
                " \(label), link \(destination) "
            }

            replacements.append(MarkdownReplacement(range: range, text: replacement))
        }
    }

    private struct PriorityListItemReplacementCollector: MarkupWalker {
        let source: String
        var replacements: [MarkdownReplacement] = []

        mutating func visitParagraph(_ paragraph: Paragraph) {
            guard let range = stringRange(for: paragraph, in: source),
                  let replacement = priorityParagraphReplacement(in: String(source[range])) else {
                descendInto(paragraph)
                return
            }

            replacements.append(
                MarkdownReplacement(
                    range: range,
                    text: replacement,
                ),
            )
        }

        mutating func visitListItem(_ listItem: ListItem) {
            guard let range = stringRange(for: listItem, in: source),
                  let item = priorityListItem(in: listItem) else {
                descendInto(listItem)
                return
            }

            replacements.append(
                MarkdownReplacement(
                    range: range,
                    text: priorityReplacement(level: item.level, remainder: item.remainder),
                ),
            )
        }
    }

    private static func priorityListItem(in listItem: ListItem) -> (level: Int, remainder: String)? {
        priorityItem(in: plainText(in: listItem))
    }

    private static func priorityItem(in text: String) -> (level: Int, remainder: String)? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let labelEnd = content.firstIndex(of: "]") else { return nil }
        guard content.first == "[" else { return nil }

        let labelBody = content[content.index(after: content.startIndex)..<labelEnd]
        guard let first = labelBody.first, first == "P" || first == "p" else { return nil }

        let digits = labelBody.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let level = Int(digits) else {
            return nil
        }

        let remainderStart = content.index(after: labelEnd)
        return (level, trimmedPriorityRemainder(content[remainderStart...]))
    }

    private static func priorityReplacement(level: Int, remainder: String) -> String {
        let spokenPriority = spokenPriorityLevel(level)
        let trimmedRemainder = remainder.trimmingCharacters(in: .whitespaces)

        return trimmedRemainder.isEmpty ? spokenPriority : "\(spokenPriority). \(trimmedRemainder)"
    }

    private static func priorityParagraphReplacement(in text: String) -> String? {
        var changed = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let item = priorityItem(in: String(line)) else {
                return String(line)
            }

            changed = true
            return priorityReplacement(level: item.level, remainder: item.remainder)
        }

        return changed ? lines.joined(separator: "\n") : nil
    }

    private static func plainText(in markup: Markup) -> String {
        if let inline = markup as? InlineMarkup {
            return inline.plainText
        }

        return markup.children.map { plainText(in: $0) }.joined(separator: " ")
    }

    private static func stringRange(for markup: Markup, in source: String) -> Range<String.Index>? {
        guard let sourceRange = markup.range else { return nil }

        return stringRange(for: sourceRange, in: source)
    }

    private static func stringRange(for sourceRange: SourceRange, in source: String) -> Range<String.Index>? {
        guard let lowerBound = stringIndex(
            line: sourceRange.lowerBound.line,
            column: sourceRange.lowerBound.column,
            in: source,
        ),
            let upperBound = stringIndex(
                line: sourceRange.upperBound.line,
                column: sourceRange.upperBound.column,
                in: source,
            ),
            lowerBound <= upperBound else {
            return nil
        }

        return lowerBound..<upperBound
    }

    private static func stringIndex(line: Int, column: Int, in source: String) -> String.Index? {
        guard line >= 1, column >= 1 else { return nil }

        var currentLine = 1
        var lineStart = source.startIndex
        var index = source.startIndex

        while currentLine < line {
            guard index < source.endIndex else { return nil }

            if source[index] == "\n" {
                currentLine += 1
                lineStart = source.index(after: index)
            }
            index = source.index(after: index)
        }

        let utf8Offset = column - 1
        guard let utf8LineStart = lineStart.samePosition(in: source.utf8),
              let target = source.utf8.index(
                  utf8LineStart,
                  offsetBy: utf8Offset,
                  limitedBy: source.utf8.endIndex,
              ) else {
            return nil
        }

        return target.samePosition(in: source)
    }
}
