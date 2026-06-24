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
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.load(
        Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.w8a8Filename,
    )

    try assertResidentCatalogFixture(fixture, expectedModelPackageFragment: "linear-matmul")
}

@Test func `qwen3 tts speech tokenizer decoder fp16 resident catalog routes selected buckets`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.load(
        Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.fp16Filename,
    )

    try assertResidentCatalogFixture(fixture, expectedModelPackageFragment: "bucket-72-fp16")
    #expect(fixture.source.bucketModels[1].modelPackage.contains("bucket-88-fp16"))
}

@Test func `qwen3 tts decoder closeout manifests listening artifacts`() throws {
    let manifest = try Qwen3TTSDecoderCloseoutListeningManifest.load()

    #expect(manifest.schemaVersion == 1)
    #expect(manifest.status == "macbook_pro_speaker_listening_acceptable_followup_optional")
    #expect(manifest.listenInOrder.map(\.sampleId) == ["prompt-001", "prompt-002"])
    #expect(manifest.listenInOrder.map(\.bucket) == [72, 88])
    #expect(manifest.listenInOrder.allSatisfy { $0.validDurationSeconds > 0 })
    #expect(manifest.listenInOrder.allSatisfy { $0.baselineValidWav.hasPrefix(".local/coreml-qwen3tts/") })
    #expect(manifest.listenInOrder.allSatisfy { $0.candidateValidWav.hasPrefix(".local/coreml-qwen3tts/") })
    #expect(manifest.listenInOrder.allSatisfy { $0.audioInspectionReport.hasPrefix("docs/maintainers/") })
    #expect(manifest.listenInOrder[0].macbookProSpeakerListeningResult == "acceptable")
    #expect(manifest.listenInOrder[1].macbookProSpeakerListeningResult == "acceptable_with_muffled_quality")
}

@Test func `qwen3 tts decoder closeout compares fp16 and w8a8 residency`() throws {
    let report = try Qwen3TTSDecoderCloseoutComparisonReport.load()

    #expect(report.schemaVersion == 1)
    #expect(report.status == "decoder_listening_acceptable_backend_gate_pending")
    #expect(report.packages.map(\.bucket) == [72, 88])
    #expect(report.packages.allSatisfy { $0.w8a8LinearMatmulPackageSizeBytes < $0.fp16PackageSizeBytes })
    #expect(report.residentCatalogComparison.map(\.sampleId) == ["prompt-001", "prompt-002"])
    #expect(report.residentCatalogComparison.allSatisfy { $0.fp16Pass2MeasuredMeanMs > 0 })
    #expect(report.residentCatalogComparison.allSatisfy { $0.w8a8Pass2MeasuredMeanMs > 0 })
    #expect(report.residentCatalogComparison.allSatisfy { $0.validOutputMeanAbsDiff > 0 })
    #expect(report.processResidency.fp16FinalRssBytes > 0)
    #expect(report.processResidency.w8a8FinalRssBytes > 0)
    #expect(report.decision.publicBackend.contains("Do not add"))
}

private func assertResidentCatalogFixture(
    _ fixture: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture,
    expectedModelPackageFragment: String,
) throws {
    #expect(fixture.schemaVersion == 1)
    #expect(fixture.toolName == "coreml-qwen-decoder")
    #expect(fixture.mode == "resident_bucket_catalog")
    #expect(fixture.source.computeUnits == "all")
    #expect(fixture.source.catalogPasses == 2)
    #expect(fixture.source.sampleIds == ["prompt-001", "prompt-002"])
    #expect(fixture.source.bucketModels.map(\.bucket) == [72, 88])
    #expect(fixture.source.bucketModels[0].modelPackage.contains(expectedModelPackageFragment))
    #expect(fixture.buckets.map(\.bucket) == [72, 88])
    #expect(fixture.buckets.allSatisfy { $0.compileDurationMs ?? 0 > 0 })
    #expect(fixture.buckets.allSatisfy { $0.loadDurationMs > 0 })
    #expect(fixture.memorySnapshots.map(\.label) == [
        "start",
        "after_load_bucket_72",
        "after_load_bucket_88",
        "after_prediction_pass_1_prompt-001",
        "after_prediction_pass_1_prompt-002",
        "after_prediction_pass_2_prompt-001",
        "after_prediction_pass_2_prompt-002",
        "end",
    ])
    #expect(fixture.memorySnapshots.allSatisfy { ($0.residentSizeBytes ?? 0) > 0 })
    #expect(fixture.predictions.count == 4)

    try assertResidentCatalogPrediction(
        fixture.predictionForSample(id: "prompt-001", passIndex: 1),
        passIndex: 1,
        selectedBucket: 72,
        audioCodesShape: [67, 16],
        paddedInputShape: [1, 72, 16],
        validOutputSampleCount: 128_640,
        paddedOutputSampleCount: 138_240,
        paddedTailSampleCount: 9600,
    )
    try assertResidentCatalogPrediction(
        fixture.predictionForSample(id: "prompt-002", passIndex: 1),
        passIndex: 1,
        selectedBucket: 88,
        audioCodesShape: [84, 16],
        paddedInputShape: [1, 88, 16],
        validOutputSampleCount: 161_280,
        paddedOutputSampleCount: 168_960,
        paddedTailSampleCount: 7680,
    )
    try assertResidentCatalogPrediction(
        fixture.predictionForSample(id: "prompt-001", passIndex: 2),
        passIndex: 2,
        selectedBucket: 72,
        audioCodesShape: [67, 16],
        paddedInputShape: [1, 72, 16],
        validOutputSampleCount: 128_640,
        paddedOutputSampleCount: 138_240,
        paddedTailSampleCount: 9600,
    )
    try assertResidentCatalogPrediction(
        fixture.predictionForSample(id: "prompt-002", passIndex: 2),
        passIndex: 2,
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
            let modelPackage: String
        }

        let computeUnits: String
        let catalogPasses: Int
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
        let passIndex: Int
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

    static let w8a8Filename =
        "speech-tokenizer-decoder-coreml-resident-catalog-buckets-72-88-w8a8-linear-matmul-prompts-001-002-12hz.json"
    static let fp16Filename =
        "speech-tokenizer-decoder-coreml-resident-catalog-buckets-72-88-fp16-prompts-001-002-12hz.json"

    let schemaVersion: Int
    let toolName: String
    let mode: String
    let source: Source
    let buckets: [Bucket]
    let memorySnapshots: [MemorySnapshot]
    let predictions: [Prediction]

    static func load(
        _ filename: String = w8a8Filename,
    ) throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/\(filename)",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }

    func predictionForSample(id: String, passIndex: Int) -> Prediction? {
        for prediction in predictions where prediction.sample.id == id && prediction.passIndex == passIndex {
            return prediction
        }
        return nil
    }
}

private struct Qwen3TTSDecoderCloseoutListeningManifest: Decodable {
    struct ListeningItem: Decodable {
        let sampleId: String
        let bucket: Int
        let validDurationSeconds: Double
        let baselineValidWav: String
        let candidateValidWav: String
        let audioInspectionReport: String
        let macbookProSpeakerListeningResult: String
    }

    let schemaVersion: Int
    let status: String
    let listenInOrder: [ListeningItem]

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/decoder-closeout-listening-manifest-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private struct Qwen3TTSDecoderCloseoutComparisonReport: Decodable {
    struct Package: Decodable {
        let bucket: Int
        let fp16PackageSizeBytes: Int
        let w8a8LinearMatmulPackageSizeBytes: Int
    }

    struct Comparison: Decodable {
        let sampleId: String
        let fp16Pass2MeasuredMeanMs: Double
        let w8a8Pass2MeasuredMeanMs: Double
        let validOutputMeanAbsDiff: Double
    }

    struct ProcessResidency: Decodable {
        let fp16FinalRssBytes: UInt64
        let w8a8FinalRssBytes: UInt64
    }

    struct Decision: Decodable {
        let publicBackend: String
    }

    let schemaVersion: Int
    let status: String
    let packages: [Package]
    let residentCatalogComparison: [Comparison]
    let processResidency: ProcessResidency
    let decision: Decision

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/decoder-closeout-fp16-vs-w8a8-resident-catalog-12hz.json",
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

private func assertResidentCatalogPrediction(
    _ prediction: Qwen3TTSSpeechTokenizerDecoderCoreMLResidentCatalogFixture.Prediction?,
    passIndex: Int,
    selectedBucket: Int,
    audioCodesShape: [Int],
    paddedInputShape: [Int],
    validOutputSampleCount: Int,
    paddedOutputSampleCount: Int,
    paddedTailSampleCount: Int,
) throws {
    let prediction = try #require(prediction)

    #expect(prediction.passIndex == passIndex)
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
