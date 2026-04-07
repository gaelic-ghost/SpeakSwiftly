import Foundation

// MARK: - Voice Vibe

public extension SpeakSwiftly {
    enum Vibe: String, Codable, Sendable, Equatable, CaseIterable {
        case masc
        case femme
        case androgenous
    }
}
