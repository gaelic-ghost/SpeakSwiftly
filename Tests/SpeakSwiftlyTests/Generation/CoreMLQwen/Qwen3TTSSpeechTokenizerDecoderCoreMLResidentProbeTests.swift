import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder resident probe records padded talker decode`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.toolName == "coreml-qwen-decoder")
    #expect(fixture.source.computeUnits == "all")
    #expect(fixture.source.sampleId == "prompt-001")
    #expect(fixture.sample.audioCodesShape == [67, 16])
    #expect(fixture.sample.paddedInputShape == [1, 72, 16])
    #expect(fixture.sample.paddedStepCount == 5)
    #expect(fixture.sample.padValue == -1)
    #expect(fixture.sample.validOutputSampleCount == 128_640)
    #expect(fixture.sample.paddedOutputSampleCount == 138_240)
    #expect(fixture.prediction.warmupRuns == 1)
    #expect(fixture.prediction.measuredRuns == 2)
    #expect(fixture.prediction.outputShape == [1, 138_240])
    #expect(fixture.prediction.validOutput.sampleCount == 128_640)
    #expect(fixture.prediction.paddedTail?.sampleCount == 9600)
}

@Test func `qwen3 tts speech tokenizer decoder resident probe records hot prediction timing`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.load()

    #expect((fixture.prediction.compileDurationMs ?? 0) > 0)
    #expect(fixture.prediction.loadDurationMs > 0)
    #expect(fixture.prediction.measured.meanMs > 0)
    #expect(fixture.prediction.measured.maxMs >= fixture.prediction.measured.minMs)
    #expect(fixture.prediction.measured.p95Ms >= fixture.prediction.measured.minMs)
    #expect((fixture.prediction.warmup?.meanMs ?? 0) > fixture.prediction.measured.meanMs)
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture: Decodable {
    struct Source: Decodable {
        let computeUnits: String
        let sampleId: String
    }

    struct Sample: Decodable {
        let audioCodesShape: [Int]
        let paddedInputShape: [Int]
        let paddedStepCount: Int
        let padValue: Int
        let validOutputSampleCount: Int
        let paddedOutputSampleCount: Int
    }

    struct Prediction: Decodable {
        struct TimingStats: Decodable {
            let minMs: Double
            let meanMs: Double
            let p95Ms: Double
            let maxMs: Double
        }

        struct AudioSummary: Decodable {
            let sampleCount: Int
        }

        let compileDurationMs: Double?
        let loadDurationMs: Double
        let warmupRuns: Int
        let measuredRuns: Int
        let warmup: TimingStats?
        let measured: TimingStats
        let outputShape: [Int]
        let validOutput: AudioSummary
        let paddedTail: AudioSummary?
    }

    static let defaultFilename =
        "speech-tokenizer-decoder-coreml-resident-probe-bucket-72-w8a8-linear-matmul-prompt-001-12hz.json"

    let schemaVersion: Int
    let toolName: String
    let source: Source
    let sample: Sample
    let prediction: Prediction

    static func load(
        _ filename: String = defaultFilename,
    ) throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/\(filename)",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
