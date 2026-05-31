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

@Test func `qwen3 tts speech tokenizer decoder quantization preflight blocks representative w8a8 until bucketed decoders exist`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLQuantizationPreflightFixture.load()

    #expect(fixture.calibrationCompatibility.syntheticRuntimeSample.audioCodesShape == [8, 16])
    #expect(fixture.calibrationCompatibility.syntheticRuntimeSample.matchesCurrentModel)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.sampleCount == 3)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.matchingSampleCount == 0)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.mismatchedSampleCount == 3)
    #expect(fixture.calibrationCompatibility.realSpeechCalibration.suggestedDecoderBuckets == [40, 72, 88])
    #expect(fixture.quantizationPlan.w8a8Representative.status == "blocked_until_bucketed_decoder_packages_exist")
    #expect(fixture.quantizationPlan.w8a8Representative.requiredDecoderInputShapes == [[1, 40, 16], [1, 72, 16], [1, 88, 16]])
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

        let syntheticRuntimeSample: SyntheticRuntimeSample
        let realSpeechCalibration: RealSpeechCalibration
    }

    struct QuantizationPlan: Decodable {
        struct W8A8Representative: Decodable {
            let status: String
            let requiredDecoderInputShapes: [[Int]]
        }

        let w8a8Representative: W8A8Representative
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
