import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder resident probe records padded talker decode`() throws {
    try assertResidentProbe(
        filename: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.bucket72Filename,
        sampleId: "prompt-001",
        audioCodesShape: [67, 16],
        paddedInputShape: [1, 72, 16],
        paddedStepCount: 5,
        validOutputSampleCount: 128_640,
        paddedOutputSampleCount: 138_240,
        paddedTailSampleCount: 9600,
    )
    try assertResidentProbe(
        filename: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.bucket88Filename,
        sampleId: "prompt-002",
        audioCodesShape: [84, 16],
        paddedInputShape: [1, 88, 16],
        paddedStepCount: 4,
        validOutputSampleCount: 161_280,
        paddedOutputSampleCount: 168_960,
        paddedTailSampleCount: 7680,
    )
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

    static let bucket72Filename =
        "speech-tokenizer-decoder-coreml-resident-probe-bucket-72-w8a8-linear-matmul-prompt-001-12hz.json"
    static let bucket88Filename =
        "speech-tokenizer-decoder-coreml-resident-probe-bucket-88-w8a8-linear-matmul-prompt-002-12hz.json"

    let schemaVersion: Int
    let toolName: String
    let source: Source
    let sample: Sample
    let prediction: Prediction

    static func load(
        _ filename: String = bucket72Filename,
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

private func assertResidentProbe(
    filename: String,
    sampleId: String,
    audioCodesShape: [Int],
    paddedInputShape: [Int],
    paddedStepCount: Int,
    validOutputSampleCount: Int,
    paddedOutputSampleCount: Int,
    paddedTailSampleCount: Int,
) throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.load(filename)

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.toolName == "coreml-qwen-decoder")
    #expect(fixture.source.computeUnits == "all")
    #expect(fixture.source.sampleId == sampleId)
    #expect(fixture.sample.audioCodesShape == audioCodesShape)
    #expect(fixture.sample.paddedInputShape == paddedInputShape)
    #expect(fixture.sample.paddedStepCount == paddedStepCount)
    #expect(fixture.sample.padValue == -1)
    #expect(fixture.sample.validOutputSampleCount == validOutputSampleCount)
    #expect(fixture.sample.paddedOutputSampleCount == paddedOutputSampleCount)
    #expect(fixture.prediction.warmupRuns == 1)
    #expect(fixture.prediction.measuredRuns == 2)
    #expect(fixture.prediction.outputShape == [1, paddedOutputSampleCount])
    #expect(fixture.prediction.validOutput.sampleCount == validOutputSampleCount)
    #expect(fixture.prediction.paddedTail?.sampleCount == paddedTailSampleCount)
}
