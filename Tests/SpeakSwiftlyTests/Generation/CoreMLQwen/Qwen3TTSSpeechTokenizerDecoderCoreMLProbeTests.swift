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
    #expect(fixture.nextCommand.contains("--python 3.12"))
    #expect(fixture.nextCommand.contains("--with 'coremltools>=8.3.0,<10'"))
    #expect(fixture.nextCommand.contains("--with 'torch==2.7.0'"))
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
    #expect(nonStrictFixture.trace.errorMessage.contains("is_contiguous inside of vmap"))

    #expect(strictFixture.conversionTarget.wrapperMode == "fixed_16q")
    #expect(strictFixture.conversionTarget.captureMode == "export")
    #expect(strictFixture.conversionTarget.upstreamMaxAbsDiff == 0.0)
    #expect(strictFixture.trace.status == "failed")
    #expect(strictFixture.trace.strict == true)
    #expect(strictFixture.trace.errorType == "TorchRuntimeError")
    #expect(strictFixture.trace.errorMessage.contains("calling .item() on a Tensor"))
    #expect(strictFixture.trace.errorMessage.contains("<local-home-path>"))
    #expect(strictFixture.conversion.status == "not_started")
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLPreflightFixture: Decodable {
    struct ConversionTarget: Decodable {
        let stage: String
        let inputName: String
        let inputShape: [Int]
        let inputDtype: String
        let expectedOutputShape: [Int]
        let expectedOutputSampleRate: Int
        let convertTo: String
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
        let upstreamMaxAbsDiff: Double?
    }

    struct Trace: Decodable {
        let status: String
        let captureMode: String?
        let strict: Bool
        let errorType: String
        let errorMessage: String
    }

    struct Conversion: Decodable {
        let status: String
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let conversionTarget: ConversionTarget
    let trace: Trace
    let conversion: Conversion

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
