import Foundation
import Testing

@Test func `qwen3 tts calibration code fixture pins libritts r provenance`() throws {
    let fixture = try Qwen3TTSCalibrationCodeFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-05-31T00:00:00Z")
    #expect(fixture.mode == "runtime")
    #expect(fixture.source.dataset == "mythicinfinity/libritts_r")
    #expect(fixture.source.datasetConfig == "clean")
    #expect(fixture.source.datasetSplit == "train.clean.100")
    #expect(fixture.source.datasetHubUrl == "https://hf.co/datasets/mythicinfinity/libritts_r")
    #expect(fixture.source.rowOffset == 0)
    #expect(fixture.source.requestedSampleCount == 3)
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-Tokenizer-12Hz")
    #expect(fixture.source.resolvedRevision == "7dd38ad4e9bad454aae9cd937d0cd577604fe229")
    #expect(fixture.source.qwenSourceCommit == "022e286b98fbec7e1e916cb940cdf532cd9f488e")
}

@Test func `qwen3 tts calibration code fixture summarizes decoder calibration shape`() throws {
    let fixture = try Qwen3TTSCalibrationCodeFixture.load()

    #expect(fixture.calibrationScope.currentGraph == "12 Hz speech-tokenizer decoder only")
    #expect(fixture.calibrationScope.currentInput == "audio_codes shaped batch x code_steps x 16 codebooks")
    #expect(fixture.aggregate.sampleCount == 3)
    #expect(fixture.aggregate.totalCodeSteps == 185)
    #expect(fixture.aggregate.minCodeSteps == 37)
    #expect(fixture.aggregate.maxCodeSteps == 83)
    #expect(fixture.aggregate.medianCodeSteps == 65)
    #expect(fixture.aggregate.quantizerCount == 16)
    #expect(fixture.aggregate.suggestedDecoderBuckets == [40, 72, 88])
}

@Test func `qwen3 tts calibration code fixture pins sample code tensors`() throws {
    let fixture = try Qwen3TTSCalibrationCodeFixture.load()

    #expect(fixture.samples.count == 3)
    let first = try #require(fixture.samples.first)
    #expect(first.rowIdx == 0)
    #expect(first.id == "730_358_000003_000002")
    #expect(first.speakerId == "730")
    #expect(first.textNormalized == "[The moon] I gazed with a kind of wonder.")
    #expect(first.audio.sampleRate == 24000)
    #expect(first.audio.sampleCount == 70080)
    #expect(first.audio.durationSeconds == 2.92)
    #expect(first.audio.source == "hugging_face_dataset_viewer_transient_audio_asset")
    #expect(first.encoded.audioCodesShape == [37, 16])
    #expect(first.encoded.audioCodes.count == 37)
    #expect(first.encoded.audioCodes.allSatisfy { $0.count == 16 })
    #expect(first.encoded.audioCodesMin == 1)
    #expect(first.encoded.audioCodesMax == 2046)
    #expect(first.encoded.audioCodesFirstQuantizerPrefix.prefix(8) == [1995, 1028, 397, 1668, 1668, 271, 313, 313])
    #expect(first.encoded.audioCodesPrefix.first == [1995, 1105, 1661, 832, 1449, 1762, 138, 444])
}

private struct Qwen3TTSCalibrationCodeFixture: Decodable {
    struct Source: Decodable {
        let dataset: String
        let datasetConfig: String
        let datasetSplit: String
        let datasetHubUrl: String
        let rowOffset: Int
        let requestedSampleCount: Int
        let modelId: String
        let resolvedRevision: String
        let qwenSourceCommit: String
    }

    struct CalibrationScope: Decodable {
        let currentGraph: String
        let currentInput: String
    }

    struct Aggregate: Decodable {
        let sampleCount: Int
        let totalCodeSteps: Int
        let minCodeSteps: Int
        let maxCodeSteps: Int
        let medianCodeSteps: Int
        let quantizerCount: Int
        let suggestedDecoderBuckets: [Int]
    }

    struct Sample: Decodable {
        struct Audio: Decodable {
            let sampleRate: Int
            let sampleCount: Int
            let durationSeconds: Double
            let source: String
        }

        struct Encoded: Decodable {
            let audioCodesShape: [Int]
            let audioCodesMin: Int
            let audioCodesMax: Int
            let audioCodes: [[Int]]
            let audioCodesPrefix: [[Int]]
            let audioCodesFirstQuantizerPrefix: [Int]
        }

        let rowIdx: Int
        let id: String
        let speakerId: String
        let textNormalized: String
        let audio: Audio
        let encoded: Encoded
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let mode: String
    let source: Source
    let calibrationScope: CalibrationScope
    let aggregate: Aggregate
    let samples: [Sample]

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/calibration-code-fixture-libritts-r-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
