enum ResidentSpeechModels {
    case qwen3(AnySpeechModel)

    var preloadModelRepos: [String] {
        switch self {
            case .qwen3:
                SpeakSwiftly.SpeechBackend.qwenFamilyBackends.map { ModelFactory.residentModelRepo(for: $0) }
        }
    }
}
