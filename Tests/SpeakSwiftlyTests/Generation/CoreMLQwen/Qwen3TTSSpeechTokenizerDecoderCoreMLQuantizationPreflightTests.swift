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
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-fp16-compute-only-12hz.json",
    )

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

@Test func `qwen3 tts speech tokenizer decoder representative bucket 40 w8a8 smoke records output drift`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-40-fp16-representative-12hz.json",
    )

    #expect(fixture.mode == "coreml_quantization_runtime")
    #expect(fixture.source.conversionTarget.computePrecision == "float16")
    #expect(fixture.source.conversionTarget.inputShape == [1, 40, 16])
    #expect(fixture.runtime.sampleData.source == "representative_calibration_fixture")
    #expect(fixture.runtime.sampleData.bucket == 40)
    #expect(fixture.runtime.sampleData.inputShape == [1, 40, 16])
    #expect(fixture.runtime.sampleData.samples?.first?.id == "730_358_000003_000002")
    #expect(fixture.runtime.sampleData.samples?.first?.audioCodesShape == [37, 16])
    #expect(fixture.runtime.sampleData.samples?.first?.validOutputSampleCount == 71040)

    let result = try #require(fixture.runtime.results.first)
    #expect(result.status == "succeeded")
    #expect(result.mode == "w8a8_representative_smoke_compute_only")
    #expect(result.packageSizeBytes == 114_801_996)
    #expect(result.outputMatch?.quantizedOutputShape == [1, 76800])
    #expect((result.outputMatch?.maxAbsDiff ?? 0.0) > 0.28)
    #expect((result.outputMatch?.meanAbsDiff ?? 0.0) > 0.012)
    #expect(result.outputMatch?.validOutput?.sampleCount == 71040)
    #expect((result.outputMatch?.validOutput?.maxAbsDiff ?? 0.0) > 0.28)
    #expect(result.outputMatch?.paddedTail?.sampleCount == 5760)
}

@Test func `qwen3 tts speech tokenizer decoder audio inspection localizes representative w8a8 drift`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-40-w8a8-12hz.json",
    )

    #expect(fixture.mode == "coreml_decoder_audio_inspection")
    #expect(fixture.sample.id == "730_358_000003_000002")
    #expect(fixture.sample.audioCodesShape == [37, 16])
    #expect(fixture.sample.paddedInputShape == [1, 40, 16])
    #expect(fixture.sample.validOutputSampleCount == 71040)
    #expect(fixture.audio.validOutputDiff.sampleCount == 71040)
    #expect((fixture.audio.validOutputDiff.maxAbsDiff) > 0.17)
    #expect((fixture.audio.validOutputDiff.meanAbsDiff) > 0.012)
    #expect(fixture.audio.windows.count == 12)
    #expect(fixture.audio.windows.alertCount == 8)
    #expect(fixture.audio.windows.topByMeanAbsDiff.first?.startSeconds == 1.25)
    #expect(fixture.artifacts.baselineValidWav.hasSuffix("baseline-fp16-valid.wav"))
    #expect(fixture.artifacts.candidateValidWav.hasSuffix("candidate-w8a8-valid.wav"))
}

@Test func `qwen3 tts speech tokenizer decoder audio inspection localizes talker w8a8 drift`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-72-talker-qwen3-group-16-prompt-000-12hz.json",
    )

    #expect(fixture.mode == "coreml_decoder_audio_inspection")
    #expect(fixture.sample.id == "prompt-000")
    #expect(fixture.sample.audioCodesShape == [72, 16])
    #expect(fixture.sample.paddedInputShape == [1, 72, 16])
    #expect(fixture.sample.validOutputSampleCount == 138_240)
    #expect(fixture.audio.validOutputDiff.sampleCount == 138_240)
    #expect((fixture.audio.validOutputDiff.maxAbsDiff) > 0.37)
    #expect((fixture.audio.validOutputDiff.meanAbsDiff) > 0.012)
    #expect(fixture.audio.paddedTailDiff?.sampleCount == nil)
    #expect(fixture.audio.windows.count == 24)
    #expect(fixture.audio.windows.alertCount == 15)
    #expect(fixture.audio.windows.topByMeanAbsDiff.first?.startSeconds == 1.0)
    #expect(fixture.artifacts.baselineValidWav.contains("bucket-72-talker-qwen3"))
    #expect(fixture.artifacts.candidateValidWav.contains("bucket-72-talker-qwen3"))
}

@Test func `qwen3 tts speech tokenizer decoder diverse bucket 40 w8a8 records four calibration samples`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-40-fp16-libritts-r-24-diverse-group-16-12hz.json",
    )

    #expect(fixture.mode == "coreml_quantization_runtime")
    #expect(fixture.source.conversionTarget.computePrecision == "float16")
    #expect(fixture.source.conversionTarget.inputShape == [1, 40, 16])
    #expect(fixture.runtime.sampleData.source == "representative_calibration_fixture")
    #expect(fixture.runtime.sampleData.bucket == 40)
    #expect(fixture.runtime.sampleData.count == 4)
    #expect(fixture.runtime.sampleData.samples?.map(\.id) == [
        "730_358_000003_000002",
        "1183_133256_000022_000000",
        "3526_176653_000071_000006",
        "2436_2477_000070_000000",
    ])

    let result = try #require(fixture.runtime.results.first)
    #expect(result.status == "succeeded")
    #expect(result.candidateLabel == "libritts-r-24-diverse-bucket-40-group-16")
    #expect(result.calibrationOpGroupSize == 16)
    #expect(result.sampleDataCount == 4)
    #expect(result.packageSizeBytes == 114_801_996)
    #expect(result.outputMatch?.quantizedOutputShape == [1, 76800])
    #expect((result.outputMatch?.maxAbsDiff ?? 0.0) > 0.26)
    #expect((result.outputMatch?.meanAbsDiff ?? 1.0) < 0.0124)
}

@Test func `qwen3 tts speech tokenizer decoder bucket 72 w8a8 accepts talker generated codes`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-72-fp16-talker-qwen3-group-16-12hz.json",
    )

    #expect(fixture.mode == "coreml_quantization_runtime")
    #expect(fixture.source.conversionTarget.computePrecision == "float16")
    #expect(fixture.source.conversionTarget.inputShape == [1, 72, 16])
    #expect(fixture.runtime.sampleData.source == "talker_code_fixture")
    #expect(fixture.runtime.sampleData.bucket == 72)
    #expect(fixture.runtime.sampleData.count == 2)
    #expect(fixture.runtime.sampleData.samples?.map(\.id) == ["prompt-000", "prompt-001"])
    #expect(fixture.runtime.sampleData.samples?.map(\.audioCodesShape) == [[72, 16], [67, 16]])

    let result = try #require(fixture.runtime.results.first)
    #expect(result.status == "succeeded")
    #expect(result.candidateLabel == "talker-qwen3-bucket-72-group-16")
    #expect(result.mode == "w8a8_talker_smoke_compute_only")
    #expect(result.calibrationOpGroupSize == 16)
    #expect(result.sampleDataCount == 2)
    #expect(result.packageSizeBytes == 114_813_284)
    #expect(result.outputMatch?.quantizedOutputShape == [1, 138_240])
    #expect((result.outputMatch?.maxAbsDiff ?? 0.0) > 0.29)
    #expect((result.outputMatch?.meanAbsDiff ?? 0.0) > 0.011)
}

@Test func `qwen3 tts speech tokenizer decoder bucket 72 per op scopes identify lower drift candidate`() throws {
    let broad = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-72-fp16-talker-qwen3-group-16-12hz.json",
    )
    let linearMatmul = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-72-fp16-talker-qwen3-linear-matmul-group-16-12hz.json",
    )
    let convolutional = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-72-fp16-talker-qwen3-conv-convtranspose-group-16-12hz.json",
    )
    let noConvTranspose = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-72-fp16-talker-qwen3-no-convtranspose-group-16-12hz.json",
    )

    let broadResult = try #require(broad.runtime.results.first)
    let linearMatmulResult = try #require(linearMatmul.runtime.results.first)
    let convolutionalResult = try #require(convolutional.runtime.results.first)
    let noConvTransposeResult = try #require(noConvTranspose.runtime.results.first)

    #expect(linearMatmulResult.activationOpTypes == ["linear", "matmul"])
    #expect(convolutionalResult.activationOpTypes == ["conv", "conv_transpose"])
    #expect(noConvTransposeResult.activationOpTypes == ["conv", "linear", "matmul"])
    let broadMeanDiff = try #require(broadResult.outputMatch?.meanAbsDiff)
    let linearMatmulMeanDiff = try #require(linearMatmulResult.outputMatch?.meanAbsDiff)
    let convolutionalMeanDiff = try #require(convolutionalResult.outputMatch?.meanAbsDiff)
    let noConvTransposeMeanDiff = try #require(noConvTransposeResult.outputMatch?.meanAbsDiff)
    #expect(linearMatmulMeanDiff < broadMeanDiff)
    #expect(linearMatmulMeanDiff < convolutionalMeanDiff)
    #expect(linearMatmulMeanDiff < noConvTransposeMeanDiff)
    #expect(linearMatmulMeanDiff < 0.0064)
    #expect(convolutionalMeanDiff > 0.011)
    #expect(noConvTransposeMeanDiff > 0.011)
}

@Test func `qwen3 tts speech tokenizer decoder bucket 72 linear matmul audio inspection improves drift`() throws {
    let broad = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-72-talker-qwen3-group-16-prompt-000-12hz.json",
    )
    let linearMatmul = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-72-talker-qwen3-linear-matmul-group-16-prompt-000-12hz.json",
    )

    #expect(linearMatmul.mode == "coreml_decoder_audio_inspection")
    #expect(linearMatmul.sample.id == "prompt-000")
    #expect(linearMatmul.sample.audioCodesShape == [72, 16])
    #expect(linearMatmul.sample.paddedInputShape == [1, 72, 16])
    #expect(linearMatmul.sample.validOutputSampleCount == 138_240)
    #expect(linearMatmul.audio.validOutputDiff.sampleCount == 138_240)
    #expect(linearMatmul.audio.validOutputDiff.meanAbsDiff < broad.audio.validOutputDiff.meanAbsDiff)
    #expect(linearMatmul.audio.validOutputDiff.meanAbsDiff < 0.0063)
    #expect(linearMatmul.audio.windows.alertCount < broad.audio.windows.alertCount)
    #expect(linearMatmul.audio.windows.alertCount == 5)
    #expect(linearMatmul.audio.windows.topByMeanAbsDiff.first?.startSeconds == 4.25)
}

@Test func `qwen3 tts speech tokenizer decoder bucket 88 linear matmul records lower drift`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationRuntimeFixture.load(
        "speech-tokenizer-decoder-coreml-quantization-bucket-88-fp16-talker-qwen3-linear-matmul-group-16-12hz.json",
    )

    #expect(fixture.mode == "coreml_quantization_runtime")
    #expect(fixture.source.conversionTarget.computePrecision == "float16")
    #expect(fixture.source.conversionTarget.inputShape == [1, 88, 16])
    #expect(fixture.runtime.sampleData.source == "talker_code_fixture")
    #expect(fixture.runtime.sampleData.bucket == 88)
    #expect(fixture.runtime.sampleData.count == 1)
    #expect(fixture.runtime.sampleData.samples?.first?.id == "prompt-002")
    #expect(fixture.runtime.sampleData.samples?.first?.audioCodesShape == [84, 16])
    #expect(fixture.runtime.sampleData.samples?.first?.validOutputSampleCount == 161_280)

    let result = try #require(fixture.runtime.results.first)
    #expect(result.status == "succeeded")
    #expect(result.candidateLabel == "talker-qwen3-bucket-88-linear-matmul-group-16")
    #expect(result.activationOpTypes == ["linear", "matmul"])
    #expect(result.packageSizeBytes == 114_776_495)
    #expect(result.outputMatch?.validOutput?.sampleCount == 161_280)
    #expect((result.outputMatch?.meanAbsDiff ?? 1.0) < 0.005)
    #expect((result.outputMatch?.validOutput?.meanAbsDiff ?? 1.0) < 0.0049)
}

@Test func `qwen3 tts speech tokenizer decoder bucket 88 linear matmul audio inspection stays localized`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-88-talker-qwen3-linear-matmul-group-16-prompt-002-12hz.json",
    )

    #expect(fixture.mode == "coreml_decoder_audio_inspection")
    #expect(fixture.sample.id == "prompt-002")
    #expect(fixture.sample.audioCodesShape == [84, 16])
    #expect(fixture.sample.paddedInputShape == [1, 88, 16])
    #expect(fixture.sample.validOutputSampleCount == 161_280)
    #expect(fixture.audio.validOutputDiff.sampleCount == 161_280)
    #expect(fixture.audio.validOutputDiff.meanAbsDiff < 0.0049)
    #expect(fixture.audio.paddedTailDiff?.sampleCount == 7680)
    #expect(fixture.audio.windows.count == 27)
    #expect(fixture.audio.windows.alertCount == 2)
    #expect(fixture.audio.windows.topByMeanAbsDiff.first?.startSeconds == 2.0)
}

@Test func `qwen3 tts speech tokenizer decoder diverse calibration does not clear valid audio drift`() throws {
    let original = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-40-w8a8-12hz.json",
    )
    let diverse = try Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture.load(
        "speech-tokenizer-decoder-coreml-audio-inspection-bucket-40-libritts-r-24-diverse-group-16-12hz.json",
    )

    #expect(diverse.sample.id == original.sample.id)
    #expect(diverse.sample.validOutputSampleCount == original.sample.validOutputSampleCount)
    #expect(diverse.audio.validOutputDiff.meanAbsDiff > original.audio.validOutputDiff.meanAbsDiff)
    let diversePaddedTailMeanDiff = try #require(diverse.audio.paddedTailDiff?.meanAbsDiff)
    let originalPaddedTailMeanDiff = try #require(original.audio.paddedTailDiff?.meanAbsDiff)
    #expect(diversePaddedTailMeanDiff < originalPaddedTailMeanDiff)
    #expect(diverse.audio.windows.alertCount == original.audio.windows.alertCount)
    #expect(diverse.audio.windows.topByMeanAbsDiff.first?.startSeconds == 1.5)
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

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLAudioInspectionFixture: Decodable {
    struct Sample: Decodable {
        let id: String
        let audioCodesShape: [Int]
        let paddedInputShape: [Int]
        let validOutputSampleCount: Int
    }

    struct Artifacts: Decodable {
        let baselineValidWav: String
        let candidateValidWav: String
    }

    struct Audio: Decodable {
        struct Diff: Decodable {
            let sampleCount: Int
            let maxAbsDiff: Double
            let meanAbsDiff: Double
        }

        struct Windows: Decodable {
            struct Window: Decodable {
                let startSeconds: Double
            }

            let count: Int
            let alertCount: Int
            let topByMeanAbsDiff: [Window]
        }

        let validOutputDiff: Diff
        let paddedTailDiff: Diff?
        let windows: Windows
    }

    let mode: String
    let sample: Sample
    let artifacts: Artifacts
    let audio: Audio

    static func load(_ filename: String) throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/\(filename)",
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
            let inputShape: [Int]
        }

        let conversionTarget: ConversionTarget
    }

    struct Runtime: Decodable {
        struct SampleData: Decodable {
            struct Sample: Decodable {
                let id: String
                let audioCodesShape: [Int]
                let validOutputSampleCount: Int
            }

            let source: String?
            let bucket: Int?
            let count: Int
            let inputShape: [Int]
            let samples: [Sample]?
        }

        struct BaselinePrediction: Decodable {
            let outputShape: [Int]
        }

        struct Result: Decodable {
            struct OutputMatch: Decodable {
                struct OutputSlice: Decodable {
                    let sampleCount: Int
                    let maxAbsDiff: Double
                    let meanAbsDiff: Double
                }

                let computeUnits: String
                let quantizedOutputShape: [Int]
                let maxAbsDiff: Double
                let meanAbsDiff: Double
                let validOutput: OutputSlice?
                let paddedTail: OutputSlice?
            }

            let status: String
            let candidateLabel: String?
            let mode: String
            let outputPackage: String
            let packageSizeBytes: Int
            let calibrationOpGroupSize: Int
            let sampleDataCount: Int
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

    static func load(_ filename: String) throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/\(filename)",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
