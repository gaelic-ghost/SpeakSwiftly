import Foundation

// MARK: - Speech Backend

public extension SpeakSwiftly {
    // MARK: Backend Enumeration

    enum SpeechBackend: String, Codable, Sendable, Equatable, CaseIterable {
        case qwen3
        case qwen3CustomVoice = "qwen3_custom_voice"
        case marvis
    }
}

extension SpeakSwiftly.SpeechBackend {
    // MARK: Environment

    public static let environmentVariable = "SPEAKSWIFTLY_SPEECH_BACKEND"

    public static func configured(in environment: [String: String]) -> Self? {
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

    public static func fromEnvironment(_ environment: [String: String]) -> Self {
        configured(in: environment) ?? .qwen3
    }

    var residentModelRepo: String {
        switch self {
        case .qwen3:
            ModelFactory.qwenResidentModelRepo
        case .qwen3CustomVoice:
            ModelFactory.qwenCustomVoiceResidentModelRepo
        case .marvis:
            ModelFactory.marvisResidentModelRepo
        }
    }
}
