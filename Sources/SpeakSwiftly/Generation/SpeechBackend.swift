import Foundation

// MARK: - SpeakSwiftly.SpeechBackend

public extension SpeakSwiftly {
    // MARK: Backend Enumeration

    enum SpeechBackend: String, Codable, Sendable, Equatable, CaseIterable {
        case qwen3
        case marvis
    }
}

public extension SpeakSwiftly.SpeechBackend {
    // MARK: Environment

    static let environmentVariable = "SPEAKSWIFTLY_SPEECH_BACKEND"
    static let legacyQwenCustomVoiceRawValue = "qwen3_custom_voice"

    static func normalized(rawValue: String) -> Self? {
        let normalizedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedValue {
            case legacyQwenCustomVoiceRawValue:
                return .qwen3
            default:
                return Self(rawValue: normalizedValue)
        }
    }

    static func configured(in environment: [String: String]) -> Self? {
        guard let rawValue = environment[environmentVariable], !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return normalized(rawValue: rawValue)
    }

    static func fromEnvironment(_ environment: [String: String]) -> Self {
        configured(in: environment) ?? .qwen3
    }

    internal var residentModelRepo: String {
        switch self {
            case .qwen3:
                ModelFactory.qwenResidentModelRepo
            case .marvis:
                ModelFactory.marvisResidentModelRepo
        }
    }

    internal var isQwenFamily: Bool {
        switch self {
            case .qwen3:
                true
            case .marvis:
                false
        }
    }
}

public extension SpeakSwiftly.SpeechBackend {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let backend = Self.normalized(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "SpeakSwiftly could not decode speech backend '\(rawValue)' because it is not one of the supported backend identifiers.",
            )
        }

        self = backend
    }
}
