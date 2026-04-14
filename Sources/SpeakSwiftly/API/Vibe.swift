import Foundation

// MARK: - Voice Vibe

public extension SpeakSwiftly {
    /// The broad vocal presentation used when creating a voice profile.
    enum Vibe: String, Codable, Sendable, Equatable, CaseIterable {
        case masc
        case femme
        case androgenous
    }
}
