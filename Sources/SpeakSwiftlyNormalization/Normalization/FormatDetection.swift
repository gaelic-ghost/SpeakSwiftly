import Foundation

extension TextNormalizer {
    static func looksLikeHTML(_ text: String) -> Bool {
        guard text.contains("</") else { return false }

        return htmlHasStructure(text)
    }

    static func looksLikeMarkdownList(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let listLineCount = lines.count { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("+ ")
                || trimmed.firstMatch(of: /^\d+\.\s+/) != nil
        }

        return listLineCount >= 2
    }

    static func looksLikeMarkdown(_ text: String) -> Bool {
        markdownHasStructure(text)
    }

    static func looksLikeCLIOutput(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let promptLikeLines = lines.count { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("$ ")
                || trimmed.hasPrefix("% ")
                || looksLikeAnglePrompt(trimmed)
                || trimmed.firstMatch(of: /^[A-Za-z0-9_.-]+@\S+[:~]/) != nil
        }

        return promptLikeLines >= 1
    }

    static func looksLikeLogOutput(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let logLineCount = lines.count { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.firstMatch(of: /^\d{4}-\d{2}-\d{2}[ T]/) != nil
                || trimmed.contains(" ERROR ")
                || trimmed.contains(" WARN ")
                || trimmed.contains(" INFO ")
                || trimmed.contains("[error]")
                || trimmed.contains("[warn]")
                || trimmed.contains("[info]")
        }

        return logLineCount >= 1
    }

    private static func looksLikeAnglePrompt(_ line: String) -> Bool {
        guard line.hasPrefix("> ") else { return false }

        let command = line.dropFirst(2)
        guard let first = command.first else { return false }

        return first == "."
            || first == "/"
            || first == "~"
            || first == "-"
            || first == "_"
            || first.isNumber
            || first.isLowercase
    }
}
