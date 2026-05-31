import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder bucket plan assigns calibration samples`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLBucketPlanFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreml_decoder_bucket_plan")
    #expect(fixture.bucketPlan.stage == "speech_tokenizer_decoder")
    #expect(fixture.bucketPlan.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.bucketPlan.inputName == "audio_codes")
    #expect(fixture.bucketPlan.inputDtype == "int64")
    #expect(fixture.bucketPlan.quantizerCount == 16)
    #expect(fixture.bucketPlan.samplesPerCodeStep == 1920)
    #expect(fixture.bucketPlan.buckets == [40, 72, 88])
    #expect(fixture.bucketPlan.requiredInputShapes == [[1, 40, 16], [1, 72, 16], [1, 88, 16]])
    #expect(fixture.bucketPlan.sampleAssignments.map(\.assignedBucket).sorted() == [40, 72, 88])
}

@Test func `qwen3 tts speech tokenizer decoder bucket plan records conversion commands`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLBucketPlanFixture.load()

    #expect(fixture.conversionCommands.count == 3)
    #expect(fixture.conversionCommands.map(\.bucket) == [40, 72, 88])
    #expect(fixture.conversionCommands.allSatisfy { $0.command.contains("--pad-code-steps \($0.bucket)") })
    #expect(fixture.conversionCommands.allSatisfy { $0.command.contains("--wrapper-mode fixed_16q_static_mask") })
    #expect(fixture.conversionCommands.allSatisfy { $0.mlpackageOutput.contains("bucket-\($0.bucket)") })
    #expect(fixture.w8a8FollowUp.blockedUntil == "bucketed_decoder_mlpackages_exist")
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLBucketPlanFixture: Decodable {
    struct BucketPlan: Decodable {
        struct SampleAssignment: Decodable {
            let assignedBucket: Int
        }

        let stage: String
        let wrapperMode: String
        let inputName: String
        let inputDtype: String
        let quantizerCount: Int
        let samplesPerCodeStep: Int
        let buckets: [Int]
        let requiredInputShapes: [[Int]]
        let sampleAssignments: [SampleAssignment]
    }

    struct ConversionCommand: Decodable {
        let bucket: Int
        let mlpackageOutput: String
        let command: String
    }

    struct W8A8FollowUp: Decodable {
        let blockedUntil: String
    }

    let schemaVersion: Int
    let mode: String
    let bucketPlan: BucketPlan
    let conversionCommands: [ConversionCommand]
    let w8a8FollowUp: W8A8FollowUp

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-bucket-plan-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
