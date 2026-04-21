#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

private let backendBenchmarkSchemaVersion = 1

@Suite(
    .serialized,
    .tags(.e2e, .benchmark),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
    .enabled(
        if: speakSwiftlyBackendBenchmarkE2ETestsEnabled(),
        "This backend benchmark suite is opt-in and requires SPEAKSWIFTLY_BACKEND_BENCHMARK_E2E=1.",
    ),
)
struct BackendBenchmarkE2ETests {
    @Test func `compare resident backends with two queued live requests`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        try await Self.provisionBenchmarkProfiles(in: sandbox.profileRootURL)

        let iterations = speakSwiftlyBackendBenchmarkIterations()
        let playbackMode = BenchmarkHarness.effectivePlaybackMode()
        var samples = [BackendBenchmarkSample]()
        samples.reserveCapacity(iterations * SpeakSwiftly.SpeechBackend.allCases.count)

        for backend in SpeakSwiftly.SpeechBackend.allCases {
            for iteration in 1...iterations {
                try await samples.append(
                    Self.runBenchmarkSample(
                        profileRootURL: sandbox.profileRootURL,
                        backend: backend,
                        iteration: iteration,
                        playbackMode: playbackMode,
                    ),
                )
            }
        }

        let summary = BackendBenchmarkSummary(
            schemaVersion: backendBenchmarkSchemaVersion,
            generatedAt: Date(),
            host: .localMachine(),
            settings: .current(
                iterations: iterations,
                playbackMode: playbackMode,
                benchmarkTextCharacterCount: Self.benchmarkText.count,
            ),
            backends: BackendBenchmarkReport.make(from: samples),
        )
        let summaryURL = try BenchmarkHarness.writeSummary(
            summary,
            timestampedStem: playbackMode == .audible ? "backend-live-audible-benchmark" : "backend-live-benchmark",
            latestFilename: playbackMode == .audible ? "backend-live-audible-benchmark-latest.json" : "backend-live-benchmark-latest.json",
            generatedAt: summary.generatedAt,
        )

        print("SpeakSwiftly backend benchmark summary: \(summaryURL.path)")
        for report in summary.backends {
            print(report.prettyDescription)
        }
    }
}

private extension BackendBenchmarkE2ETests {
    static let benchmarkText = """
    SpeakSwiftly backend benchmarking starts with a deliberate stretch of ordinary prose so the first live request has enough time to warm the resident model, enter buffering, reach preroll, and settle into sustained playback instead of disappearing before the timings become useful. The point of this paragraph is not theatrical reading. The point is to give the benchmark a realistic opening span with sentences long enough to expose startup cost, queue pressure, and early playback stability under normal language.

    The second paragraph adds denser phrasing, longer clauses, and more punctuation so the benchmark does not flatten every backend into a tiny trivial request. We want the package to speak something that still sounds like real operator-facing text while being substantial enough to reveal how the second queued request behaves once the first request is already active. That lets us compare the queued-request tax across backends instead of pretending a one-line utterance tells the whole performance story.
    """

    static func profileName(for backend: SpeakSwiftly.SpeechBackend) -> String {
        "benchmark-\(backend.rawValue)-profile"
    }

    static func provisionBenchmarkProfiles(in profileRootURL: URL) async throws {
        for backend in SpeakSwiftly.SpeechBackend.allCases {
            try await BenchmarkHarness.withBenchmarkRuntime(
                profileRootURL: profileRootURL,
                backend: backend,
                qwenConditioningStrategy: .preparedConditioning,
            ) { session in
                _ = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)

                let handle = await session.runtime.voices.create(
                    design: profileName(for: backend),
                    from: E2EHarness.testingProfileText,
                    vibe: .masc,
                    voice: E2EHarness.testingProfileVoiceDescription,
                )
                _ = try await BenchmarkHarness.awaitSuccess(from: handle)
            }
        }
    }

    static func runBenchmarkSample(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
        iteration: Int,
        playbackMode: BenchmarkPlaybackMode,
    ) async throws -> BackendBenchmarkSample {
        try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: backend,
            qwenConditioningStrategy: .preparedConditioning,
            playbackMode: playbackMode,
        ) { session in
            let residentPreloadMS = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)
            let queuedPair = try await runQueuedLivePairBenchmark(
                in: session,
                backend: backend,
            )

            return BackendBenchmarkSample(
                backend: backend,
                iteration: iteration,
                residentPreloadMS: residentPreloadMS,
                queuedLivePair: queuedPair,
            )
        }
    }

    static func runQueuedLivePairBenchmark(
        in session: BenchmarkRuntimeSession,
        backend: SpeakSwiftly.SpeechBackend,
    ) async throws -> BackendQueuedLivePairBenchmark {
        let firstHandle = await session.runtime.generate.speech(
            text: benchmarkText,
            with: profileName(for: backend),
        )
        let secondHandle = await session.runtime.generate.speech(
            text: benchmarkText,
            with: profileName(for: backend),
        )

        async let firstRequest = BenchmarkHarness.runRequestBenchmark(
            handle: firstHandle,
            logRecorder: session.logRecorder,
        )
        async let secondRequest = BenchmarkHarness.runRequestBenchmark(
            handle: secondHandle,
            logRecorder: session.logRecorder,
        )

        let pair = try await BackendQueuedLivePairBenchmark(
            firstRequest: firstRequest,
            secondRequest: secondRequest,
        )

        guard pair.secondRequest.lifecycle.queuedAtMS != nil else {
            throw BenchmarkError(
                "Backend benchmark expected the second live request for backend '\(backend.rawValue)' to enter the queue, but it never reported a queued event.",
            )
        }

        return pair
    }
}

private struct BackendBenchmarkSummary: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let host: BenchmarkHost
    let settings: BackendBenchmarkSettings
    let backends: [BackendBenchmarkReport]
}

private struct BackendBenchmarkSettings: Codable {
    let iterations: Int
    let playbackMode: BenchmarkPlaybackMode
    let benchmarkTextCharacterCount: Int
    let timestampedSummaryPattern: String
    let latestSummaryFilename: String
    let benchmarkedBackends: [SpeakSwiftly.SpeechBackend]

    static func current(
        iterations: Int,
        playbackMode: BenchmarkPlaybackMode,
        benchmarkTextCharacterCount: Int,
    ) -> Self {
        Self(
            iterations: iterations,
            playbackMode: playbackMode,
            benchmarkTextCharacterCount: benchmarkTextCharacterCount,
            timestampedSummaryPattern: playbackMode == .audible
                ? "backend-live-audible-benchmark-<ISO8601>.json"
                : "backend-live-benchmark-<ISO8601>.json",
            latestSummaryFilename: playbackMode == .audible
                ? "backend-live-audible-benchmark-latest.json"
                : "backend-live-benchmark-latest.json",
            benchmarkedBackends: SpeakSwiftly.SpeechBackend.allCases,
        )
    }
}

private struct BackendBenchmarkReport: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let profileName: String
    let sampleCount: Int
    let residentPreloadMS: BenchmarkMetricSummary
    let queuedLivePair: BackendQueuedLivePairAggregate
    let samples: [BackendBenchmarkSample]

    var prettyDescription: String {
        """
        \(backend.rawValue): preload \(residentPreloadMS.prettyAverage) ms, first request complete \(queuedLivePair.firstRequest.lifecycle.completedMS.prettyAverage) ms, second request complete \(queuedLivePair.secondRequest.lifecycle.completedMS.prettyAverage) ms, second request queue wait \(queuedLivePair.penalties.secondRequestQueueWaitMS.prettyAverage) ms, second request first audio penalty \(queuedLivePair.penalties.secondRequestFirstAudioPenaltyMS.prettyAverage) ms
        """
    }

    static func make(from samples: [BackendBenchmarkSample]) -> [Self] {
        Dictionary(grouping: samples, by: \.backend)
            .map { backend, backendSamples in
                Self(
                    backend: backend,
                    profileName: BackendBenchmarkE2ETests.profileName(for: backend),
                    sampleCount: backendSamples.count,
                    residentPreloadMS: .make(from: backendSamples.map(\.residentPreloadMS)),
                    queuedLivePair: .make(from: backendSamples.map(\.queuedLivePair)),
                    samples: backendSamples.sorted { $0.iteration < $1.iteration },
                )
            }
            .sorted { $0.backend.rawValue < $1.backend.rawValue }
    }
}

private struct BackendBenchmarkSample: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let iteration: Int
    let residentPreloadMS: Double
    let queuedLivePair: BackendQueuedLivePairBenchmark
}

private struct BackendQueuedLivePairBenchmark: Codable {
    let firstRequest: BenchmarkRequest
    let secondRequest: BenchmarkRequest
}

private struct BackendQueuedLivePairAggregate: Codable {
    let sampleCount: Int
    let firstRequest: BenchmarkRequestAggregate
    let secondRequest: BenchmarkRequestAggregate
    let penalties: BackendQueuedLivePenaltyAggregate

    static func make(from samples: [BackendQueuedLivePairBenchmark]) -> Self {
        Self(
            sampleCount: samples.count,
            firstRequest: .make(from: samples.map(\.firstRequest)),
            secondRequest: .make(from: samples.map(\.secondRequest)),
            penalties: .make(from: samples),
        )
    }
}

private struct BackendQueuedLivePenaltyAggregate: Codable {
    let secondRequestQueueWaitMS: BenchmarkMetricSummary
    let secondRequestFirstAudioPenaltyMS: BenchmarkMetricSummary
    let secondRequestCompletionPenaltyMS: BenchmarkMetricSummary

    static func make(from samples: [BackendQueuedLivePairBenchmark]) -> Self {
        Self(
            secondRequestQueueWaitMS: .make(
                from: samples.compactMap {
                    Self.queueWaitMS(for: $0.secondRequest.lifecycle)
                },
            ),
            secondRequestFirstAudioPenaltyMS: .make(
                from: samples.compactMap {
                    guard
                        let first = $0.firstRequest.generation.firstAudioChunkAtMS,
                        let second = $0.secondRequest.generation.firstAudioChunkAtMS
                    else {
                        return nil
                    }
                    return second - first
                },
            ),
            secondRequestCompletionPenaltyMS: .make(
                from: samples.compactMap {
                    guard
                        let first = $0.firstRequest.lifecycle.completedAtMS,
                        let second = $0.secondRequest.lifecycle.completedAtMS
                    else {
                        return nil
                    }
                    return second - first
                },
            ),
        )
    }

    private static func queueWaitMS(for lifecycle: BenchmarkRequestLifecycleMetrics) -> Double? {
        guard
            let queuedAtMS = lifecycle.queuedAtMS,
            let startedAtMS = lifecycle.startedAtMS
        else {
            return nil
        }

        return startedAtMS - queuedAtMS
    }
}
#endif
