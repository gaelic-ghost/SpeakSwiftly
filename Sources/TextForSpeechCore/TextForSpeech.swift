import Foundation
import Observation

// MARK: - Namespace

public enum TextForSpeech {
    public struct Context: Codable, Sendable, Equatable {
        public let cwd: String?
        public let repoRoot: String?

        public init(cwd: String? = nil, repoRoot: String? = nil) {
            self.cwd = Context.normalizedPath(cwd)
            self.repoRoot = Context.normalizedPath(repoRoot)
        }

        private static func normalizedPath(_ path: String?) -> String? {
            guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }

            let standardized = NSString(string: trimmed).standardizingPath
            return standardized.isEmpty ? nil : standardized
        }
    }

    public enum Kind: String, Codable, CaseIterable, Sendable, Hashable {
        case plain = "plain_text"
        case markdown
        case html
        case source = "source_code"
        case swift = "swift_source"
        case python = "python_source"
        case rust = "rust_source"
        case log
        case cli = "cli_output"
        case list

        public func matches(_ other: Self) -> Bool {
            if self == other {
                return true
            }

            switch (self, other) {
            case (.source, .swift), (.source, .python), (.source, .rust):
                return true
            default:
                return false
            }
        }
    }

    public struct Replacement: Codable, Sendable, Equatable, Identifiable {
        public enum Match: String, Codable, Sendable {
            case phrase = "exact_phrase"
            case token = "whole_token"
        }

        public enum Phase: String, Codable, Sendable {
            case beforeNormalization = "before_built_ins"
            case afterNormalization = "after_built_ins"
        }

        public let id: String
        public let text: String
        public let replacement: String
        public let match: Match
        public let phase: Phase
        public let isCaseSensitive: Bool
        public let kinds: Set<Kind>
        public let priority: Int

        public init(
            _ text: String,
            with replacement: String,
            id: String = UUID().uuidString,
            as match: Match = .phrase,
            in phase: Phase = .beforeNormalization,
            caseSensitive isCaseSensitive: Bool = false,
            for kinds: Set<Kind> = [],
            priority: Int = 0
        ) {
            self.id = id
            self.text = text
            self.replacement = replacement
            self.match = match
            self.phase = phase
            self.isCaseSensitive = isCaseSensitive
            self.kinds = kinds
            self.priority = priority
        }

        public func applies(to kind: Kind) -> Bool {
            guard !kinds.isEmpty else { return true }
            return kinds.contains(where: { $0.matches(kind) })
        }
    }

    public struct Profile: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let replacements: [Replacement]

        public init(
            id: String = "default",
            name: String = "Default",
            replacements: [Replacement] = []
        ) {
            self.id = id
            self.name = name
            self.replacements = replacements
        }

        public func replacements(
            for phase: Replacement.Phase,
            in kind: Kind
        ) -> [Replacement] {
            replacements
                .filter { $0.phase == phase && $0.applies(to: kind) }
                .sorted {
                    if $0.priority == $1.priority {
                        return $0.id < $1.id
                    }
                    return $0.priority > $1.priority
                }
        }
    }

}

public extension TextForSpeech.Profile {
    static let `default` = TextForSpeech.Profile()
}

// MARK: - Runtime

@Observable
public final class TextForSpeechRuntime {
    public var profile: TextForSpeech.Profile
    public private(set) var profiles: [String: TextForSpeech.Profile]

    public init(
        profile: TextForSpeech.Profile = .default,
        profiles: [String: TextForSpeech.Profile] = [:]
    ) {
        self.profile = profile
        self.profiles = profiles
    }

    public func snapshot(named id: String? = nil) -> TextForSpeech.Profile {
        guard let id, let storedProfile = profiles[id] else {
            return profile
        }
        return storedProfile
    }

    public func use(_ profile: TextForSpeech.Profile) {
        self.profile = profile
    }

    public func store(_ profile: TextForSpeech.Profile) {
        profiles[profile.id] = profile
    }

    public func removeProfile(named id: String) {
        profiles.removeValue(forKey: id)
        if profile.id == id {
            profile = .default
        }
    }
}

// MARK: - SpeakSwiftly Compatibility

public typealias SpeechNormalizationContext = TextForSpeech.Context
public typealias TextInputKind = TextForSpeech.Kind
public typealias TextReplacementRule = TextForSpeech.Replacement
public typealias TextNormalizationProfile = TextForSpeech.Profile
