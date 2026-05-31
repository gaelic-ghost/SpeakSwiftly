import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder core ml preflight pins conversion target`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLPreflightFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "preflight")
    #expect(fixture.conversionTarget.stage == "speech_tokenizer_decoder")
    #expect(fixture.conversionTarget.inputName == "audio_codes")
    #expect(fixture.conversionTarget.inputShape == [1, 8, 16])
    #expect(fixture.conversionTarget.inputDtype == "int64")
    #expect(fixture.conversionTarget.expectedOutputShape == [1, 15360])
    #expect(fixture.conversionTarget.expectedOutputSampleRate == 24000)
    #expect(fixture.conversionTarget.convertTo == "mlprogram")
    #expect(fixture.conversionTarget.padding.originalCodeSteps == 8)
    #expect(fixture.conversionTarget.padding.requestedCodeSteps == 8)
    #expect(fixture.conversionTarget.padding.paddedStepCount == 0)
    #expect(fixture.conversionTarget.padding.samplesPerCodeStep == 1920)
    #expect(fixture.nextCommand.contains("--python 3.12"))
    #expect(fixture.nextCommand.contains("--with 'coremltools>=8.3.0,<10'"))
    #expect(fixture.nextCommand.contains("--with 'torch==2.7.0'"))
    #expect(fixture.nextCommand.contains("--capture-mode export"))
    #expect(fixture.nextCommand.contains("--export-decomposed"))
    #expect(fixture.nextCommand.contains("--wrapper-mode fixed_16q_static_mask"))
    #expect(fixture.nextCommand.contains("--verify-coreml-prediction"))
}

@Test func `qwen3 tts speech tokenizer decoder core ml conversion records trace blocker`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-12hz.json",
    )

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "runtime")
    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.12.0")
    #expect(fixture.conversionTarget.inputShape == [1, 8, 16])
    #expect(fixture.conversionTarget.torchOutputShape == [1, 15360])
    #expect(fixture.trace.status == "failed")
    #expect(fixture.trace.errorType == "RuntimeError")
    #expect(fixture.trace.errorMessage == "unordered_map::at: key not found")
    #expect(fixture.conversion.status == "not_started")
}

@Test func `qwen3 tts speech tokenizer decoder core ml torch27 conversion records same trace blocker`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-torch27-12hz.json",
    )

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "runtime")
    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "upstream")
    #expect(fixture.conversionTarget.inputShape == [1, 8, 16])
    #expect(fixture.conversionTarget.torchOutputShape == [1, 15360])
    #expect(fixture.trace.status == "failed")
    #expect(fixture.trace.captureMode == "trace")
    #expect(fixture.trace.errorType == "RuntimeError")
    #expect(fixture.trace.errorMessage == "unordered_map::at: key not found")
    #expect(fixture.conversion.status == "not_started")
}

@Test func `qwen3 tts speech tokenizer decoder core ml fixed quantizer wrapper matches upstream output`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-fixed16q-12hz.json",
    )

    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "fixed_16q")
    #expect(fixture.conversionTarget.captureMode == "trace")
    #expect(fixture.conversionTarget.torchOutputShape == [1, 15360])
    #expect(fixture.conversionTarget.upstreamMaxAbsDiff == 0.0)
    #expect(fixture.trace.status == "failed")
    #expect(fixture.trace.captureMode == "trace")
    #expect(fixture.trace.errorMessage == "unordered_map::at: key not found")
    #expect(fixture.conversion.status == "not_started")
}

@Test func `qwen3 tts speech tokenizer decoder core ml export probes record transformer mask blockers`() throws {
    let nonStrictFixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-export-fixed16q-12hz.json",
    )
    let strictFixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-export-strict-fixed16q-12hz.json",
    )

    #expect(nonStrictFixture.conversionTarget.wrapperMode == "fixed_16q")
    #expect(nonStrictFixture.conversionTarget.captureMode == "export")
    #expect(nonStrictFixture.conversionTarget.upstreamMaxAbsDiff == 0.0)
    #expect(nonStrictFixture.trace.status == "failed")
    #expect(nonStrictFixture.trace.strict == false)
    #expect(nonStrictFixture.trace.errorType == "RuntimeError")
    #expect(nonStrictFixture.trace.errorMessage?.contains("is_contiguous inside of vmap") == true)

    #expect(strictFixture.conversionTarget.wrapperMode == "fixed_16q")
    #expect(strictFixture.conversionTarget.captureMode == "export")
    #expect(strictFixture.conversionTarget.upstreamMaxAbsDiff == 0.0)
    #expect(strictFixture.trace.status == "failed")
    #expect(strictFixture.trace.strict == true)
    #expect(strictFixture.trace.errorType == "TorchRuntimeError")
    #expect(strictFixture.trace.errorMessage?.contains("calling .item() on a Tensor") == true)
    #expect(strictFixture.trace.errorMessage?.contains("<local-home-path>") == true)
    #expect(strictFixture.conversion.status == "not_started")
}

@Test func `qwen3 tts speech tokenizer decoder core ml static mask export converts and predicts`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-static-mask-export-decomposed-12hz.json",
    )

    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.conversionTarget.captureMode == "export")
    #expect(fixture.conversionTarget.exportDecomposed == true)
    #expect(fixture.conversionTarget.upstreamMaxAbsDiff == 0.0)
    #expect(fixture.trace.status == "succeeded")
    #expect(fixture.trace.captureMode == "export")
    #expect(fixture.trace.exportDecomposed == true)
    #expect(fixture.conversion.status == "succeeded")
    #expect(fixture.outputMatch?.status == "succeeded")
    #expect(fixture.outputMatch?.computeUnits == "cpuOnly")
    #expect(fixture.outputMatch?.coremlOutputShape == [1, 15360])
    #expect((fixture.outputMatch?.maxAbsDiff ?? 1.0) < 0.0001)
}

@Test func `qwen3 tts speech tokenizer decoder core ml fp16 export converts and predicts`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-fp16-12hz.json",
    )

    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.conversionTarget.computePrecision == "float16")
    #expect(fixture.conversionTarget.inputShape == [1, 8, 16])
    #expect(fixture.conversionTarget.torchOutputShape == [1, 15360])
    #expect(fixture.trace.status == "succeeded")
    #expect(fixture.conversion.status == "succeeded")
    #expect(fixture.outputMatch?.status == "succeeded")
    #expect(fixture.outputMatch?.computeUnits == "cpuOnly")
    #expect(fixture.outputMatch?.coremlOutputShape == [1, 15360])
    #expect((fixture.outputMatch?.maxAbsDiff ?? 1.0) < 0.0018)
}

@Test func `qwen3 tts speech tokenizer decoder core ml bucket 40 export converts and predicts`() throws {
    try assertBucketConversion(
        filename: "speech-tokenizer-decoder-coreml-conversion-bucket-40-12hz.json",
        bucket: 40,
        outputSamples: 76800,
    )
}

@Test func `qwen3 tts speech tokenizer decoder core ml bucket 40 fp16 export converts and predicts`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-bucket-40-fp16-12hz.json",
    )

    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.conversionTarget.computePrecision == "float16")
    #expect(fixture.conversionTarget.inputShape == [1, 40, 16])
    #expect(fixture.conversionTarget.torchOutputShape == [1, 76800])
    #expect(fixture.trace.status == "succeeded")
    #expect(fixture.conversion.status == "succeeded")
    #expect(fixture.outputMatch?.status == "succeeded")
    #expect(fixture.outputMatch?.coremlOutputShape == [1, 76800])
    #expect((fixture.outputMatch?.meanAbsDiff ?? 1.0) < 0.0005)
}

@Test func `qwen3 tts speech tokenizer decoder core ml bucket 72 export converts and predicts`() throws {
    try assertBucketConversion(
        filename: "speech-tokenizer-decoder-coreml-conversion-bucket-72-12hz.json",
        bucket: 72,
        outputSamples: 138_240,
    )
}

@Test func `qwen3 tts speech tokenizer decoder core ml bucket 72 fp16 export converts and predicts`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(
        "speech-tokenizer-decoder-coreml-conversion-bucket-72-fp16-12hz.json",
    )

    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.conversionTarget.computePrecision == "float16")
    #expect(fixture.conversionTarget.inputShape == [1, 72, 16])
    #expect(fixture.conversionTarget.torchOutputShape == [1, 138_240])
    #expect(fixture.trace.status == "succeeded")
    #expect(fixture.conversion.status == "succeeded")
    #expect(fixture.outputMatch?.status == "succeeded")
    #expect(fixture.outputMatch?.coremlOutputShape == [1, 138_240])
    #expect((fixture.outputMatch?.meanAbsDiff ?? 1.0) < 0.0005)
    #expect((fixture.outputMatch?.maxAbsDiff ?? 1.0) < 0.049)
}

@Test func `qwen3 tts speech tokenizer decoder core ml bucket 88 export converts and predicts`() throws {
    try assertBucketConversion(
        filename: "speech-tokenizer-decoder-coreml-conversion-bucket-88-12hz.json",
        bucket: 88,
        outputSamples: 168_960,
    )
}

private func assertBucketConversion(filename: String, bucket: Int, outputSamples: Int) throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load(filename)
    #expect(fixture.source.coremltoolsVersion == "9.0")
    #expect(fixture.source.torchVersion == "2.7.0")
    #expect(fixture.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.conversionTarget.inputShape == [1, bucket, 16])
    #expect(fixture.conversionTarget.torchOutputShape == [1, outputSamples])
    #expect(fixture.trace.status == "succeeded")
    #expect(fixture.conversion.status == "succeeded")
    #expect(fixture.outputMatch?.status == "succeeded")
    #expect(fixture.outputMatch?.coremlOutputShape == [1, outputSamples])
    #expect((fixture.outputMatch?.maxAbsDiff ?? 1.0) < 0.0003)
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLPreflightFixture: Decodable {
    struct ConversionTarget: Decodable {
        struct Padding: Decodable {
            let originalCodeSteps: Int
            let requestedCodeSteps: Int
            let paddedStepCount: Int
            let samplesPerCodeStep: Int?
        }

        let stage: String
        let inputName: String
        let inputShape: [Int]
        let inputDtype: String
        let expectedOutputShape: [Int]
        let expectedOutputSampleRate: Int
        let convertTo: String
        let padding: Padding
    }

    let schemaVersion: Int
    let mode: String
    let conversionTarget: ConversionTarget
    let nextCommand: String

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-preflight-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture: Decodable {
    struct Source: Decodable {
        let coremltoolsVersion: String
        let torchVersion: String
    }

    struct ConversionTarget: Decodable {
        let wrapperMode: String?
        let inputShape: [Int]
        let torchOutputShape: [Int]
        let captureMode: String?
        let computePrecision: String?
        let exportDecomposed: Bool?
        let upstreamMaxAbsDiff: Double?
    }

    struct Trace: Decodable {
        let status: String
        let captureMode: String?
        let strict: Bool
        let exportDecomposed: Bool?
        let errorType: String?
        let errorMessage: String?
    }

    struct Conversion: Decodable {
        let status: String
    }

    struct OutputMatch: Decodable {
        let status: String
        let computeUnits: String
        let coremlOutputShape: [Int]?
        let maxAbsDiff: Double?
        let meanAbsDiff: Double?
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let conversionTarget: ConversionTarget
    let trace: Trace
    let conversion: Conversion
    let outputMatch: OutputMatch?

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
