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
}

@Test func `qwen3 tts speech tokenizer decoder core ml conversion records trace blocker`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLConversionFixture.load()

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
        let inputShape: [Int]
        let torchOutputShape: [Int]
    }

    struct Trace: Decodable {
        let status: String
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

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-conversion-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
