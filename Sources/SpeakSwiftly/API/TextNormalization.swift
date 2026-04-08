import Foundation
import TextForSpeech

// MARK: - Text Normalization API

public extension SpeakSwiftly {
    // MARK: Normalizer Handle

    actor Normalizer {
        let textRuntime: TextForSpeechRuntime

        public init(
            baseProfile: TextForSpeech.Profile = .base,
            activeProfile: TextForSpeech.Profile = .default,
            profiles: [String: TextForSpeech.Profile] = [:],
            persistenceURL: URL? = nil
        ) {
            textRuntime = TextForSpeechRuntime(
                baseProfile: baseProfile,
                customProfile: activeProfile,
                profiles: profiles,
                persistenceURL: persistenceURL
            )
        }
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    nonisolated var normalizer: SpeakSwiftly.Normalizer {
        normalizerRef
    }
}
