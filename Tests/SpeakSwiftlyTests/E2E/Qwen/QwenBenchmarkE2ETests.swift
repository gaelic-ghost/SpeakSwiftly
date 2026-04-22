#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

private let qwenBenchmarkSchemaVersion = 3

@Suite(
    .serialized,
    .tags(.e2e, .qwen, .benchmark),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
    .enabled(
        if: speakSwiftlyQwenBenchmarkE2ETestsEnabled(),
        "This Qwen resident benchmark suite is opt-in and requires SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1.",
    ),
)
struct QwenBenchmarkE2ETests {
    @Test func `compare qwen conditioning strategies`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        try await Self.provisionBenchmarkProfile(in: sandbox.profileRootURL)

        let iterations = speakSwiftlyQwenBenchmarkIterations()
        var samples = [QwenBenchmarkSample]()
        samples.reserveCapacity(iterations * 2)

        for strategy in [SpeakSwiftly.QwenConditioningStrategy.legacyRaw, .preparedConditioning] {
            for iteration in 1...iterations {
                try await samples.append(
                    Self.runBenchmarkSample(
                        profileRootURL: sandbox.profileRootURL,
                        strategy: strategy,
                        iteration: iteration,
                    ),
                )
            }
        }

        let summary = QwenBenchmarkSummary(
            schemaVersion: qwenBenchmarkSchemaVersion,
            generatedAt: Date(),
            host: .localMachine(),
            settings: .current(
                iterations: iterations,
                benchmarkProfileName: Self.benchmarkProfileName,
                playbackTextCharacterCount: E2EHarness.testingPlaybackText.count,
                playbackMode: BenchmarkHarness.effectivePlaybackMode(),
            ),
            strategies: QwenConditioningStrategyBenchmarkReport.make(from: samples),
        )
        let summaryURL = try BenchmarkHarness.writeSummary(
            summary,
            timestampedStem: "qwen-resident-benchmark",
            latestFilename: "qwen-resident-benchmark-latest.json",
            generatedAt: summary.generatedAt,
        )

        print("SpeakSwiftly qwen benchmark summary: \(summaryURL.path)")
        for strategy in summary.strategies {
            print(strategy.prettyDescription)
        }
    }
}

private extension QwenBenchmarkE2ETests {
    static let benchmarkProfileName = "benchmark-profile"

    static func provisionBenchmarkProfile(in profileRootURL: URL) async throws {
        try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: .qwen3,
            qwenConditioningStrategy: .preparedConditioning,
        ) { session in
            _ = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)

            let handle = await session.runtime.voices.create(
                design: benchmarkProfileName,
                from: E2EHarness.testingProfileText,
                vibe: .masc,
                voice: E2EHarness.testingProfileVoiceDescription,
            )
            _ = try await BenchmarkHarness.awaitSuccess(from: handle)
        }
    }

    static func runBenchmarkSample(
        profileRootURL: URL,
        strategy: SpeakSwiftly.QwenConditioningStrategy,
        iteration: Int,
    ) async throws -> QwenBenchmarkSample {
        try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: .qwen3,
            qwenConditioningStrategy: strategy,
            playbackMode: BenchmarkHarness.effectivePlaybackMode(),
        ) { session in
            let preloadMS = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)
            let generatedFile = try await BenchmarkHarness.runRequestBenchmark(
                handle: session.runtime.generate.audio(
                    text: E2EHarness.testingPlaybackText,
                    voiceProfile: benchmarkProfileName,
                ),
                logRecorder: session.logRecorder,
            )
            let liveSpeech = try await BenchmarkHarness.runRequestBenchmark(
                handle: session.runtime.generate.speech(
                    text: E2EHarness.testingPlaybackText,
                    voiceProfile: benchmarkProfileName,
                ),
                logRecorder: session.logRecorder,
            )

            return QwenBenchmarkSample(
                strategy: strategy,
                iteration: iteration,
                residentPreloadMS: preloadMS,
                generatedFile: generatedFile,
                liveSpeech: liveSpeech,
            )
        }
    }
}

private struct QwenBenchmarkSummary: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let host: BenchmarkHost
    let settings: QwenBenchmarkSettings
    let strategies: [QwenConditioningStrategyBenchmarkReport]
}

private struct QwenBenchmarkSettings: Codable {
    let iterations: Int
    let benchmarkProfileName: String
    let playbackTextCharacterCount: Int
    let playbackMode: BenchmarkPlaybackMode
    let timestampedSummaryPattern: String
    let latestSummaryFilename: String
    let comparedStrategies: [SpeakSwiftly.QwenConditioningStrategy]

    static func current(
        iterations: Int,
        benchmarkProfileName: String,
        playbackTextCharacterCount: Int,
        playbackMode: BenchmarkPlaybackMode,
    ) -> Self {
        Self(
            iterations: iterations,
            benchmarkProfileName: benchmarkProfileName,
            playbackTextCharacterCount: playbackTextCharacterCount,
            playbackMode: playbackMode,
            timestampedSummaryPattern: "qwen-resident-benchmark-<ISO8601>.json",
            latestSummaryFilename: "qwen-resident-benchmark-latest.json",
            comparedStrategies: [.legacyRaw, .preparedConditioning],
        )
    }
}

private struct QwenConditioningStrategyBenchmarkReport: Codable {
    let strategy: SpeakSwiftly.QwenConditioningStrategy
    let sampleCount: Int
    let residentPreloadMS: BenchmarkMetricSummary
    let generatedFile: BenchmarkRequestAggregate
    let liveSpeech: BenchmarkRequestAggregate
    let samples: [QwenBenchmarkSample]

    var prettyDescription: String {
        """
        \(strategy.rawValue): preload \(residentPreloadMS.prettyAverage) ms, file complete \(generatedFile.lifecycle.completedMS.prettyAverage) ms, file first audio \(generatedFile.generation.firstAudioChunkMS.prettyAverage) ms, live complete \(liveSpeech.lifecycle.completedMS.prettyAverage) ms, live first audio \(liveSpeech.generation.firstAudioChunkMS.prettyAverage) ms, live preroll \(liveSpeech.lifecycle.prerollReadyMS.prettyAverage) ms, tokens/s \(generatedFile.generation.tokensPerSecond.prettyAverage), peak memory \(generatedFile.generation.peakMemoryUsageGB.prettyAverage) GB
        """
    }

    static func make(from samples: [QwenBenchmarkSample]) -> [Self] {
        Dictionary(grouping: samples, by: \.strategy)
            .map { strategy, strategySamples in
                Self(
                    strategy: strategy,
                    sampleCount: strategySamples.count,
                    residentPreloadMS: .make(from: strategySamples.map(\.residentPreloadMS)),
                    generatedFile: .make(from: strategySamples.map(\.generatedFile)),
                    liveSpeech: .make(from: strategySamples.map(\.liveSpeech)),
                    samples: strategySamples.sorted { $0.iteration < $1.iteration },
                )
            }
            .sorted { $0.strategy.rawValue < $1.strategy.rawValue }
    }
}

private struct QwenBenchmarkSample: Codable {
    let strategy: SpeakSwiftly.QwenConditioningStrategy
    let iteration: Int
    let residentPreloadMS: Double
    let generatedFile: BenchmarkRequest
    let liveSpeech: BenchmarkRequest
}
#endif
