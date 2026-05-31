import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer runtime preflight pins download size`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerPreflightFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-05-31T00:00:00Z")
    #expect(fixture.mode == "preflight")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-Tokenizer-12Hz")
    #expect(fixture.source.resolvedRevision == "7dd38ad4e9bad454aae9cd937d0cd577604fe229")
    #expect(fixture.modelFileInventory.fileCount == 6)
    #expect(fixture.modelFileInventory.totalSizeBytes == 682_300_739)

    let largestFile = try #require(fixture.modelFileInventory.files.first)
    #expect(largestFile.path == "model.safetensors")
    #expect(largestFile.sizeBytes == 682_293_092)
}

@Test func `qwen3 tts speech tokenizer runtime preflight pins synthetic audio shape`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerPreflightFixture.load()

    #expect(fixture.syntheticAudio.sampleRate == 24000)
    #expect(fixture.syntheticAudio.durationSeconds == 0.64)
    #expect(fixture.syntheticAudio.frequencyHz == 220)
    #expect(fixture.syntheticAudio.sampleCount == 15360)
    #expect(fixture.syntheticAudio.expectedCodeStepsAt1920Samples == 8)
    #expect(fixture.nextCommand.contains("--allow-model-download"))
    #expect(fixture.nextCommand.contains("--no-preflight-only"))
    #expect(fixture.nextCommand.contains("--with 'torch>=2.6.0'"))
    #expect(fixture.nextCommand.contains("--output .local/coreml-qwen3tts/qwen3tts-speech-tokenizer-fixture.json"))
}

private struct Qwen3TTSSpeechTokenizerPreflightFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
        let resolvedRevision: String
    }

    struct ModelFileInventory: Decodable {
        struct File: Decodable {
            let path: String
            let sizeBytes: Int
        }

        let fileCount: Int
        let totalSizeBytes: Int
        let files: [File]
    }

    struct SyntheticAudio: Decodable {
        let sampleRate: Int
        let durationSeconds: Double
        let frequencyHz: Double
        let sampleCount: Int
        let expectedCodeStepsAt1920Samples: Int
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let mode: String
    let source: Source
    let modelFileInventory: ModelFileInventory
    let syntheticAudio: SyntheticAudio
    let nextCommand: String

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-runtime-preflight-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
