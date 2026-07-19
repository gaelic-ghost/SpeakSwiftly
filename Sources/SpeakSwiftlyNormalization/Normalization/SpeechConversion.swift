import Foundation

extension TextNormalizer {
    enum DoubleColonSpeechPolicy {
        case silent
        case verbose
    }

    static func spokenCode(_ text: String) -> String {
        spokenCode(
            text,
            suppressingMatchedDelimiters: true,
        )
    }

    static func spokenCode(
        _ text: String,
        doubleColonPolicy: DoubleColonSpeechPolicy,
    ) -> String {
        spokenCode(
            text,
            suppressingMatchedDelimiters: true,
            doubleColonPolicy: doubleColonPolicy,
        )
    }

    static func spokenCode(
        _ text: String,
        suppressingMatchedDelimiters: Bool,
        doubleColonPolicy: DoubleColonSpeechPolicy = .silent,
    ) -> String {
        let pairSuppressed = if suppressingMatchedDelimiters {
            omittingMatchedSpeechDelimiters(in: text)
        } else {
            text
        }
        let doubleColonReplacement = switch doubleColonPolicy {
            case .silent:
                " "
            case .verbose:
                " double colon "
        }

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
            ("::", doubleColonReplacement),
            ("?.", " optional chaining "),
            ("??", " nil coalescing "),
            ("...", " ellipsis "),
            ("_", " "),
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

        let spoken = replacements.reduce(pairSuppressed) { partial, replacement in
            partial.replacingOccurrences(of: replacement.0, with: replacement.1)
        }

        return collapseWhitespace(insertWordBreaks(in: spoken))
    }

    static func omittingMatchedSpeechDelimiters(in text: String) -> String {
        enum Delimiter: Character {
            case openParenthesis = "("
            case closeParenthesis = ")"
            case openBracket = "["
            case closeBracket = "]"
            case openBrace = "{"
            case closeBrace = "}"

            var matchingOpen: Delimiter? {
                switch self {
                    case .closeParenthesis:
                        .openParenthesis
                    case .closeBracket:
                        .openBracket
                    case .closeBrace:
                        .openBrace
                    default:
                        nil
                }
            }

            var isOpening: Bool {
                matchingOpen == nil
            }
        }

        guard !text.isEmpty else { return text }

        let characters = Array(text)
        var omittedIndices = Set<Int>()
        var delimiterStack: [(delimiter: Delimiter, index: Int)] = []

        for (index, character) in characters.enumerated() {
            guard let delimiter = Delimiter(rawValue: character) else { continue }

            if delimiter.isOpening {
                delimiterStack.append((delimiter, index))
                continue
            }

            guard let matchingOpen = delimiter.matchingOpen,
                  let last = delimiterStack.last,
                  last.delimiter == matchingOpen else {
                return text
            }

            omittedIndices.insert(last.index)
            omittedIndices.insert(index)
            delimiterStack.removeLast()
        }

        guard delimiterStack.isEmpty else { return text }
        guard !omittedIndices.isEmpty else { return text }

        return String(
            characters.enumerated().map { index, character in
                omittedIndices.contains(index) ? " " : character
            },
        )
    }

    static func spokenPath(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
    ) -> String {
        let contextualPath = contextualizedPath(text, requestContext: requestContext)
        var segments: [String] = []
        var buffer = ""
        var remainder = contextualPath.path[...]

        if let spokenContextPrefix = contextualPath.spokenContextPrefix {
            segments.append(spokenContextPrefix)
        } else if let alias = aliasedPathPrefix(in: contextualPath.path) {
            segments.append(alias.spokenName)
            remainder = contextualPath.path[alias.range.upperBound...]
        } else {
            let relativePrefix = spokenRelativePathPrefix(in: contextualPath.path)
            segments += relativePrefix.prefixSegments
            remainder = relativePrefix.remainder[...]
        }

        func flushBuffer() {
            guard !buffer.isEmpty else { return }

            segments.append(spokenSegment(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in remainder {
            switch character {
                case "~":
                    flushBuffer()
                    segments.append("home")
                case "/":
                    flushBuffer()
                case "\\":
                    flushBuffer()
                case ".":
                    flushBuffer()
                    segments.append("dot")
                case "_":
                    flushBuffer()
                    segments.append(" ")
                case "-":
                    flushBuffer()
                    segments.append(" ")
                default:
                    buffer.append(character)
            }
        }

        flushBuffer()
        return collapseWhitespace(segments.joined(separator: " "))
    }

    private static func spokenRelativePathPrefix(
        in path: String,
    ) -> (prefixSegments: [String], remainder: String) {
        if path == "." || path == "./" {
            return (["current directory"], "")
        }

        if path.hasPrefix("./") {
            return (["current directory"], String(path.dropFirst(2)))
        }

        if path == ".." || path == "../" {
            return (["parent directory"], "")
        }

        var remainder = path[...]
        var prefixSegments: [String] = []

        while remainder.hasPrefix("../") {
            prefixSegments.append("parent directory")
            remainder = remainder.dropFirst(3)
        }

        if !prefixSegments.isEmpty {
            return (prefixSegments, String(remainder))
        }

        return ([], path)
    }

    static func spokenURL(_ text: String) -> String {
        guard let schemeSeparator = text.range(of: "://") else {
            if text.lowercased().hasPrefix("www.") {
                return spokenSlashSeparatedPath(String(text.dropFirst(4)))
            }

            return spokenPath(text)
        }

        let scheme = text[..<schemeSeparator.lowerBound].lowercased()
        var remainder = String(text[schemeSeparator.upperBound...])

        if ["http", "https"].contains(scheme) {
            if remainder.lowercased().hasPrefix("www.") {
                remainder.removeFirst(4)
            }

            return spokenSlashSeparatedPath(remainder)
        }

        return collapseWhitespace(
            "\(spokenSegment(String(scheme))) colon slash slash \(spokenSlashSeparatedPath(remainder))",
        )
    }

    static func spokenIdentifier(_ text: String) -> String {
        var parts: [String] = []
        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }

            parts.append(spokenSegment(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            switch character {
                case ".":
                    flushBuffer()
                    parts.append("dot")
                case "_":
                    flushBuffer()
                    parts.append(" ")
                case "-":
                    flushBuffer()
                    parts.append(" ")
                default:
                    buffer.append(character)
            }
        }

        flushBuffer()
        return collapseWhitespace(parts.joined(separator: " "))
    }

    static func spokenFunctionCall(
        _ text: String,
        style: SpeakSwiftlyNormalization.Replacement.Transform.FunctionCallStyle,
    ) -> String {
        guard text.hasSuffix("()") else { return spokenIdentifier(text) }

        let base = String(text.dropLast(2))
        let spokenBase = spokenIdentifier(base)

        switch style {
            case .compact:
                return spokenBase
            case .balanced:
                return "\(spokenBase) function"
            case .explicit:
                return "\(spokenBase) function call"
        }
    }

    static func spokenIssueReference(
        _ text: String,
        style: SpeakSwiftlyNormalization.Replacement.Transform.IssueReferenceStyle,
    ) -> String {
        let digits = text.drop { $0 == "#" }
        let number = String(digits)

        switch style {
            case .compact:
                return number
            case .balanced:
                return "issue \(number)"
            case .explicit:
                return "issue number \(number)"
        }
    }

    static func spokenFileReference(
        _ text: String,
        style: SpeakSwiftlyNormalization.Replacement.Transform.FileReferenceStyle,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
    ) -> String {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return spokenPath(text, requestContext: requestContext) }

        let file = spokenPath(parts[0], requestContext: requestContext)
        let line = parts[1]
        let column = parts.count == 3 ? parts[2] : nil

        switch style {
            case .compact:
                if let column {
                    return "\(file) \(line) \(column)"
                }
                return "\(file) \(line)"
            case .balanced:
                if let column {
                    return "\(file) line \(line) column \(column)"
                }
                return "\(file) at line \(line)"
            case .explicit:
                if let column {
                    return "file \(file) line \(line) column \(column)"
                }
                return "file \(file) at line \(line)"
        }
    }

    static func spokenCLIFlag(
        _ text: String,
        style: SpeakSwiftlyNormalization.Replacement.Transform.CLIFlagStyle,
    ) -> String {
        let isLongFlag = text.hasPrefix("--")
        let body = String(text.drop { $0 == "-" })
        let spokenBody = spokenSegment(body.replacingOccurrences(of: "-", with: " "))

        switch style {
            case .compact:
                return spokenBody
            case .balanced:
                return isLongFlag ? "double tack \(spokenBody)" : "tack \(spokenBody)"
            case .explicit:
                return isLongFlag ? "long flag \(spokenBody)" : "short flag \(spokenBody)"
        }
    }

    private static func spokenSlashSeparatedPath(_ text: String) -> String {
        var segments: [String] = []
        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }

            segments.append(spokenSegment(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in text {
            switch character {
                case "/":
                    flushBuffer()
                    if !segments.isEmpty {
                        segments.append("slash")
                    }
                case ".":
                    flushBuffer()
                    segments.append("dot")
                case "_", "-":
                    flushBuffer()
                default:
                    buffer.append(character)
            }
        }

        flushBuffer()
        return collapseWhitespace(segments.joined(separator: " "))
    }
}
