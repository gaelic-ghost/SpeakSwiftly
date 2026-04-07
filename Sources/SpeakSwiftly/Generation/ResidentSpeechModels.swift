import Foundation

// MARK: - Resident Speech Models

enum MarvisResidentVoice: String, Sendable, Equatable {
    case conversationalA = "conversational_a"
    case conversationalB = "conversational_b"
}

struct MarvisResidentModels: Sendable {
    let conversationalA: AnySpeechModel
    let conversationalB: AnySpeechModel

    func model(for vibe: SpeakSwiftly.Vibe) -> (model: AnySpeechModel, voice: MarvisResidentVoice) {
        switch vibe {
        case .femme, .androgenous:
            (conversationalA, .conversationalA)
        case .masc:
            (conversationalB, .conversationalB)
        }
    }
}

enum ResidentSpeechModels: Sendable {
    case qwen3(AnySpeechModel)
    case marvis(MarvisResidentModels)

    var preloadModelRepos: [String] {
        switch self {
        case .qwen3:
            [ModelFactory.qwenResidentModelRepo]
        case .marvis:
            [ModelFactory.marvisResidentModelRepo, ModelFactory.marvisResidentModelRepo]
        }
    }
}
