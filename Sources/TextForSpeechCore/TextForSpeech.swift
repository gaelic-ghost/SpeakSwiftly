import Foundation
import Observation

// MARK: - Public Context

public struct SpeechNormalizationContext: Codable, Sendable, Equatable {
    public let cwd: String?
    public let repoRoot: String?

    public init(cwd: String? = nil, repoRoot: String? = nil) {
        self.cwd = SpeechNormalizationContext.normalizedPath(cwd)
        self.repoRoot = SpeechNormalizationContext.normalizedPath(repoRoot)
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        let standardized = NSString(string: trimmed).standardizingPath
        return standardized.isEmpty ? nil : standardized
    }
}

// MARK: - Input Kind

public enum TextInputKind: String, Codable, CaseIterable, Sendable, Hashable {
    case plainText = "plain_text"
    case markdown
    case html
    case sourceCode = "source_code"
    case swiftSource = "swift_source"
    case pythonSource = "python_source"
    case rustSource = "rust_source"
    case log
    case cliOutput = "cli_output"
    case list

    public func matches(_ other: TextInputKind) -> Bool {
        if self == other {
            return true
        }

        switch (self, other) {
        case (.sourceCode, .swiftSource), (.sourceCode, .pythonSource), (.sourceCode, .rustSource):
            return true
        default:
            return false
        }
    }
}

// MARK: - Replacement Rules

public struct TextReplacementRule: Codable, Sendable, Equatable, Identifiable {
    public enum MatchMode: String, Codable, Sendable {
        case exactPhrase = "exact_phrase"
        case wholeToken = "whole_token"
    }

    public enum Phase: String, Codable, Sendable {
        case beforeBuiltIns = "before_built_ins"
        case afterBuiltIns = "after_built_ins"
    }

    public let id: String
    public let match: String
    public let replacement: String
    public let matchMode: MatchMode
    public let phase: Phase
    public let caseSensitive: Bool
    public let inputKinds: Set<TextInputKind>
    public let priority: Int

    public init(
        id: String = UUID().uuidString,
        match: String,
        replacement: String,
        matchMode: MatchMode = .exactPhrase,
        phase: Phase = .beforeBuiltIns,
        caseSensitive: Bool = false,
        inputKinds: Set<TextInputKind> = [],
        priority: Int = 0
    ) {
        self.id = id
        self.match = match
        self.replacement = replacement
        self.matchMode = matchMode
        self.phase = phase
        self.caseSensitive = caseSensitive
        self.inputKinds = inputKinds
        self.priority = priority
    }

    public func applies(to inputKind: TextInputKind) -> Bool {
        guard !inputKinds.isEmpty else { return true }
        return inputKinds.contains(where: { $0.matches(inputKind) })
    }
}

// MARK: - Profile

public struct TextNormalizationProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let replacementRules: [TextReplacementRule]

    public init(
        id: String = "default",
        displayName: String = "Default",
        replacementRules: [TextReplacementRule] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.replacementRules = replacementRules
    }

    public func replacementRules(
        for phase: TextReplacementRule.Phase,
        inputKind: TextInputKind
    ) -> [TextReplacementRule] {
        replacementRules
            .filter { $0.phase == phase && $0.applies(to: inputKind) }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.id < $1.id
                }
                return $0.priority > $1.priority
            }
    }
}

public extension TextNormalizationProfile {
    static let `default` = TextNormalizationProfile()
}

// MARK: - Runtime

@Observable
public final class TextNormalizationRuntime {
    public var currentProfile: TextNormalizationProfile
    public private(set) var namedProfiles: [String: TextNormalizationProfile]

    public init(
        currentProfile: TextNormalizationProfile = .default,
        namedProfiles: [String: TextNormalizationProfile] = [:]
    ) {
        self.currentProfile = currentProfile
        self.namedProfiles = namedProfiles
    }

    public func snapshot(profileID: String? = nil) -> TextNormalizationProfile {
        guard let profileID, let namedProfile = namedProfiles[profileID] else {
            return currentProfile
        }
        return namedProfile
    }

    public func replaceCurrentProfile(with profile: TextNormalizationProfile) {
        currentProfile = profile
    }

    public func upsertProfile(_ profile: TextNormalizationProfile) {
        namedProfiles[profile.id] = profile
    }

    public func removeProfile(id: String) {
        namedProfiles.removeValue(forKey: id)
        if currentProfile.id == id {
            currentProfile = .default
        }
    }
}
