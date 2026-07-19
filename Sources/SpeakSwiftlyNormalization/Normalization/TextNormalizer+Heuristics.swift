import Foundation

extension TextNormalizer {
    static func isLikelyFilePath(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        guard !token.contains("://") else { return false }
        guard !token.contains("@") else { return false }
        guard !isLikelyMeasuredValue(token) else { return false }

        return token.hasPrefix("/")
            || token.hasPrefix("~/")
            || (token.contains("/") && !token.contains(" "))
    }

    static func isLikelyEmbeddedFilePath(_ token: String) -> Bool {
        guard isLikelyFilePath(token) else { return false }
        guard !token.contains(" ") else { return false }

        if token.hasPrefix("/") || token.hasPrefix("~/") {
            return true
        }

        return token.contains("./")
            || token.contains("../")
            || token.contains("/Users/")
            || token.contains("/tmp/")
            || token.contains("/var/")
            || token.contains("/private/")
            || token.contains("/opt/")
            || token.contains("/usr/")
            || token.contains("/Library/")
            || token.contains("/Applications/")
            || token.contains("/Sources/")
            || token.contains("/Tests/")
            || token.contains("/docs/")
            || token.contains("/scripts/")
            || token.contains("/Packages/")
            || token.contains("/.build/")
            || token.contains("\\")
            || token.contains(".")
    }

    static func isLikelyURL(_ token: String) -> Bool {
        guard let schemeSeparator = token.range(of: "://") else { return false }

        let scheme = token[..<schemeSeparator.lowerBound]
        guard !scheme.isEmpty else { return false }

        return scheme.allSatisfy { $0.isLetter }
    }

    static func isLikelyCurrencyAmount(_ token: String) -> Bool {
        parsedCurrencyAmount(in: token) != nil
    }

    static func isLikelyMeasuredValue(_ token: String) -> Bool {
        parsedMeasuredValue(in: token) != nil
    }

    static func isLikelyDottedIdentifier(_ token: String) -> Bool {
        guard token.contains(".") else { return false }
        guard !isLikelyFilePath(token) else { return false }
        guard !token.contains("://") else { return false }

        let parts = token.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return false }

        return parts.allSatisfy(isDottedIdentifierSegmentLike)
    }

    static func isLikelySnakeCaseIdentifier(_ token: String) -> Bool {
        guard token.contains("_") else { return false }

        let parts = token.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return false }

        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isAlphaNumeric) }
    }

    static func isLikelyDashedIdentifier(_ token: String) -> Bool {
        guard token.contains("-") else { return false }
        guard !isLikelyFilePath(token) else { return false }
        guard !token.contains("://") else { return false }

        let parts = token.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return false }

        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isAlphaNumeric) }
    }

    static func isLikelyCamelCaseIdentifier(_ token: String) -> Bool {
        guard !token.contains("."),
              !token.contains("_"),
              !token.contains("-"),
              !token.contains("/")
        else {
            return false
        }

        return hasLowerToUpperTransition(token)
    }

    static func isLikelyFunctionCall(_ token: String) -> Bool {
        guard token.hasSuffix("()") else { return false }

        let base = String(token.dropLast(2))
        guard !base.isEmpty else { return false }
        guard !base.contains("/") else { return false }
        guard !base.contains("://") else { return false }

        let parts = base.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return false }

        return parts.allSatisfy(isIdentifierLike)
    }

    static func isLikelyIssueReference(_ token: String) -> Bool {
        guard token.hasPrefix("#") else { return false }

        let digits = token.dropFirst()
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    static func isLikelyFileLineReference(_ token: String) -> Bool {
        let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return false }

        let pathPart = parts[0]
        guard !pathPart.isEmpty else { return false }
        guard parts[1].allSatisfy(\.isNumber) else { return false }

        if parts.count == 3, !parts[2].allSatisfy(\.isNumber) {
            return false
        }

        return isLikelyFilePath(pathPart)
            || pathPart.contains(".")
    }

    static func isLikelyCLIFlag(_ token: String) -> Bool {
        guard token.hasPrefix("-") else { return false }
        guard token != "-", token != "--" else { return false }

        let body = token.drop { $0 == "-" }
        guard let first = body.first, first.isLetter else { return false }

        return body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    static func isLikelyObjectiveCSymbol(_ token: String) -> Bool {
        if token.hasPrefix("NS"), token.dropFirst(2).first?.isUppercase == true {
            return true
        }

        guard token.contains(":") else { return false }

        return token.split(separator: ":").allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isAlphaNumeric)
        }
    }

    static func isIdentifierLike(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isAlphaNumeric || $0 == "_" }
    }

    static func isDottedIdentifierSegmentLike(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isAlphaNumeric || $0 == "_" || $0 == "-" }
    }

    static func hasLowerToUpperTransition(_ text: String) -> Bool {
        var previous: Character?

        for character in text {
            defer { previous = character }
            guard let previous else { continue }

            if previous.isLowercase, character.isUppercase {
                return true
            }
        }

        return false
    }

    static func containsRepeatedLetterRun(_ text: String) -> Bool {
        var previous: Character?
        var runLength = 1

        for character in text.lowercased() {
            guard character.isLetter else {
                previous = nil
                runLength = 1
                continue
            }

            if previous == character {
                runLength += 1
                if runLength >= 3 {
                    return true
                }
            } else {
                previous = character
                runLength = 1
            }
        }

        return false
    }

    static func isLikelyCodeLine(_ line: String) -> Bool {
        let punctuation = line.filter { "{}[]()<>/\\=_*#|~:;.`-".contains($0) }.count
        let letters = line.filter(\.isLetter).count
        let hasStructuredMarker =
            line.firstMatch(of: codeMarkerRegex) != nil
                || line.contains("[")
                || line.contains("]")
                || line.contains("@property")

        return punctuation >= 6 && (punctuation * 2 >= max(letters, 4) || hasStructuredMarker)
    }
}

private extension Character {
    var isAlphaNumeric: Bool { isLetter || isNumber }
}
