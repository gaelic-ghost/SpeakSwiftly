import Foundation

extension TextNormalizer {
    struct ContextualizedPath {
        let path: String
        let spokenContextPrefix: String?
    }

    static func aliasedPathPrefix(in text: String) -> (range: Range<String.Index>, spokenName: String)? {
        let aliases = [
            ("/Users/galew", "gale wumbo"),
            ("/Users/galem", "gale mini"),
        ]

        for (prefix, spokenName) in aliases {
            guard text.hasPrefix(prefix) else { continue }

            let prefixEnd = text.index(text.startIndex, offsetBy: prefix.count)
            let isExactMatch = prefixEnd == text.endIndex
            let continuesAsPath = !isExactMatch && text[prefixEnd] == "/"
            if isExactMatch || continuesAsPath {
                return (text.startIndex..<prefixEnd, spokenName)
            }
        }

        return nil
    }

    static func standaloneGaleAlias(for token: String) -> String? {
        switch token.lowercased() {
            case "galew":
                "gale wumbo"
            case "galem":
                "gale mini"
            default:
                nil
        }
    }

    static func contextualizedPath(
        _ path: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
    ) -> ContextualizedPath {
        guard path.hasPrefix("/") else {
            return ContextualizedPath(path: path, spokenContextPrefix: nil)
        }

        let standardizedPath = NSString(string: path).standardizingPath

        if let cwd = requestContext?.cwd,
           let relativePath = relativePath(from: cwd, to: standardizedPath) {
            let spokenContextPrefix = "current directory"
            return ContextualizedPath(path: relativePath, spokenContextPrefix: spokenContextPrefix)
        }

        if let repoRoot = requestContext?.repoRoot,
           let relativePath = relativePath(from: repoRoot, to: standardizedPath) {
            let spokenContextPrefix = "repo root"
            return ContextualizedPath(path: relativePath, spokenContextPrefix: spokenContextPrefix)
        }

        return ContextualizedPath(path: standardizedPath, spokenContextPrefix: nil)
    }

    private static func relativePath(from basePath: String, to path: String) -> String? {
        let standardizedBasePath = NSString(string: basePath).standardizingPath

        guard standardizedPathBoundaryMatches(path, prefix: standardizedBasePath) else {
            return nil
        }
        guard path.count > standardizedBasePath.count else {
            return ""
        }

        let relativeStart = path.index(path.startIndex, offsetBy: standardizedBasePath.count + 1)
        return String(path[relativeStart...])
    }

    private static func standardizedPathBoundaryMatches(_ path: String, prefix: String) -> Bool {
        guard path.hasPrefix(prefix) else { return false }
        guard path.count > prefix.count else { return true }

        let boundaryIndex = path.index(path.startIndex, offsetBy: prefix.count)
        return path[boundaryIndex] == "/"
    }
}
