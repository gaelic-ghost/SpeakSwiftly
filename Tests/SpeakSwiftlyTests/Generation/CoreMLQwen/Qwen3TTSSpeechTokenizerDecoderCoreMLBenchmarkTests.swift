import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder core ml benchmark records all compute unit results`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLBenchmarkFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreml_benchmark")
    #expect(fixture.source.conversionTarget.wrapperMode == "fixed_16q_static_mask")
    #expect(fixture.source.conversionTarget.captureMode == "export")
    #expect(fixture.source.conversionTarget.exportDecomposed == true)
    #expect(fixture.benchmark.inputShape == [1, 8, 16])
    #expect(fixture.benchmark.inputDtype == "int32")
    #expect(fixture.benchmark.warmupRuns == 3)
    #expect(fixture.benchmark.measuredRuns == 10)
    #expect(fixture.benchmark.computeUnitsOrder == ["cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine", "all"])
    #expect(fixture.benchmark.results.count == 4)
    #expect(fixture.benchmark.results.allSatisfy { $0.status == "succeeded" })
    #expect(fixture.benchmark.results.allSatisfy { $0.outputShape == [1, 15360] })
}

@Test func `qwen3 tts speech tokenizer decoder core ml benchmark keeps outputs close across compute units`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLBenchmarkFixture.load()

    for result in fixture.benchmark.results where result.computeUnits != "cpuOnly" {
        #expect((result.baselineDelta?.maxAbsDiff ?? 1.0) < 0.000001)
    }
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLBenchmarkFixture: Decodable {
    struct Source: Decodable {
        struct ConversionTarget: Decodable {
            let wrapperMode: String
            let captureMode: String
            let exportDecomposed: Bool
        }

        let conversionTarget: ConversionTarget
    }

    struct Benchmark: Decodable {
        struct Result: Decodable {
            struct BaselineDelta: Decodable {
                let maxAbsDiff: Double
            }

            let status: String
            let computeUnits: String
            let outputShape: [Int]?
            let baselineDelta: BaselineDelta?
        }

        let inputShape: [Int]
        let inputDtype: String
        let warmupRuns: Int
        let measuredRuns: Int
        let computeUnitsOrder: [String]
        let results: [Result]
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let benchmark: Benchmark

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/speech-tokenizer-decoder-coreml-benchmark-static-mask-12hz.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
