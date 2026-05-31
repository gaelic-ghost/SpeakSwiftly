import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder quantization preflight records core ml tools support`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreml_quantization_preflight")
    #expect(fixture.coremltools.hasLinearQuantizeWeights)
    #expect(fixture.coremltools.hasExperimentalLinearQuantizeActivations)
    #expect(fixture.source.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.source.conversionTarget.inputShape == [1, 8, 16])
}

@Test func `qwen3 tts speech tokenizer decoder quantization preflight records scoped w8a8 readiness`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightFixture.load()

    #expect(fixture.calibrationCompatibility.syntheticRuntimeSample.audioCodesShape == [8, 16])
    #expect(fixture.calibrationCompatibility.syntheticRuntimeSample.matchesCurrentModel)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.sampleCount == 3)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.matchingSampleCount == 0)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.mismatchedSampleCount == 3)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.suggestedDecoderBuckets == [40, 72, 88])
    #expect(fixture.calibrationCompatibility.bucketedDecoderConversions.status == "complete")
    #expect(fixture.calibrationCompatibility.bucketedDecoderConversions.requiredInputShapes == [[1, 40, 16], [1, 72, 16], [1, 88, 16]])
    #expect(fixture.calibrationCompatibility.bucketedDecoderConversions.pinnedReportCount == 3)
    #expect(fixture.calibrationCompatibility.bucketedDecoderConversions.missingReports.isEmpty)
    #expect(fixture.quantizationPlan.w8a8Representative.status == "ready_for_scoped_activation_probe")
    #expect(fixture.quantizationPlan.w8a8Representative.requiredDecoderInputShapes == [[1, 40, 16], [1, 72, 16], [1, 88, 16]])
    #expect(fixture.quantizationPlan.w8a8ScopeStrategy.status == "identified")
    #expect(fixture.quantizationPlan.w8a8ScopeStrategy.basePrecision == "float16")
    #expect(fixture.quantizationPlan.w8a8ScopeStrategy.activationScope == "compute_only")
    #expect(fixture.quantizationPlan.w8a8ScopeStrategy.activationOpTypes == ["conv", "linear", "matmul", "conv_transpose"])
}

@Test func `qwen3 tts speech tokenizer decoder scoped w8a8 smoke records fp16 parity`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load()

    #expect(fixture.mode == "coreml_quantization_runtime")
    #expect(fixture.source.conversionTarget.computePrecision == "float16")
    #expect(fixture.runtime.sampleData.inputShape == [1, 8, 16])
    #expect(fixture.runtime.baselinePrediction?.outputShape == [1, 15360])
    #expect(fixture.runtime.results.count == 1)

    let result = try #require(fixture.runtime.results.first)
    #expect(result.status == "succeeded")
    #expect(result.mode == "w8a8_synthetic_smoke_compute_only")
    #expect(result.outputPackage.contains("fp16-w8a8-compute-only"))
    #expect(result.packageSizeBytes == 114_795_122)
    #expect(result.activationScope == "compute_only")
    #expect(result.activationOpTypes == ["conv", "linear", "matmul", "conv_transpose"])
    #expect(result.outputMatch?.computeUnits == "cpuOnly")
    #expect(result.outputMatch?.quantizedOutputShape == [1, 15360])
    #expect((result.outputMatch?.maxAbsDiff ?? 1.0) < 0.009)
    #expect((result.outputMatch?.meanAbsDiff ?? 1.0) < 0.0023)
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightFixture: Decodable {
    struct Source: Decodable {
        struct ConversionTarget: Decodable {
            let wrapperMode: String
            let inputShape: [Int]
        }

        let conversionTarget: ConversionTarget
    }

    struct CoreMLTools: Decodable {
        let hasLinearQuantizeWeights: Bool
        let hasExperimentalLinearQuantizeActivations: Bool
    }

    struct CalibrationCompatibility: Decodable {
        struct SyntheticRuntimeSample: Decodable {
            let audioCodesShape: [Int]
            let matchesCurrentModel: Bool
        }

        struct RealSpeechCalibration: Decodable {
            let sampleCount: Int
            let matchingSampleCount: Int
            let mismatchedSampleCount: Int
            let suggestedDecoderBuckets: [Int]
        }

        struct BucketedDecoderConversions: Decodable {
            let status: String
            let requiredInputShapes: [[Int]]
            let pinnedReportCount: Int
            let missingReports: [String]
        }

        let syntheticRuntimeSample: SyntheticRuntimeSample
        let realSpeechCalibration: RealSpeechCalibration
        let bucketedDecoderConversions: BucketedDecoderConversions
    }

    struct QuantizationPlan: Decodable {
        struct W8A8Representative: Decodable {
            let status: String
            let requiredDecoderInputShapes: [[Int]]
        }

        struct W8A8ScopeStrategy: Decodable {
            let status: String
            let basePrecision: String
            let activationScope: String
            let activationOpTypes: [String]
        }

        let w8a8Representative: W8A8Representative
        let w8a8ScopeStrategy: W8A8ScopeStrategy
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let coremltools: CoreMLTools
    let calibrationCompatibility: CalibrationCompatibility
    let quantizationPlan: QuantizationPlan

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-quantization-preflight-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture: Decodable {
    struct Source: Decodable {
        struct ConversionTarget: Decodable {
            let computePrecision: String
        }

        let conversionTarget: ConversionTarget
    }

    struct Runtime: Decodable {
        struct SampleData: Decodable {
            let inputShape: [Int]
        }

        struct BaselinePrediction: Decodable {
            let outputShape: [Int]
        }

        struct Result: Decodable {
            struct OutputMatch: Decodable {
                let computeUnits: String
                let quantizedOutputShape: [Int]
                let maxAbsDiff: Double
                let meanAbsDiff: Double
            }

            let status: String
            let mode: String
            let outputPackage: String
            let packageSizeBytes: Int
            let activationScope: String
            let activationOpTypes: [String]
            let outputMatch: OutputMatch?
        }

        let sampleData: SampleData
        let baselinePrediction: BaselinePrediction?
        let results: [Result]
    }

    let mode: String
    let source: Source
    let runtime: Runtime

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-quantization-fp16-compute-only-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
