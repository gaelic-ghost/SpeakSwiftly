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

@Test func `qwen3 tts speech tokenizer decoder resident catalog routes selected buckets`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.toolName == "coreml-qwen-decoder")
    #expect(fixture.mode == "resident_bucket_catalog")
    #expect(fixture.source.computeUnits == "all")
    #expect(fixture.source.sampleIds == ["prompt-001", "prompt-002"])
    #expect(fixture.source.bucketModels.map(\.bucket) == [72, 88])
    #expect(fixture.buckets.map(\.bucket) == [72, 88])
    #expect(fixture.buckets.allSatisfy { $0.compileDurationMs ?? 0 > 0 })
    #expect(fixture.buckets.allSatisfy { $0.loadDurationMs > 0 })
    #expect(fixture.memorySnapshots.map(\.label) == [
        "start",
        "after_load_bucket_72",
        "after_load_bucket_88",
        "after_prediction_prompt-001",
        "after_prediction_prompt-002",
        "end",
    ])
    #expect(fixture.memorySnapshots.allSatisfy { ($0.residentSizeBytes ?? 0) > 0 })

    try assertResidentCatalogPrediction(
        fixture.predictionForSample(id: "prompt-001"),
        selectedBucket: 72,
        audioCodesShape: [67, 16],
        paddedInputShape: [1, 72, 16],
        validOutputSampleCount: 128_640,
        paddedOutputSampleCount: 138_240,
        paddedTailSampleCount: 9600,
    )
    try assertResidentCatalogPrediction(
        fixture.predictionForSample(id: "prompt-002"),
        selectedBucket: 88,
        audioCodesShape: [84, 16],
        paddedInputShape: [1, 88, 16],
        validOutputSampleCount: 161_280,
        paddedOutputSampleCount: 168_960,
        paddedTailSampleCount: 7680,
    )
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture: Decodable {
    struct Source: Decodable {
        let computeUnits: String
        let sampleId: String
    }

    struct Sample: Decodable {
        let id: String
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

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture: Decodable {
    struct Source: Decodable {
        struct BucketModel: Decodable {
            let bucket: Int
        }

        let computeUnits: String
        let sampleIds: [String]
        let bucketModels: [BucketModel]
    }

    struct Bucket: Decodable {
        let bucket: Int
        let compileDurationMs: Double?
        let loadDurationMs: Double
    }

    struct MemorySnapshot: Decodable {
        let label: String
        let residentSizeBytes: UInt64?
    }

    struct Prediction: Decodable {
        let sample: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.Sample
        let selectedBucket: Int
        let fixtureAssignedBucket: Int
        let warmupRuns: Int
        let measuredRuns: Int
        let measured: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.Prediction.TimingStats
        let outputShape: [Int]
        let validOutput: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.Prediction.AudioSummary
        let paddedTail: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentProbeFixture.Prediction.AudioSummary?
    }

    static let filename =
        "speech-tokenizer-decoder-coreml-resident-catalog-buckets-72-88-w8a8-linear-matmul-prompts-001-002-12hz.json"

    let schemaVersion: Int
    let toolName: String
    let mode: String
    let source: Source
    let buckets: [Bucket]
    let memorySnapshots: [MemorySnapshot]
    let predictions: [Prediction]

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/\(filename)",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }

    func predictionForSample(id: String) -> Prediction? {
        for prediction in predictions where prediction.sample.id == id {
            return prediction
        }
        return nil
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

private func assertResidentCatalogPrediction(
    _ prediction: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.Prediction?,
    selectedBucket: Int,
    audioCodesShape: [Int],
    paddedInputShape: [Int],
    validOutputSampleCount: Int,
    paddedOutputSampleCount: Int,
    paddedTailSampleCount: Int,
) throws {
    let prediction = try #require(prediction)

    #expect(prediction.selectedBucket == selectedBucket)
    #expect(prediction.fixtureAssignedBucket == selectedBucket)
    #expect(prediction.sample.audioCodesShape == audioCodesShape)
    #expect(prediction.sample.paddedInputShape == paddedInputShape)
    #expect(prediction.sample.validOutputSampleCount == validOutputSampleCount)
    #expect(prediction.sample.paddedOutputSampleCount == paddedOutputSampleCount)
    #expect(prediction.warmupRuns == 1)
    #expect(prediction.measuredRuns == 2)
    #expect(prediction.measured.meanMs > 0)
    #expect(prediction.measured.maxMs >= prediction.measured.minMs)
    #expect(prediction.measured.p95Ms >= prediction.measured.minMs)
    #expect(prediction.outputShape == [1, paddedOutputSampleCount])
    #expect(prediction.validOutput.sampleCount == validOutputSampleCount)
    #expect(prediction.paddedTail?.sampleCount == paddedTailSampleCount)
}
