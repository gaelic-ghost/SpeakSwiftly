extension TextNormalizer {
    static func canonicalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
    }

    static func collapseWhitespace(_ text: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }

        var rebuilt = ""
        var blankLineCount = 0

        for line in lines {
            if line.isEmpty {
                blankLineCount += 1
                continue
            }

            if blankLineCount > 0, !rebuilt.isEmpty {
                rebuilt += ". "
            } else if !rebuilt.isEmpty, !rebuilt.hasSuffix(" ") {
                rebuilt += " "
            }

            rebuilt += line
            blankLineCount = 0
        }

        return rebuilt
            .replacingOccurrences(
                of: #"\s+([,.;:?!])"#,
                with: "$1",
                options: .regularExpression,
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeWhitespacePreservingLineBreaks(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(normalizeWhitespaceWithinLine)
            .joined(separator: "\n")
    }

    private static func normalizeWhitespaceWithinLine(_ line: some StringProtocol) -> String {
        line
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(
                of: #"\s+([,.;:?!])"#,
                with: "$1",
                options: .regularExpression,
            )
    }
}
