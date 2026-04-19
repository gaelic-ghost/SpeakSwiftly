import Foundation

enum MarvisResidentVoice: String, Equatable {
    case conversationalA = "conversational_a"
    case conversationalB = "conversational_b"

    static func forVibe(_ vibe: SpeakSwiftly.Vibe) -> MarvisResidentVoice {
        switch vibe {
            case .femme, .androgenous:
                .conversationalA
            case .masc:
                .conversationalB
        }
    }
}

struct MarvisResidentModels {
    let conversationalA: AnySpeechModel
    let conversationalB: AnySpeechModel

    func model(for vibe: SpeakSwiftly.Vibe) -> (model: AnySpeechModel, voice: MarvisResidentVoice) {
        switch MarvisResidentVoice.forVibe(vibe) {
            case .conversationalA:
                (conversationalA, .conversationalA)
            case .conversationalB:
                (conversationalB, .conversationalB)
        }
    }
}

enum ResidentSpeechModels {
    case qwen3(AnySpeechModel)
    case chatterboxTurbo(AnySpeechModel)
    case marvis(MarvisResidentModels)

    var preloadModelRepos: [String] {
        switch self {
            case .qwen3:
                [ModelFactory.qwenResidentModelRepo]
            case .chatterboxTurbo:
                [ModelFactory.chatterboxResidentModelRepo]
            case .marvis:
                [ModelFactory.marvisResidentModelRepo]
        }
    }
}
