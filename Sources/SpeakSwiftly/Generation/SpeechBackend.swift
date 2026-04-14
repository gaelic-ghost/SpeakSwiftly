import Foundation

// MARK: - SpeakSwiftly.SpeechBackend

public extension SpeakSwiftly {
    // MARK: Backend Enumeration

    enum SpeechBackend: String, Codable, Sendable, Equatable, CaseIterable {
        case qwen3
        case qwen3CustomVoice = "qwen3_custom_voice"
        case marvis
    }
}

public extension SpeakSwiftly.SpeechBackend {
    // MARK: Environment

    static let environmentVariable = "SPEAKSWIFTLY_SPEECH_BACKEND"

    static func configured(in environment: [String: String]) -> Self? {
        guard let rawValue = environment[environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !rawValue.isEmpty,
            let backend = Self(rawValue: rawValue)
        else {
            return nil
        }

        return backend
    }

    static func fromEnvironment(_ environment: [String: String]) -> Self {
        configured(in: environment) ?? .qwen3
    }

    internal var residentModelRepo: String {
        switch self {
            case .qwen3:
                ModelFactory.qwenResidentModelRepo
            case .qwen3CustomVoice:
                ModelFactory.qwenCustomVoiceResidentModelRepo
            case .marvis:
                ModelFactory.marvisResidentModelRepo
        }
    }

    internal var isQwenFamily: Bool {
        switch self {
            case .qwen3, .qwen3CustomVoice:
                true
            case .marvis:
                false
        }
    }
}
