import Foundation

extension TextNormalizer {
    struct PathCompactionDescriptor {
        let exactKey: String
        let directoryKey: String?
        let finalSegmentSpoken: String?
    }

    struct PathCompactionState {
        var seenExactPaths = Set<String>()
        var seenDirectories = Set<String>()
    }

    static func compactRepeatedFilePathPrefixes(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
    ) -> String {
        var state = PathCompactionState()

        return transformTokensStatefully(in: text, state: &state) { token, state in
            guard tokenMatches(.filePath, token: token) else { return nil }
            guard let descriptor = pathCompactionDescriptor(for: token, requestContext: requestContext) else {
                return nil
            }

            defer {
                state.seenExactPaths.insert(descriptor.exactKey)
                if let directoryKey = descriptor.directoryKey {
                    state.seenDirectories.insert(directoryKey)
                }
            }

            if state.seenExactPaths.contains(descriptor.exactKey) {
                return "same path"
            }

            if let directoryKey = descriptor.directoryKey,
               state.seenDirectories.contains(directoryKey),
               let finalSegmentSpoken = descriptor.finalSegmentSpoken {
                return "same directory, \(finalSegmentSpoken)"
            }

            return nil
        }
    }

    private static func pathCompactionDescriptor(
        for path: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext?,
    ) -> PathCompactionDescriptor? {
        let contextualPath = contextualizedPath(path, requestContext: requestContext)
        var comparableAnchor = normalizedComparableAnchor(for: contextualPath)
        var comparablePath = contextualPath.path

        if contextualPath.spokenContextPrefix == nil,
           let alias = aliasedPathPrefix(in: contextualPath.path) {
            comparableAnchor = alias.spokenName
            comparablePath = String(contextualPath.path[alias.range.upperBound...])
        } else if contextualPath.spokenContextPrefix == nil, comparablePath == "~" {
            comparableAnchor = "home"
            comparablePath = ""
        } else if contextualPath.spokenContextPrefix == nil, comparablePath.hasPrefix("~/") {
            comparableAnchor = "home"
            comparablePath = String(comparablePath.dropFirst(2))
        } else if contextualPath.spokenContextPrefix == nil, comparablePath.hasPrefix("/") {
            comparableAnchor = "/"
            comparablePath = String(comparablePath.dropFirst())
        }

        let segments = comparablePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard comparableAnchor != nil || !segments.isEmpty else { return nil }

        let keyParts = ([comparableAnchor].compactMap { $0 } + segments)
        let exactKey = keyParts.joined(separator: "\u{1F}")
        let directoryKey = if segments.isEmpty {
            comparableAnchor
        } else {
            ([comparableAnchor].compactMap { $0 } + segments.dropLast()).joined(separator: "\u{1F}")
        }

        return PathCompactionDescriptor(
            exactKey: exactKey,
            directoryKey: directoryKey?.isEmpty == true ? nil : directoryKey,
            finalSegmentSpoken: segments.last.map { spokenPath($0) },
        )
    }

    private static func normalizedComparableAnchor(
        for contextualPath: ContextualizedPath,
    ) -> String? {
        contextualPath.spokenContextPrefix
    }
}
