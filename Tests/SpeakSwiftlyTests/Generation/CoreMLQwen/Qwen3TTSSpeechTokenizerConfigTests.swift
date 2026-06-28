import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer config fixture source is pinned`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerConfigFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-05-31T00:00:00Z")
    #expect(fixture.source.upstreamRepository == "https://github.com/QwenLM/Qwen3-TTS")
    #expect(fixture.source.upstreamCommit == "022e286b98fbec7e1e916cb940cdf532cd9f488e")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-Tokenizer-12Hz")
    #expect(fixture.source.resolvedRevision == "7dd38ad4e9bad454aae9cd937d0cd577604fe229")
}

@Test func `qwen3 tts speech tokenizer 12hz rates and codebook shape stay stable`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerConfigFixture.load()

    #expect(fixture.modelConfig.modelType == "qwen3_tts_tokenizer_12hz")
    #expect(fixture.modelConfig.inputSampleRate == 24000)
    #expect(fixture.modelConfig.outputSampleRate == 24000)
    #expect(fixture.modelConfig.encodeDownsampleRate == 1920)
    #expect(fixture.modelConfig.decodeUpsampleRate == 1920)
    #expect(fixture.modelConfig.encoderValidNumQuantizers == 16)

    #expect(fixture.featureExtractor.featureExtractorType == "EncodecFeatureExtractor")
    #expect(fixture.featureExtractor.samplingRate == 24000)
    #expect(fixture.featureExtractor.paddingValue == 0)
    #expect(fixture.featureExtractor.returnAttentionMask)

    #expect(fixture.encoderConfig.numQuantizers == 32)
    #expect(fixture.encoderConfig.codebookSize == 2048)
    #expect(fixture.encoderConfig.samplingRate == 24000)
}

@Test func `qwen3 tts speech tokenizer decoder shape stays stable`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerConfigFixture.load()

    #expect(fixture.decoderConfig.hiddenSize == 512)
    #expect(fixture.decoderConfig.numHiddenLayers == 8)
    #expect(fixture.decoderConfig.numAttentionHeads == 16)
    #expect(fixture.decoderConfig.numKeyValueHeads == 16)
    #expect(fixture.decoderConfig.latentDim == 1024)
    #expect(fixture.decoderConfig.decoderDim == 1536)
    #expect(fixture.decoderConfig.upsampleRates == [8, 5, 4, 3])
    #expect(fixture.decoderConfig.upsamplingRatios == [2, 2])
}

private struct Qwen3TTSSpeechTokenizerConfigFixture: Decodable {
    struct Source: Decodable {
        let upstreamRepository: String
        let upstreamCommit: String
        let modelId: String
        let resolvedRevision: String
    }

    struct ModelConfig: Decodable {
        let modelType: String
        let inputSampleRate: Int
        let outputSampleRate: Int
        let encodeDownsampleRate: Int
        let decodeUpsampleRate: Int
        let encoderValidNumQuantizers: Int
    }

    struct FeatureExtractor: Decodable {
        let featureExtractorType: String
        let samplingRate: Int
        let paddingValue: Double
        let returnAttentionMask: Bool
    }

    struct EncoderConfig: Decodable {
        let numQuantizers: Int
        let codebookSize: Int
        let samplingRate: Int
    }

    struct DecoderConfig: Decodable {
        let hiddenSize: Int
        let numHiddenLayers: Int
        let numAttentionHeads: Int
        let numKeyValueHeads: Int
        let latentDim: Int
        let decoderDim: Int
        let upsampleRates: [Int]
        let upsamplingRatios: [Int]
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let modelConfig: ModelConfig
    let featureExtractor: FeatureExtractor
    let encoderConfig: EncoderConfig
    let decoderConfig: DecoderConfig

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL("docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/speech-tokenizer-config-12hz.json")
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
