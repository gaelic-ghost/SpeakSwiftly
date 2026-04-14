extension DeepTraceAnalysis {
    // MARK: Heuristics

    static func isLikelyFilePath(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        guard !token.contains("://") else { return false }
        guard !token.contains("@") else { return false }

        return token.hasPrefix("/")
            || token.hasPrefix("~/")
            || (token.contains("/") && !token.contains(" "))
    }

    static func isLikelyURL(_ token: String) -> Bool {
        guard let schemeSeparator = token.range(of: "://") else { return false }

        let scheme = token[..<schemeSeparator.lowerBound]
        guard !scheme.isEmpty else { return false }

        return scheme.allSatisfy { $0.isLetter }
    }

    static func isLikelyDottedIdentifier(_ token: String) -> Bool {
        guard token.contains(".") else { return false }
        guard !isLikelyFilePath(token) else { return false }
        guard !token.contains("://") else { return false }

        let parts = token.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return false }

        return parts.allSatisfy(isIdentifierLike)
    }

    static func isLikelySnakeCaseIdentifier(_ token: String) -> Bool {
        guard token.contains("_") else { return false }

        let parts = token.split(separator: "_").map(String.init)
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
}
