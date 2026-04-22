import Foundation

enum MarvisResidentVoice: String, Equatable {
    case conversationalA = "conversational_a"
    case conversationalB = "conversational_b"

    static func forVibe(_ vibe: SpeakSwiftly.Vibe) -> MarvisResidentVoice {
        switch vibe {
            case .femme:
                .conversationalA
            case .masc:
                .conversationalB
        }
    }
}

enum MarvisResidentModels {
    case dual(
        conversationalA: AnySpeechModel,
        conversationalB: AnySpeechModel,
    )
    case single(AnySpeechModel)

    var primaryModel: AnySpeechModel {
        switch self {
            case let .dual(conversationalA, _):
                conversationalA
            case let .single(model):
                model
        }
    }

    func model(for vibe: SpeakSwiftly.Vibe) -> (model: AnySpeechModel, voice: MarvisResidentVoice) {
        let voice = MarvisResidentVoice.forVibe(vibe)

        switch self {
            case let .dual(conversationalA, conversationalB):
                switch voice {
                    case .conversationalA:
                        return (conversationalA, MarvisResidentVoice.conversationalA)
                    case .conversationalB:
                        return (conversationalB, MarvisResidentVoice.conversationalB)
                }
            case let .single(model):
                return (model, voice)
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
