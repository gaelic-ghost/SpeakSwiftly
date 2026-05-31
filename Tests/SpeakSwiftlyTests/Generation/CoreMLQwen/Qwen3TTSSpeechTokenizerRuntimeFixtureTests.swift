import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer runtime fixture pins encoded code shape`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerRuntimeFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-05-31T00:00:00Z")
    #expect(fixture.mode == "runtime")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-Tokenizer-12Hz")
    #expect(fixture.source.resolvedRevision == "7dd38ad4e9bad454aae9cd937d0cd577604fe229")
    #expect(fixture.source.qwenSourceCommit == "022e286b98fbec7e1e916cb940cdf532cd9f488e")

    #expect(fixture.encoded.audioCodesShape == [8, 16])
    #expect(fixture.encoded.audioCodesDtype == "int64")
    #expect(fixture.encoded.audioCodesFirstQuantizerPrefix == [1221, 215, 1521, 1095, 1985, 1985, 1985, 687])
    #expect(fixture.encoded.audioCodesPrefix.first == [1221, 910, 262, 956, 1881, 645, 1588, 1653])
}

@Test func `qwen3 tts speech tokenizer runtime fixture pins decoded waveform shape`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerRuntimeFixture.load()

    #expect(fixture.syntheticAudio.sampleRate == 24000)
    #expect(fixture.syntheticAudio.sampleCount == 15360)
    #expect(fixture.decoded.sampleRate == 24000)
    #expect(fixture.decoded.sampleCount == 15360)
    #expect(fixture.decoded.durationSeconds == 0.64)
    #expect(fixture.decoded.rms > 0.032)
    #expect(fixture.decoded.rms < 0.034)
}

private struct Qwen3TTSSpeechTokenizerRuntimeFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
        let resolvedRevision: String
        let qwenSourceCommit: String
    }

    struct SyntheticAudio: Decodable {
        let sampleRate: Int
        let sampleCount: Int
    }

    struct Encoded: Decodable {
        let audioCodesShape: [Int]
        let audioCodesDtype: String
        let audioCodesPrefix: [[Int]]
        let audioCodesFirstQuantizerPrefix: [Int]
    }

    struct Decoded: Decodable {
        let sampleRate: Int
        let sampleCount: Int
        let durationSeconds: Double
        let rms: Double
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let mode: String
    let source: Source
    let syntheticAudio: SyntheticAudio
    let encoded: Encoded
    let decoded: Decoded

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-runtime-fixture-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
