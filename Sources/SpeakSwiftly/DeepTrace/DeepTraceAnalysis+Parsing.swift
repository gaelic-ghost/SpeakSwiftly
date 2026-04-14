import Foundation

extension DeepTraceAnalysis {
    // MARK: Parsing

    static func fencedCodeBlockBodies(in text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var bodies: [String] = []
        var buffer: [String] = []
        var insideFence = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if insideFence {
                    bodies.append(buffer.joined(separator: "\n"))
                    buffer.removeAll(keepingCapacity: true)
                }
                insideFence.toggle()
                continue
            }

            if insideFence {
                buffer.append(line)
            }
        }

        if insideFence, !buffer.isEmpty {
            bodies.append(buffer.joined(separator: "\n"))
        }

        return bodies
    }

    static func inlineCodeBodies(in text: String) -> [String] {
        var bodies: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "`" else {
                index = text.index(after: index)
                continue
            }

            let contentStart = text.index(after: index)
            guard let closing = text[contentStart...].firstIndex(of: "`") else {
                break
            }

            bodies.append(String(text[contentStart..<closing]))
            index = text.index(after: closing)
        }

        return bodies
    }

    static func markdownLinks(in text: String) -> [MarkdownLinkMatch] {
        var matches: [MarkdownLinkMatch] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let labelStart = text[cursor...].firstIndex(of: "[") else { break }
            guard let labelEnd = text[labelStart...].firstRange(of: "](")?.lowerBound else {
                cursor = text.index(after: labelStart)
                continue
            }

            let destinationStart = text.index(labelEnd, offsetBy: 2)
            guard let destinationEnd = text[destinationStart...].firstIndex(of: ")") else {
                cursor = text.index(after: labelStart)
                continue
            }

            let fullRange = labelStart..<text.index(after: destinationEnd)
            matches.append(
                MarkdownLinkMatch(
                    fullRange: fullRange,
                    label: String(text[text.index(after: labelStart)..<labelEnd]),
                    destination: String(text[destinationStart..<destinationEnd]),
                ),
            )
            cursor = fullRange.upperBound
        }

        return matches
    }

    static func candidateTokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(trimmedCandidateToken)
            .filter { !$0.isEmpty }
    }

    static func filePathFragments(in text: String) -> [String] {
        var fragments: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let startsTildePath = character == "~"
                && text.index(after: index) < text.endIndex
                && text[text.index(after: index)] == "/"

            guard character == "/" || startsTildePath else {
                index = text.index(after: index)
                continue
            }

            let start = index
            var end = index

            while end < text.endIndex {
                let current = text[end]
                if current.isWhitespace || "`),;\"[]{}".contains(current) {
                    break
                }
                end = text.index(after: end)
            }

            let fragment = String(text[start..<end])
            if isLikelyFilePath(fragment) {
                fragments.append(fragment)
            }

            index = end
        }

        return fragments
    }

    static func paragraphCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        return trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    static func trimmedCandidateToken(_ token: String) -> String {
        let punctuation = CharacterSet(charactersIn: "\"'()[]{}<>.,;:!?")
        var start = token.startIndex
        var end = token.endIndex

        while start < end,
              token[start].unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            start = token.index(after: start)
        }

        while end > start {
            let beforeEnd = token.index(before: end)
            guard token[beforeEnd].unicodeScalars.allSatisfy({ punctuation.contains($0) }) else {
                break
            }

            end = beforeEnd
        }

        return String(token[start..<end])
    }
}
