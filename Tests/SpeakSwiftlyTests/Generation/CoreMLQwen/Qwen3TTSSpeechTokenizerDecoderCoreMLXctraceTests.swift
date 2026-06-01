import Foundation
import Testing

@Test func `qwen3 tts speech tokenizer decoder core ml xctrace profile records compute unit traces`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLXctraceFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreml_xctrace_profile")
    #expect(fixture.source.template == "Core ML")
    #expect(fixture.profile.warmupRuns == 2)
    #expect(fixture.profile.measuredRuns == 20)
    #expect(fixture.profile.computeUnitsOrder == ["cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine", "all"])
    #expect(fixture.profile.results.count == 4)
    #expect(fixture.profile.results.allSatisfy { $0.status == "succeeded" })
}

@Test func `qwen3 tts speech tokenizer decoder core ml xctrace profile shows gpu path for gpu capable settings`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLXctraceFixture.load()

    let cpuOnly = try #require(fixture.result(for: "cpuOnly"))
    let cpuAndGPU = try #require(fixture.result(for: "cpuAndGPU"))
    let cpuAndNeuralEngine = try #require(fixture.result(for: "cpuAndNeuralEngine"))
    let all = try #require(fixture.result(for: "all"))

    #expect(cpuOnly.table("mps-hw-intervals")?.rowCount == 0)
    #expect(cpuAndNeuralEngine.table("mps-hw-intervals")?.rowCount == 0)
    #expect((cpuAndGPU.table("mps-hw-intervals")?.rowCount ?? 0) > 0)
    #expect((all.table("mps-hw-intervals")?.rowCount ?? 0) > 0)
    #expect(cpuAndGPU.table("mps-hw-intervals")?.labels.contains("MPSGraph") == true)
    #expect(all.table("mps-hw-intervals")?.labels.contains("MPSGraph") == true)
}

@Test func `qwen3 tts speech tokenizer decoder core ml xctrace profile shows no ane interval rows`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLXctraceFixture.load()

    for result in fixture.profile.results {
        #expect(result.table("ane-hw-intervals-internal")?.rowCount == 0)
    }
}

@Test func `qwen3 tts speech tokenizer decoder w8a8 xctrace profile shows ane intervals`() throws {
    let fixture = try Qwen3TTSSpeechTokenizerDecoderCoreMLXctraceFixture.load(
        "speech-tokenizer-decoder-coreml-xctrace-bucket-72-w8a8-linear-matmul-prompt-001-12hz.json",
    )

    #expect(fixture.mode == "coreml_xctrace_profile")
    #expect(fixture.profile.warmupRuns == 1)
    #expect(fixture.profile.measuredRuns == 5)
    #expect(fixture.profile.computeUnitsOrder == ["cpuOnly", "cpuAndNeuralEngine", "all"])

    let cpuOnly = try #require(fixture.result(for: "cpuOnly"))
    let cpuAndNeuralEngine = try #require(fixture.result(for: "cpuAndNeuralEngine"))
    let all = try #require(fixture.result(for: "all"))

    #expect(cpuOnly.table("ane-hw-intervals-internal")?.rowCount == 0)
    #expect((cpuAndNeuralEngine.table("ane-hw-intervals-internal")?.rowCount ?? 0) > 0)
    #expect((all.table("ane-hw-intervals-internal")?.rowCount ?? 0) > 0)
    #expect((all.table("mps-hw-intervals")?.rowCount ?? 0) > 0)
    #expect(cpuAndNeuralEngine.table("ane-hw-intervals-internal")?.labels.contains("Apple Neural Engine") == true)
    #expect(all.table("ane-hw-intervals-internal")?.labels.contains("Apple Neural Engine") == true)
    let cpuOnlyMean = try #require(cpuOnly.benchmarkResult?.measured.meanMs)
    let cpuAndNeuralEngineMean = try #require(cpuAndNeuralEngine.benchmarkResult?.measured.meanMs)
    let allMean = try #require(all.benchmarkResult?.measured.meanMs)
    #expect(cpuAndNeuralEngineMean < cpuOnlyMean)
    #expect(allMean < cpuAndNeuralEngineMean)
}

private struct Qwen3TTSSpeechTokenizerDecoderCoreMLXctraceFixture: Decodable {
    struct Source: Decodable {
        let template: String
    }

    struct Profile: Decodable {
        struct Result: Decodable {
            struct TraceTable: Decodable {
                let schema: String
                let status: String
                let rowCount: Int
                let labels: [String]
            }

            struct BenchmarkResult: Decodable {
                struct Measured: Decodable {
                    let meanMs: Double
                }

                let measured: Measured
            }

            let status: String
            let computeUnits: String
            let benchmarkResult: BenchmarkResult?
            let traceTables: [TraceTable]

            func table(_ schema: String) -> TraceTable? {
                traceTables.first { $0.schema == schema }
            }
        }

        let warmupRuns: Int
        let measuredRuns: Int
        let computeUnitsOrder: [String]
        let results: [Result]
    }

    let schemaVersion: Int
    let mode: String
    let source: Source
    let profile: Profile

    static func load(_ filename: String = "speech-tokenizer-decoder-coreml-xctrace-static-mask-12hz.json") throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/maintainers/coreml-qwen3tts/\(filename)",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }

    func result(for computeUnits: String) -> Profile.Result? {
        profile.results.first { $0.computeUnits == computeUnits }
    }
}
