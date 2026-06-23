import Foundation
import Testing

@Test func `qwen3 tts decoder calibration expansion plan targets twenty four libritts samples`() throws {
    let fixture = try Qwen3TTSLibriTTSCalibrationPlanFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "preflight")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-Tokenizer-12Hz")
    #expect(fixture.source.requestedSampleCount == 24)
    #expect(fixture.source.rowOffsets?.count == 24)
    #expect(fixture.source.rowOffsets?.first == 0)
    #expect(fixture.source.rowOffsets?.last == 26000)
    #expect(fixture.samplePreviews.count == 24)
    #expect(Set(fixture.samplePreviews.map(\.speakerId)).count == 24)
    #expect(fixture.stratificationTargets.contains("short_utterances"))
    #expect(fixture.stratificationTargets.contains("medium_utterances"))
    #expect(fixture.stratificationTargets.contains("long_utterances"))
    #expect(fixture.stratificationTargets.contains("speaker_diversity"))
    #expect(fixture.stratificationTargets.contains("decoder_bucket_boundaries"))
    #expect(fixture.nextCommand.contains("--no-preflight-only"))
}

@Test func `qwen3 tts talker code fixture plan captures production decoder inputs`() throws {
    let fixture = try Qwen3TTSTalkerCodePlanFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "preflight")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice")
    #expect(fixture.generationDefaults.language == "English")
    #expect(fixture.generationDefaults.voice == "Ryan")
    #expect(fixture.generationDefaults.topK == 50)
    #expect(fixture.promptPlan.promptCount == 3)
    #expect(fixture.calibrationScope.currentGraph == "12 Hz speech-tokenizer decoder only")
    #expect(fixture.calibrationScope.currentInput.contains("immediately before speech_tokenizer.decode"))
    #expect(fixture.calibrationScope.outputAudioRole == "evaluation_only_for_coreml_activation_calibration")
    #expect(fixture.nextCommand.contains("run-with-live-service-headroom.sh"))
    #expect(fixture.nextCommand.contains("generate-talker-code-fixture.py"))
}

@Test func `qwen3 tts talker code fixture summary records captured buckets`() throws {
    let fixture = try Qwen3TTSTalkerCodeSummaryFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "runtime_summary")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice")
    #expect(fixture.fullFixturePath == ".local/coreml-qwen3tts/talker-code-fixture-qwen3-12hz.json")
    #expect(fixture.aggregate.sampleCount == 3)
    #expect(fixture.aggregate.suggestedDecoderBuckets == [72, 88])
    #expect(fixture.samples.map(\.bucketAssignment.assignedBucket) == [72, 72, 88])
    #expect(fixture.samples.map(\.encoded.audioCodesShape) == [[72, 16], [67, 16], [84, 16]])
    #expect(fixture.samples.allSatisfy { !$0.encoded.audioCodesPrefix.isEmpty })
}

@Test func `qwen3 tts decoder alignment plan keeps tuning separate from activation calibration`() throws {
    let fixture = try Qwen3TTSDecoderAlignmentPlanFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "preflight")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-Tokenizer-12Hz")
    #expect(fixture.trainingPlan.teacher == "frozen upstream PyTorch 12 Hz speech-tokenizer decoder")
    #expect(fixture.trainingPlan.student.contains("deepcopy of decoder"))
    #expect(fixture.trainingPlan.losses == ["waveform_l1", "multi_resolution_stft_l1"])
    #expect(fixture.trainingPlan.trainableScope == "decoder_tail")
    #expect(fixture.trainingPlan.sampleCount == 3)
    #expect(fixture.nextCommand.contains("run-with-live-service-headroom.sh"))
    #expect(fixture.nextCommand.contains("probe-decoder-alignment-tuning.py"))
}

@Test func `qwen3 tts core ai talker boundary plan starts with first codec token`() throws {
    let fixture = try Qwen3TTSCoreAITalkerBoundaryPlanFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreai_talker_boundary_preflight")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.targetSubgraph.name == "qwen3_tts_talker_first_codec_token_boundary")
    #expect(fixture.targetSubgraph.requiredBoundaries.contains("attention or SDPA remains compiler-visible"))
    #expect(fixture.targetSubgraph.requiredBoundaries.contains("KV cache input and output shapes are named and stable"))
    #expect(fixture.targetSubgraph.excludedFromFirstProbe.contains("speech-tokenizer audio decode"))
    #expect(fixture.runtimeRoutes.map(\.route) == [
        "coreai_torch",
        "hand_rolled_core_ml",
        "executorch_mlx",
        "executorch_core_ml",
    ])
    #expect(fixture.firstSlice.status == "preflight_only")
    #expect(fixture.firstSlice.nextCommand.contains("--mode export-smoke"))
    #expect(fixture.firstSlice.nextCommand.contains("coreai-talker-boundary-export-smoke-12hz.json"))
    #expect(fixture.firstSlice.acceptanceCriteria.contains("reports every preserved composite op boundary"))
    #expect(fixture.guardrails.contains("Do not add a public SpeechBackend for this slice."))
}

@Test func `qwen3 tts core ai export smoke records local blocker and beta tooling`() throws {
    let fixture = try Qwen3TTSCoreAITalkerBoundaryExportSmokeFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreai_talker_boundary_export_smoke")
    #expect(fixture.status == "blocked_missing_runtime_dependencies")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.dependencies.packages.map(\.package) == ["torch", "coreai-torch"])
    #expect(fixture.dependencies.packages.allSatisfy { !$0.found })
    #expect(fixture.localTooling.summary.coreaiBuildFound)
    #expect(fixture.localTooling.summary.xctraceFound)
    #expect(fixture.localTooling.summary.coreAiTemplateFound)
    #expect(fixture.targetSubgraph.name == "toy_qwen_talker_first_codec_token_boundary")
    #expect(fixture.targetSubgraph.features.contains("causal scaled_dot_product_attention"))
    #expect(fixture.missingDependencies == ["torch", "coreai-torch"])
    #expect(fixture.nextAction.contains("Do not add either package as a project dependency yet."))
}

private struct Qwen3TTSLibriTTSCalibrationPlanFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
        let requestedSampleCount: Int
        let rowOffsets: [Int]?
    }

    struct SamplePreview: Decodable {
        let rowIdx: Int?
        let speakerId: String
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let samplePreviews: [SamplePreview]
    let stratificationTargets: [String]
    let nextCommand: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/maintainers/coreml-qwen3tts/calibration-code-fixture-plan-libritts-r-24-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSTalkerCodePlanFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct GenerationDefaults: Decodable {
        let language: String
        let voice: String
        let topK: Int
    }

    struct PromptPlan: Decodable {
        let promptCount: Int
    }

    struct CalibrationScope: Decodable {
        let currentGraph: String
        let currentInput: String
        let outputAudioRole: String
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let generationDefaults: GenerationDefaults
    let promptPlan: PromptPlan
    let calibrationScope: CalibrationScope
    let nextCommand: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/maintainers/coreml-qwen3tts/talker-code-fixture-plan-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSTalkerCodeSummaryFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct Aggregate: Decodable {
        let sampleCount: Int
        let suggestedDecoderBuckets: [Int]
    }

    struct Sample: Decodable {
        struct Encoded: Decodable {
            let audioCodesShape: [Int]
            let audioCodesPrefix: [[Int]]
        }

        struct BucketAssignment: Decodable {
            let assignedBucket: Int
        }

        let encoded: Encoded
        let bucketAssignment: BucketAssignment
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let fullFixturePath: String
    let aggregate: Aggregate
    let samples: [Sample]

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/maintainers/coreml-qwen3tts/talker-code-fixture-qwen3-12hz-summary.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSDecoderAlignmentPlanFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct TrainingPlan: Decodable {
        let teacher: String
        let student: String
        let losses: [String]
        let trainableScope: String
        let sampleCount: Int
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let trainingPlan: TrainingPlan
    let nextCommand: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/maintainers/coreml-qwen3tts/decoder-alignment-plan-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSCoreAITalkerBoundaryPlanFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct TargetSubgraph: Decodable {
        let name: String
        let requiredBoundaries: [String]
        let excludedFromFirstProbe: [String]
    }

    struct RuntimeRoute: Decodable {
        let route: String
    }

    struct FirstSlice: Decodable {
        let status: String
        let nextCommand: String
        let acceptanceCriteria: [String]
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let targetSubgraph: TargetSubgraph
    let runtimeRoutes: [RuntimeRoute]
    let firstSlice: FirstSlice
    let guardrails: [String]

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/maintainers/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSCoreAITalkerBoundaryExportSmokeFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct Dependencies: Decodable {
        struct Package: Decodable {
            let package: String
            let found: Bool
        }

        let packages: [Package]
    }

    struct LocalTooling: Decodable {
        struct Summary: Decodable {
            let coreaiBuildFound: Bool
            let xctraceFound: Bool
            let coreAiTemplateFound: Bool
        }

        let summary: Summary
    }

    struct TargetSubgraph: Decodable {
        let name: String
        let features: [String]
    }

    let schemaVersion: Int
    let mode: String
    let status: String
    let source: Source
    let dependencies: Dependencies
    let localTooling: LocalTooling
    let targetSubgraph: TargetSubgraph
    let missingDependencies: [String]
    let nextAction: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/maintainers/coreml-qwen3tts/coreai-talker-boundary-export-smoke-12hz.json",
            as: Self.self,
        )
    }
}

private func loadQwen3TTSCoreMLPlanFixture<T: Decodable>(_ relativePath: String, as type: T.Type) throws -> T {
    let fixtureURL = try qwen3TTSFixtureURL(relativePath)
    let data = try Data(contentsOf: fixtureURL)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: data)
}
