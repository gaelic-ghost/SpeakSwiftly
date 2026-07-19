import SpeakSwiftlyCore

public extension SpeakSwiftlyNormalization {
    typealias TextFormat = SpeakSwiftlyCore.TextFormat
    typealias SourceFormat = SpeakSwiftlyCore.SourceFormat
}

// MARK: - NormalizationFormat

enum NormalizationFormat: Hashable {
    case text(SpeakSwiftlyNormalization.TextFormat)
    case source(SpeakSwiftlyNormalization.SourceFormat)
}
