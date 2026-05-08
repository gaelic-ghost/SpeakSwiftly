import Foundation

public extension SpeakSwiftly {
    // MARK: Backend Enumeration

    enum SpeechBackend: String, Codable, Sendable, Equatable, CaseIterable {
        case qwen3_smol
        case qwen3_smol_4bit
        case qwen3_smol_5bit
        case qwen3_smol_6bit
        case qwen3_smol_8bit
        case qwen3_smol_bf16
        case qwen3_BIG = "qwen3_big"
        case qwen3_BIG_4bit = "qwen3_big_4bit"
        case qwen3_BIG_5bit = "qwen3_big_5bit"
        case qwen3_BIG_6bit = "qwen3_big_6bit"
        case qwen3_BIG_8bit = "qwen3_big_8bit"
        case qwen3_BIG_bf16 = "qwen3_big_bf16"
        case chatterboxTurbo = "chatterbox_turbo"
        case marvis
        case marvis_4bit
        case marvis_6bit
    }
}

public extension SpeakSwiftly.SpeechBackend {
    // MARK: Environment

    static let environmentVariable = "SPEAKSWIFTLY_SPEECH_BACKEND"
    static let legacyQwenResidentModelEnvironmentVariable = "SPEAKSWIFTLY_QWEN_RESIDENT_MODEL"
    static let legacyQwenRawValue = "qwen3"
    static let legacyQwen17B8BitBackendRawValue = "qwen3_base_1_7b_8bit"
    static let legacyQwenCustomVoiceRawValue = "qwen3_custom_voice"
    static let legacyQwen06B8BitRawValue = "base_0_6b_8bit"
    static let legacyQwen17B8BitRawValue = "base_1_7b_8bit"

    static let qwenFamilyBackends: [Self] = [
        .qwen3_smol,
        .qwen3_smol_4bit,
        .qwen3_smol_5bit,
        .qwen3_smol_6bit,
        .qwen3_smol_8bit,
        .qwen3_smol_bf16,
        .qwen3_BIG,
        .qwen3_BIG_4bit,
        .qwen3_BIG_5bit,
        .qwen3_BIG_6bit,
        .qwen3_BIG_8bit,
        .qwen3_BIG_bf16,
    ]

    static let marvisFamilyBackends: [Self] = [
        .marvis,
        .marvis_4bit,
        .marvis_6bit,
    ]

    static func normalized(rawValue: String) -> Self? {
        let normalizedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedValue {
            case legacyQwenRawValue,
                 legacyQwenCustomVoiceRawValue,
                 legacyQwen06B8BitRawValue:
                return .qwen3_smol
            case legacyQwen17B8BitBackendRawValue,
                 legacyQwen17B8BitRawValue:
                return .qwen3_BIG
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

    static func configuredFromLegacyQwenResidentModelEnvironment(in environment: [String: String]) -> Self? {
        guard
            let rawValue = environment[legacyQwenResidentModelEnvironmentVariable],
            !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case legacyQwen06B8BitRawValue:
                return .qwen3_smol
            case legacyQwen17B8BitRawValue:
                return .qwen3_BIG
            default:
                return nil
        }
    }

    static func fromEnvironment(_ environment: [String: String]) -> Self {
        configured(in: environment)
            ?? configuredFromLegacyQwenResidentModelEnvironment(in: environment)
            ?? .qwen3_smol
    }

    internal var residentModelRepo: String {
        switch self {
            case .qwen3_smol, .qwen3_smol_8bit:
                ModelFactory.qwen06B8BitResidentModelRepo
            case .qwen3_smol_4bit:
                ModelFactory.qwen06B4BitResidentModelRepo
            case .qwen3_smol_5bit:
                ModelFactory.qwen06B5BitResidentModelRepo
            case .qwen3_smol_6bit:
                ModelFactory.qwen06B6BitResidentModelRepo
            case .qwen3_smol_bf16:
                ModelFactory.qwen06BBF16ResidentModelRepo
            case .qwen3_BIG, .qwen3_BIG_8bit:
                ModelFactory.qwen17B8BitResidentModelRepo
            case .qwen3_BIG_4bit:
                ModelFactory.qwen17B4BitResidentModelRepo
            case .qwen3_BIG_5bit:
                ModelFactory.qwen17B5BitResidentModelRepo
            case .qwen3_BIG_6bit:
                ModelFactory.qwen17B6BitResidentModelRepo
            case .qwen3_BIG_bf16:
                ModelFactory.qwen17BBF16ResidentModelRepo
            case .chatterboxTurbo:
                ModelFactory.chatterboxResidentModelRepo
            case .marvis:
                ModelFactory.marvisResidentModelRepo
            case .marvis_4bit:
                ModelFactory.marvis4BitResidentModelRepo
            case .marvis_6bit:
                ModelFactory.marvis6BitResidentModelRepo
        }
    }

    internal var isQwenFamily: Bool {
        Self.qwenFamilyBackends.contains(self)
    }

    internal var isMarvisFamily: Bool {
        Self.marvisFamilyBackends.contains(self)
    }

    internal static func qwenBackend(forResidentModelRepo modelRepo: String) -> Self? {
        qwenFamilyBackends.first { $0.residentModelRepo == modelRepo }
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
