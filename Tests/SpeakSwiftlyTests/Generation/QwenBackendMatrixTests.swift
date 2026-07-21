import Foundation
@preconcurrency import MLXLMCommon
@testable import SpeakSwiftly
@testable import SpeakSwiftlyTool
import Testing

private struct QwenBackendExpectation {
    let backend: SpeakSwiftly.SpeechBackend
    let rawValue: String
    let residentModelRepo: String
}

private let qwenBackendExpectations: [QwenBackendExpectation] = [
    .init(
        backend: .qwen3_smol,
        rawValue: "qwen3_smol",
        residentModelRepo: ModelFactory.qwenResidentModelRepo,
    ),
    .init(
        backend: .qwen3_smol_4bit,
        rawValue: "qwen3_smol_4bit",
        residentModelRepo: ModelFactory.qwen06B4BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_smol_5bit,
        rawValue: "qwen3_smol_5bit",
        residentModelRepo: ModelFactory.qwen06B5BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_smol_6bit,
        rawValue: "qwen3_smol_6bit",
        residentModelRepo: ModelFactory.qwen06B6BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_smol_8bit,
        rawValue: "qwen3_smol_8bit",
        residentModelRepo: ModelFactory.qwen06B8BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_smol_bf16,
        rawValue: "qwen3_smol_bf16",
        residentModelRepo: ModelFactory.qwen06BBF16ResidentModelRepo,
    ),
    .init(
        backend: .qwen3_BIG,
        rawValue: "qwen3_big",
        residentModelRepo: ModelFactory.qwen17B8BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_BIG_4bit,
        rawValue: "qwen3_big_4bit",
        residentModelRepo: ModelFactory.qwen17B4BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_BIG_5bit,
        rawValue: "qwen3_big_5bit",
        residentModelRepo: ModelFactory.qwen17B5BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_BIG_6bit,
        rawValue: "qwen3_big_6bit",
        residentModelRepo: ModelFactory.qwen17B6BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_BIG_8bit,
        rawValue: "qwen3_big_8bit",
        residentModelRepo: ModelFactory.qwen17B8BitResidentModelRepo,
    ),
    .init(
        backend: .qwen3_BIG_bf16,
        rawValue: "qwen3_big_bf16",
        residentModelRepo: ModelFactory.qwen17BBF16ResidentModelRepo,
    ),
]

@Test func `speech backend case list is exactly the qwen variant matrix`() {
    let expectedBackends = qwenBackendExpectations.map(\.backend)

    #expect(SpeakSwiftly.SpeechBackend.allCases == expectedBackends)
    #expect(SpeakSwiftly.SpeechBackend.qwenFamilyBackends == expectedBackends)
    #expect(SpeakSwiftly.SpeechBackend.qwenFamilyBackends.allSatisfy { $0.isQwenFamily })
}

@Test func `qwen backend identifiers decode from configuration and environment values`() throws {
    for expectation in qwenBackendExpectations {
        #expect(expectation.backend.rawValue == expectation.rawValue)
        #expect(SpeakSwiftly.SpeechBackend.normalized(rawValue: expectation.rawValue) == expectation.backend)
        #expect(SpeakSwiftly.SpeechBackend.normalized(rawValue: "  \(expectation.rawValue.uppercased())  ") == expectation.backend)
        #expect(SpeakSwiftly.SpeechBackend.configured(in: [
            SpeakSwiftly.SpeechBackend.environmentVariable: expectation.rawValue,
        ]) == expectation.backend)

        let decoded = try JSONDecoder().decode(
            SpeakSwiftly.SpeechBackend.self,
            from: Data(#""\#(expectation.rawValue)""#.utf8),
        )
        #expect(decoded == expectation.backend)

        let configuration = SpeakSwiftly.Configuration(speechBackend: expectation.backend)
        let roundTrippedConfiguration = try JSONDecoder().decode(
            SpeakSwiftly.Configuration.self,
            from: JSONEncoder().encode(configuration),
        )
        #expect(roundTrippedConfiguration.speechBackend == expectation.backend)
    }
}

@Test func `worker protocol decodes every qwen backend variant`() throws {
    for expectation in qwenBackendExpectations {
        let request = try ToolRequest.decode(
            from: #"{"id":"req-switch","op":"set_speech_backend","speech_backend":"\#(expectation.rawValue)"}"#,
        )
        #expect(request == .switchSpeechBackend(id: "req-switch", speechBackend: expectation.backend))
    }
}

@Test func `qwen backend variants map to resident model repos`() {
    for expectation in qwenBackendExpectations {
        let residentModelRepo = ModelFactory.residentModelRepo(for: expectation.backend)

        #expect(residentModelRepo == expectation.residentModelRepo)
        #expect(expectation.backend.residentModelRepo == expectation.residentModelRepo)
        #expect(SpeakSwiftly.SpeechBackend.qwenBackend(forResidentModelRepo: residentModelRepo)?.residentModelRepo == residentModelRepo)
    }
}

@Test func `qwen backend variants share resident generation policy`() {
    for expectation in qwenBackendExpectations {
        let parameters = GenerationPolicy.residentParameters(
            for: expectation.backend,
            text: "SpeakSwiftly should keep Qwen backend policy stable across quant variants.",
        )

        #expect(parameters.maxTokens == 4096)
        #expect(parameters.temperature == 0.6)
        #expect(parameters.topP == 0.9)
        #expect(parameters.topK == 50)
        #expect(parameters.repetitionPenalty == 1.05)
    }
}

@Test func `deterministic qwen diagnostic policy disables sampling`() {
    let parameters = GenerationPolicy.deterministicResidentParameters()

    #expect(parameters.maxTokens == 4096)
    #expect(parameters.temperature == 0)
    #expect(parameters.topP == 1)
    #expect(parameters.topK == 1)
    #expect(parameters.repetitionPenalty == 1.05)
}

@Test func `resident model helpers cover every qwen backend variant`() {
    for expectation in qwenBackendExpectations {
        let residentModels = makeResidentModels(for: expectation.backend)

        guard case let .qwen3(model) = residentModels else {
            Issue.record("Expected \(expectation.rawValue) to produce a Qwen resident test model.")
            continue
        }

        #expect(model.sampleRate == 24000)
        #expect(residentModels.preloadModelRepos.contains(expectation.residentModelRepo))
    }
}

@Test func `runtime scheduling policy stays serialized across qwen variants`() async throws {
    let runtime = try await makeRuntime(
        output: OutputRecorder(),
        playback: PlaybackSpy(),
        loadedAudioSamples: nil,
        residentModelLoader: { _ in makeResidentModel() },
        startsResidentModelsAutomatically: false,
    )

    for expectation in qwenBackendExpectations {
        let maximumConcurrentGenerationJobs = await runtime.maximumConcurrentGenerationJobs(for: expectation.backend)

        #expect(maximumConcurrentGenerationJobs == 1)
    }
}
