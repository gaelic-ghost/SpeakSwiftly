import Foundation

// MARK: - Text Normalization API

public extension SpeakSwiftly.Runtime {
    nonisolated var normalizer: SpeakSwiftly.Normalizer {
        SpeakSwiftly.Normalizer(runtime: self)
    }
}
