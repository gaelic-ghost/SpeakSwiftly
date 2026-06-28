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
    #expect(fixture.secondSlice.status == "planned_after_toy_conversion")
    #expect(fixture.secondSlice.nextCommand.contains("--mode real-boundary-plan"))
    #expect(fixture.secondSlice.acceptanceCriteria.contains("separates the main talker decode step from code-predictor continuation"))
    #expect(fixture.guardrails.contains("Do not add a public SpeechBackend for this slice."))
}

@Test func `qwen3 tts core ai export smoke records toy conversion and beta tooling`() throws {
    let fixture = try Qwen3TTSCoreAITalkerBoundaryExportSmokeFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreai_talker_boundary_export_smoke")
    #expect(fixture.status == "converted_to_coreai_ir")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.dependencies.packages.map(\.package) == ["torch", "coreai-torch"])
    #expect(fixture.dependencies.packages.allSatisfy { $0.found })
    #expect(fixture.localTooling.summary.coreaiBuildFound)
    #expect(fixture.localTooling.summary.xctraceFound)
    #expect(fixture.localTooling.summary.coreAiTemplateFound)
    #expect(fixture.targetSubgraph.name == "toy_qwen_talker_first_codec_token_boundary")
    #expect(fixture.targetSubgraph.features.contains("causal scaled_dot_product_attention"))
    #expect(fixture.missingDependencies.isEmpty)
    #expect(fixture.exportedGraph.containsScaledDotProductAttention)
    #expect(fixture.exportedGraph.containsRsqrt)
    #expect(fixture.exportedGraph.containsCos)
    #expect(fixture.exportedGraph.containsSin)
    #expect(fixture.exportedGraph.callTargetCount > 0)
    #expect(fixture.coreaiProgram.pythonType == "coreai.authoring.asset.AIProgram")
    #expect(fixture.nextAction.contains("before trying the real Qwen3-TTS talker boundary"))
}

@Test func `qwen3 tts core ai real boundary plan targets main talker decode step`() throws {
    let fixture = try Qwen3TTSCoreAIRealBoundaryPlanFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreai_real_talker_boundary_plan")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.priorEvidence.textTokenFixture == "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/text-token-fixture-0.6b-base.json")
    #expect(fixture.priorEvidence.toyCoreaiExport == "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-export-smoke-12hz.json")
    #expect(fixture.targetBoundary.name == "qwen3_tts_main_talker_decode_step_after_prefill")
    #expect(fixture.targetBoundary.included.contains("prefilled main-talker KV cache"))
    #expect(fixture.targetBoundary.identifiedNotIncluded.contains("code-predictor continuation inputs for codebooks 1 through 15"))
    #expect(fixture.targetBoundary.excluded.contains("speech-tokenizer audio decode"))
    #expect(fixture.fixtureCaptureContract.defaultStatus == "design_only_no_model_download")
    #expect(fixture.fixtureCaptureContract.runtimeCaptureRequires.contains("--allow-model-load"))
    #expect(fixture.fixtureCaptureContract.captureOutputs.contains("first-codebook logits shape and deterministic hash"))
    #expect(fixture.coreaiExportContract.route == "coreai_torch")
    #expect(fixture.coreaiExportContract.successCriteria.contains("first-codebook logits can be compared against the PyTorch fixture"))
    #expect(fixture.coreaiExportContract.stopConditions.contains("capture requires full audible generation or reference-audio conditioning"))
    #expect(fixture.decisionAfterSlice.contains("Continue CoreAI if first-token parity and boundary visibility are intact."))
}

@Test func `qwen3 tts core ai real boundary capture records pyTorch decode evidence`() throws {
    let fixture = try Qwen3TTSCoreAIRealBoundaryCaptureFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreai_real_talker_boundary_capture")
    #expect(fixture.status == "captured_real_boundary")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.dependencies.packages.allSatisfy { $0.found })
    #expect(fixture.parameters.device == "cpu")
    #expect(fixture.parameters.torchDtype == "bfloat16")
    #expect(fixture.prompt.kind == "target")
    #expect(fixture.prompt.tokenCount == 23)
    #expect(fixture.capture.talkerForwardCallCount == 3)
    #expect(fixture.capture.prefillCallCount == 1)
    #expect(fixture.capture.decodeCallCount == 2)
    #expect(fixture.capture.codePredictorGenerateCallCount == 2)
    #expect(fixture.capture.firstDecodeCall.inputIds.shape == [1, 1])
    #expect(fixture.capture.firstDecodeCall.inputIds.min == 1221.0)
    #expect(fixture.capture.firstDecodeCall.logits.shape == [1, 3072])
    #expect(fixture.capture.firstDecodeCall.logits.sha256 == "ed7457868ab0c6c0fafc41e2a0667401a9fe7e1246492de94b8958a8839a8eb2")
    #expect(fixture.capture.firstDecodeCall.logits.topk?.first?.index == 1342)
    #expect(fixture.capture.firstDecodeCall.outputPastKeyValues.sequenceLength == 10)
    #expect(fixture.capture.firstDecodeCall.outputPastKeyValues.layerCount == 28)
    #expect(fixture.capture.firstCodePredictorGenerateCall.inputsEmbeds.shape == [1, 2, 1024])
    #expect(fixture.capture.firstCodePredictorGenerateCall.sequences.shape == [1, 15])
    #expect(fixture.finalGeneration.talkerCodes.shape == [2, 16])
    #expect(fixture.finalGeneration.firstCodebookPrefix == [1221, 1342])
    #expect(fixture.nextAction.contains("CoreAI export wrapper"))
}

@Test func `qwen3 tts core ai real code predictor export records conversion evidence`() throws {
    let fixture = try Qwen3TTSCoreAIRealCodePredictorExportFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreai_real_code_predictor_export_smoke")
    #expect(fixture.status == "converted_real_code_predictor_to_coreai_ir")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.capturedInput.shape == [1, 2, 1024])
    #expect(fixture.capturedInput.sha256 == "28c0a98f004e851b6c6a97442a7828d69b227ea462ddf64d70db9d8ee562f652")
    #expect(fixture.referenceLogits.shape == [1, 2, 2048])
    #expect(fixture.referenceLogits.sha256 == "e66ed386c2eb6f1b6d14001d8d820059e99ad701ae58b9df4a803ada86173d08")
    #expect(fixture.referenceLogits.topk?.first?.index == 3100)
    #expect(fixture.torchExportAttempts.first?.strict == true)
    #expect(fixture.torchExportAttempts.first?.status == "exported")
    #expect(fixture.exportedProgramParity.maxAbsDiff == 0.0)
    #expect(fixture.exportedProgramParity.matchesReferenceWithin1E4)
    #expect(fixture.exportedProgramParity.exportedLogits.sha256 == fixture.referenceLogits.sha256)
    #expect(fixture.exportedGraph.containsScaledDotProductAttention)
    #expect(fixture.exportedGraph.containsRsqrt)
    #expect(fixture.exportedGraph.containsCos)
    #expect(fixture.exportedGraph.containsSin)
    #expect(fixture.exportedGraph.callTargetCount > 500)
    #expect(fixture.coreaiProgram.pythonType == "coreai.authoring.asset.AIProgram")
    #expect(fixture.nextAction.contains("main-talker decode export"))
}

@Test func `qwen3 tts core ai real main talker export records dtype boundary`() throws {
    let bf16Fixture = try Qwen3TTSCoreAIRealMainTalkerExportFixture.loadBF16()
    let fp32Fixture = try Qwen3TTSCoreAIRealMainTalkerExportFixture.loadFP32()

    #expect(bf16Fixture.schemaVersion == 1)
    #expect(bf16Fixture.mode == "coreai_real_main_talker_export_smoke")
    #expect(bf16Fixture.status == "converted_real_main_talker_frozen_cache_to_coreai_ir")
    #expect(bf16Fixture.parameters.torchDtype == "bfloat16")
    #expect(bf16Fixture.capturedInput.shape == [1, 1, 1024])
    #expect(bf16Fixture.capturedPositionIds.shape == [3, 1, 1])
    #expect(bf16Fixture.capturedCache.layerCount == 28)
    #expect(bf16Fixture.capturedCache.firstKey.shape == [1, 8, 9, 128])
    #expect(bf16Fixture.referenceLogits.sha256 == "ed7457868ab0c6c0fafc41e2a0667401a9fe7e1246492de94b8958a8839a8eb2")
    #expect(bf16Fixture.frozenCacheReplay.maxAbsDiff == 0.0)
    #expect(bf16Fixture.frozenCacheReplay.matchesReferenceWithinTolerance)
    #expect(bf16Fixture.torchExportAttempts.first?.strict == true)
    #expect(bf16Fixture.torchExportAttempts.first?.status == "exported")
    #expect(bf16Fixture.exportedProgramParity?.maxAbsDiff == 0.0)
    #expect(bf16Fixture.coreaiConversionError == nil)
    #expect(bf16Fixture.maskPolicy?.mode == "omitted_zero_decode_mask")
    #expect(bf16Fixture.coreaiProgram?.pythonType == "coreai.authoring.asset.AIProgram")

    #expect(fp32Fixture.status == "converted_real_main_talker_frozen_cache_to_coreai_ir")
    #expect(fp32Fixture.parameters.torchDtype == "float32")
    #expect(fp32Fixture.referenceLogits.sha256 == "e93b9457796e60dfa43af960016545f25217dcb3c4d79f9f82e92fd43f1b005c")
    #expect(fp32Fixture.frozenCacheReplay.maxAbsDiff == 0.0)
    #expect(fp32Fixture.exportedProgramParity?.maxAbsDiff == 0.0)
    #expect(fp32Fixture.exportedGraph?.containsRsqrt == true)
    #expect(fp32Fixture.exportedGraph?.containsCos == true)
    #expect(fp32Fixture.exportedGraph?.containsSin == true)
    #expect(fp32Fixture.coreaiProgram?.pythonType == "coreai.authoring.asset.AIProgram")
    #expect(fp32Fixture.nextAction.contains("mutable Core AI state"))
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
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-code-fixture-plan-libritts-r-24-12hz.json",
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
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/talker-code-fixture-plan-12hz.json",
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
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/talker-code-fixture-qwen3-12hz-summary.json",
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
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/decoder-alignment-plan-12hz.json",
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

    struct SecondSlice: Decodable {
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
    let secondSlice: SecondSlice
    let guardrails: [String]

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-plan-12hz.json",
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

    struct ExportedGraph: Decodable {
        let callTargetCount: Int
        let containsScaledDotProductAttention: Bool
        let containsRsqrt: Bool
        let containsCos: Bool
        let containsSin: Bool
    }

    struct CoreAIProgram: Decodable {
        let pythonType: String
    }

    let schemaVersion: Int
    let mode: String
    let status: String
    let source: Source
    let dependencies: Dependencies
    let localTooling: LocalTooling
    let targetSubgraph: TargetSubgraph
    let missingDependencies: [String]
    let exportedGraph: ExportedGraph
    let coreaiProgram: CoreAIProgram
    let nextAction: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-talker-boundary-export-smoke-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSCoreAIRealBoundaryPlanFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct PriorEvidence: Decodable {
        let textTokenFixture: String
        let toyCoreaiExport: String
    }

    struct TargetBoundary: Decodable {
        let name: String
        let included: [String]
        let identifiedNotIncluded: [String]
        let excluded: [String]
    }

    struct FixtureCaptureContract: Decodable {
        let defaultStatus: String
        let runtimeCaptureRequires: [String]
        let captureOutputs: [String]
    }

    struct CoreAIExportContract: Decodable {
        let route: String
        let successCriteria: [String]
        let stopConditions: [String]
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let priorEvidence: PriorEvidence
    let targetBoundary: TargetBoundary
    let fixtureCaptureContract: FixtureCaptureContract
    let coreaiExportContract: CoreAIExportContract
    let decisionAfterSlice: [String]

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-plan-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSCoreAIRealBoundaryCaptureFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct Dependencies: Decodable {
        struct Package: Decodable {
            let found: Bool
        }

        let packages: [Package]
    }

    struct Parameters: Decodable {
        let device: String
        let torchDtype: String
    }

    struct Prompt: Decodable {
        let kind: String
        let tokenCount: Int
    }

    struct Tensor: Decodable {
        struct TopK: Decodable {
            let index: Int
        }

        let shape: [Int]
        let min: Double?
        let sha256: String?
        let topk: [TopK]?
    }

    struct Cache: Decodable {
        let sequenceLength: Int?
        let layerCount: Int?
    }

    struct Capture: Decodable {
        struct DecodeCall: Decodable {
            let inputIds: Tensor
            let logits: Tensor
            let outputPastKeyValues: Cache
        }

        struct CodePredictorGenerateCall: Decodable {
            let inputsEmbeds: Tensor
            let sequences: Tensor
        }

        let talkerForwardCallCount: Int
        let prefillCallCount: Int
        let decodeCallCount: Int
        let codePredictorGenerateCallCount: Int
        let firstDecodeCall: DecodeCall
        let firstCodePredictorGenerateCall: CodePredictorGenerateCall
    }

    struct FinalGeneration: Decodable {
        let talkerCodes: Tensor
        let firstCodebookPrefix: [Int]
    }

    let schemaVersion: Int
    let mode: String
    let status: String
    let source: Source
    let dependencies: Dependencies
    let parameters: Parameters
    let prompt: Prompt
    let capture: Capture
    let finalGeneration: FinalGeneration
    let nextAction: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-boundary-capture-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSCoreAIRealCodePredictorExportFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
    }

    struct Tensor: Decodable {
        struct TopK: Decodable {
            let index: Int
        }

        let shape: [Int]
        let sha256: String?
        let topk: [TopK]?
    }

    struct TorchExportAttempt: Decodable {
        let strict: Bool
        let status: String
    }

    struct ExportedProgramParity: Decodable {
        let maxAbsDiff: Double
        let matchesReferenceWithin1E4: Bool
        let exportedLogits: Tensor
    }

    struct ExportedGraph: Decodable {
        let callTargetCount: Int
        let containsScaledDotProductAttention: Bool
        let containsRsqrt: Bool
        let containsCos: Bool
        let containsSin: Bool
    }

    struct CoreAIProgram: Decodable {
        let pythonType: String
    }

    let schemaVersion: Int
    let mode: String
    let status: String
    let source: Source
    let capturedInput: Tensor
    let referenceLogits: Tensor
    let torchExportAttempts: [TorchExportAttempt]
    let exportedProgramParity: ExportedProgramParity
    let exportedGraph: ExportedGraph
    let coreaiProgram: CoreAIProgram
    let nextAction: String

    static func load() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-code-predictor-export-smoke-12hz.json",
            as: Self.self,
        )
    }
}

private struct Qwen3TTSCoreAIRealMainTalkerExportFixture: Decodable {
    struct Parameters: Decodable {
        let torchDtype: String
    }

    struct Tensor: Decodable {
        let shape: [Int]
        let sha256: String?
    }

    struct CapturedCache: Decodable {
        let layerCount: Int
        let firstKey: Tensor
    }

    struct Replay: Decodable {
        let maxAbsDiff: Double
        let matchesReferenceWithinTolerance: Bool
    }

    struct TorchExportAttempt: Decodable {
        let strict: Bool
        let status: String
    }

    struct ExportedProgramParity: Decodable {
        let maxAbsDiff: Double
    }

    struct ExportedGraph: Decodable {
        let containsRsqrt: Bool
        let containsCos: Bool
        let containsSin: Bool
    }

    struct CoreAIProgram: Decodable {
        let pythonType: String
    }

    struct ConversionError: Decodable {
        let message: String
    }

    struct MaskPolicy: Decodable {
        let mode: String
    }

    let schemaVersion: Int
    let mode: String
    let status: String
    let parameters: Parameters
    let capturedInput: Tensor
    let capturedPositionIds: Tensor
    let capturedCache: CapturedCache
    let referenceLogits: Tensor
    let frozenCacheReplay: Replay
    let torchExportAttempts: [TorchExportAttempt]
    let exportedProgramParity: ExportedProgramParity?
    let exportedGraph: ExportedGraph?
    let coreaiProgram: CoreAIProgram?
    let coreaiConversionError: ConversionError?
    let maskPolicy: MaskPolicy?
    let nextAction: String

    static func loadBF16() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-main-talker-export-smoke-12hz.json",
            as: Self.self,
        )
    }

    static func loadFP32() throws -> Self {
        try loadQwen3TTSCoreMLPlanFixture(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/coreai-real-main-talker-export-smoke-fp32-12hz.json",
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
