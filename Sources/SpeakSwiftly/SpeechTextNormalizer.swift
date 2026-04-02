import Foundation

// MARK: - Speech Text Normalization

enum SpeechTextNormalizer {
    static func normalize(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        if containsCorrectableText(normalized) {
            normalized = normalizeFencedCodeBlocks(normalized)
            normalized = normalizeInlineCode(normalized)
            normalized = normalizeMarkdownLinks(normalized)

            if looksCodeHeavy(normalized) {
                normalized = spokenCode(normalized)
            }

            normalized = collapseWhitespace(normalized)
        }

        let finalized = collapseWhitespace(normalized)
        return finalized.isEmpty ? text : finalized
    }

    private static func containsCorrectableText(_ text: String) -> Bool {
        let markers = ["```", "`", "[", "](", "->", "=>", "::", "?.", "??"]
        if markers.contains(where: text.contains) {
            return true
        }

        return looksCodeHeavy(text)
    }

    private static func normalizeFencedCodeBlocks(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?s)```(?:[\w.+-]+)?\n?(.*?)```"#
        ) { match, source in
            let body = source.substring(with: match.range(at: 1))
            let spoken = spokenCode(body)
            return spoken.isEmpty ? " Code sample. " : " Code sample. \(spoken). End code sample. "
        }
    }

    private static func normalizeInlineCode(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?s)`([^`]+)`"#
        ) { match, source in
            let body = source.substring(with: match.range(at: 1))
            let spoken = spokenCode(body)
            return spoken.isEmpty ? " code " : " \(spoken) "
        }
    }

    private static func normalizeMarkdownLinks(_ text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"\[([^\]]+)\]\(([^)]+)\)"#
        ) { match, source in
            let label = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let link = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { return " \(link) " }
            return " \(label), link \(link) "
        }
    }

    private static func looksCodeHeavy(_ text: String) -> Bool {
        let obviousMarkers = [
            "```", "`", "->", "=>", "::", "&&", "||", "==", "!=", "{", "}", "</", "/>",
            "func ", "let ", "var ", "const ", "class ", "struct ", "enum ", "return "
        ]
        if obviousMarkers.contains(where: text.contains) {
            return true
        }

        let codeCharacters = text.filter { "{}[]()<>/\\=_*#|~:;".contains($0) }.count
        let letterCharacters = text.filter(\.isLetter).count
        guard letterCharacters > 0 else { return codeCharacters > 0 }
        return Double(codeCharacters) / Double(letterCharacters) >= 0.12
    }

    private static func spokenCode(_ text: String) -> String {
        let replacements: [(String, String)] = [
            ("\n", ". "),
            ("->", " returns "),
            ("=>", " maps to "),
            ("===", " strictly equals "),
            ("!==", " not strictly equals "),
            ("==", " equals equals "),
            ("!=", " not equals "),
            ("&&", " and "),
            ("||", " or "),
            ("::", " double colon "),
            ("?.", " optional chaining "),
            ("??", " nil coalescing "),
            ("...", " ellipsis "),
            ("_", " underscore "),
            ("#", " hash "),
            ("*", " star "),
            ("{", " open brace "),
            ("}", " close brace "),
            ("[", " open bracket "),
            ("]", " close bracket "),
            ("(", " open parenthesis "),
            (")", " close parenthesis "),
            ("<", " less than "),
            (">", " greater than "),
            ("/", " slash "),
            ("\\", " backslash "),
            (":", " colon "),
            (";", " semicolon "),
            ("=", " equals "),
        ]

        var spoken = text
        for (source, replacement) in replacements {
            spoken = spoken.replacingOccurrences(of: source, with: replacement)
        }

        spoken = replacingMatches(
            in: spoken,
            pattern: #"([a-z0-9])([A-Z])"#
        ) { match, source in
            let lhs = source.substring(with: match.range(at: 1))
            let rhs = source.substring(with: match.range(at: 2))
            return "\(lhs) \(rhs)"
        }

        return collapseWhitespace(spoken)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let collapsedSpaces = text.replacingOccurrences(
            of: #"[ ]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        let collapsedLines = collapsedSpaces.replacingOccurrences(
            of: #"\n{2,}"#,
            with: ". ",
            options: .regularExpression
        )
        return collapsedLines
            .replacingOccurrences(
                of: #"\s+([,.;:?!])"#,
                with: "$1",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: (_ match: NSTextCheckingResult, _ source: NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastLocation = 0

        for match in matches {
            let matchRange = match.range
            let prefixRange = NSRange(location: lastLocation, length: matchRange.location - lastLocation)
            result += source.substring(with: prefixRange)
            result += transform(match, source)
            lastLocation = matchRange.location + matchRange.length
        }

        let suffixRange = NSRange(location: lastLocation, length: source.length - lastLocation)
        result += source.substring(with: suffixRange)
        return result
    }
}
