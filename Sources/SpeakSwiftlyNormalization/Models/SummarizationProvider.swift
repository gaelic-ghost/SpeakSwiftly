import Foundation

public extension SpeakSwiftlyNormalization {
    enum SummarizationProvider: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
        case codexExec
        case openAIResponses
        case foundationModels
        case test

        public var id: String { rawValue }
    }
}
