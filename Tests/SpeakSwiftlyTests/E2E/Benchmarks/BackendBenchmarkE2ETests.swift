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

    @Test func `compare marvis resident policies with three queued voice switches`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        try await Self.provisionMarvisBenchmarkProfiles(in: sandbox.profileRootURL)

        let iterations = speakSwiftlyBackendBenchmarkIterations()
        let playbackMode = BenchmarkHarness.effectivePlaybackMode()
        var samples = [MarvisResidentPolicyBenchmarkSample]()
        samples.reserveCapacity(iterations * SpeakSwiftly.MarvisResidentPolicy.allCases.count)

        for residentPolicy in SpeakSwiftly.MarvisResidentPolicy.allCases {
            for iteration in 1...iterations {
                try await samples.append(
                    Self.runMarvisResidentPolicySample(
                        profileRootURL: sandbox.profileRootURL,
                        residentPolicy: residentPolicy,
                        iteration: iteration,
                        playbackMode: playbackMode,
                    ),
                )
            }
        }

        let summary = MarvisResidentPolicyBenchmarkSummary(
            schemaVersion: backendBenchmarkSchemaVersion,
            generatedAt: Date(),
            host: .localMachine(),
            settings: .current(
                iterations: iterations,
                playbackMode: playbackMode,
                benchmarkTextCharacterCount: Self.benchmarkText.count,
            ),
            residentPolicies: MarvisResidentPolicyBenchmarkReport.make(from: samples),
        )
        let summaryURL = try BenchmarkHarness.writeSummary(
            summary,
            timestampedStem: playbackMode == .audible
                ? "marvis-resident-policy-audible-benchmark"
                : "marvis-resident-policy-benchmark",
            latestFilename: playbackMode == .audible
                ? "marvis-resident-policy-audible-benchmark-latest.json"
                : "marvis-resident-policy-benchmark-latest.json",
            generatedAt: summary.generatedAt,
        )

        print("SpeakSwiftly Marvis resident policy benchmark summary: \(summaryURL.path)")
        for report in summary.residentPolicies {
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

    static func provisionMarvisBenchmarkProfiles(in profileRootURL: URL) async throws {
        try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: .marvis,
            qwenConditioningStrategy: .preparedConditioning,
        ) { session in
            _ = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)

            for fixture in MarvisResidentPolicyFixture.allCases {
                let handle = await session.runtime.voices.create(
                    design: fixture.profileName,
                    from: E2EHarness.testingCloneSourceText,
                    vibe: fixture.vibe,
                    voice: fixture.voiceDescription,
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
            voiceProfile: profileName(for: backend),
        )
        let secondHandle = await session.runtime.generate.speech(
            text: benchmarkText,
            voiceProfile: profileName(for: backend),
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

    static func runMarvisResidentPolicySample(
        profileRootURL: URL,
        residentPolicy: SpeakSwiftly.MarvisResidentPolicy,
        iteration: Int,
        playbackMode: BenchmarkPlaybackMode,
    ) async throws -> MarvisResidentPolicyBenchmarkSample {
        try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: .marvis,
            qwenConditioningStrategy: .preparedConditioning,
            marvisResidentPolicy: residentPolicy,
            playbackMode: playbackMode,
        ) { session in
            let residentPreloadMS = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)
            let threeRequestSwitch = try await runMarvisThreeRequestSwitchBenchmark(in: session)

            return MarvisResidentPolicyBenchmarkSample(
                residentPolicy: residentPolicy,
                iteration: iteration,
                residentPreloadMS: residentPreloadMS,
                threeRequestSwitch: threeRequestSwitch,
            )
        }
    }

    static func runMarvisThreeRequestSwitchBenchmark(
        in session: BenchmarkRuntimeSession,
    ) async throws -> MarvisThreeRequestSwitchBenchmark {
        let handles = await [
            session.runtime.generate.speech(
                text: benchmarkText,
                voiceProfile: MarvisResidentPolicyFixture.femme.profileName,
            ),
            session.runtime.generate.speech(
                text: benchmarkText,
                voiceProfile: MarvisResidentPolicyFixture.masc.profileName,
            ),
            session.runtime.generate.speech(
                text: benchmarkText,
                voiceProfile: MarvisResidentPolicyFixture.returnToA.profileName,
            ),
        ]

        async let firstRequest = BenchmarkHarness.runRequestBenchmark(
            handle: handles[0],
            logRecorder: session.logRecorder,
        )
        async let secondRequest = BenchmarkHarness.runRequestBenchmark(
            handle: handles[1],
            logRecorder: session.logRecorder,
        )
        async let thirdRequest = BenchmarkHarness.runRequestBenchmark(
            handle: handles[2],
            logRecorder: session.logRecorder,
        )

        let result = try await MarvisThreeRequestSwitchBenchmark(
            firstRequest: firstRequest,
            secondRequest: secondRequest,
            thirdRequest: thirdRequest,
        )

        guard
            result.secondRequest.lifecycle.queuedAtMS != nil,
            result.thirdRequest.lifecycle.queuedAtMS != nil
        else {
            throw BenchmarkError(
                "The Marvis resident-policy benchmark expected the second and third live requests to enter the queue, but one of them never reported a queued event.",
            )
        }

        return result
    }
}

private enum MarvisResidentPolicyFixture: CaseIterable {
    case femme
    case masc
    case returnToA

    var profileName: String {
        switch self {
            case .femme:
                "benchmark-marvis-femme-profile"
            case .masc:
                "benchmark-marvis-masc-profile"
            case .returnToA:
                "benchmark-marvis-return-to-a-profile"
        }
    }

    var vibe: SpeakSwiftly.Vibe {
        switch self {
            case .femme:
                .femme
            case .masc:
                .masc
            case .returnToA:
                .femme
        }
    }

    var voiceDescription: String {
        switch self {
            case .femme:
                "A warm, bright, feminine narrator voice."
            case .masc:
                "A grounded, rich, masculine speaking voice."
            case .returnToA:
                "A polished, airy, feminine speaking voice."
        }
    }
}

private struct BackendBenchmarkSummary: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let host: BenchmarkHost
    let settings: BackendBenchmarkSettings
    let backends: [BackendBenchmarkReport]
}

private struct MarvisResidentPolicyBenchmarkSummary: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let host: BenchmarkHost
    let settings: MarvisResidentPolicyBenchmarkSettings
    let residentPolicies: [MarvisResidentPolicyBenchmarkReport]
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

private struct MarvisResidentPolicyBenchmarkSettings: Codable {
    let iterations: Int
    let playbackMode: BenchmarkPlaybackMode
    let benchmarkTextCharacterCount: Int
    let timestampedSummaryPattern: String
    let latestSummaryFilename: String
    let benchmarkedResidentPolicies: [SpeakSwiftly.MarvisResidentPolicy]
    let requestProfileOrder: [String]

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
                ? "marvis-resident-policy-audible-benchmark-<ISO8601>.json"
                : "marvis-resident-policy-benchmark-<ISO8601>.json",
            latestSummaryFilename: playbackMode == .audible
                ? "marvis-resident-policy-audible-benchmark-latest.json"
                : "marvis-resident-policy-benchmark-latest.json",
            benchmarkedResidentPolicies: SpeakSwiftly.MarvisResidentPolicy.allCases,
            requestProfileOrder: MarvisResidentPolicyFixture.allCases.map(\.profileName),
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

private struct MarvisResidentPolicyBenchmarkReport: Codable {
    let residentPolicy: SpeakSwiftly.MarvisResidentPolicy
    let sampleCount: Int
    let residentPreloadMS: BenchmarkMetricSummary
    let threeRequestSwitch: MarvisThreeRequestSwitchAggregate
    let samples: [MarvisResidentPolicyBenchmarkSample]

    var prettyDescription: String {
        """
        \(residentPolicy.rawValue): preload \(residentPreloadMS.prettyAverage) ms, first complete \(threeRequestSwitch.firstRequest.lifecycle.completedMS.prettyAverage) ms, second complete \(threeRequestSwitch.secondRequest.lifecycle.completedMS.prettyAverage) ms, third complete \(threeRequestSwitch.thirdRequest.lifecycle.completedMS.prettyAverage) ms, third queue wait \(threeRequestSwitch.penalties.thirdRequestQueueWaitMS.prettyAverage) ms, return-to-a first audio penalty \(threeRequestSwitch.penalties.thirdRequestFirstAudioPenaltyMS.prettyAverage) ms
        """
    }

    static func make(from samples: [MarvisResidentPolicyBenchmarkSample]) -> [Self] {
        Dictionary(grouping: samples, by: \.residentPolicy)
            .map { residentPolicy, policySamples in
                Self(
                    residentPolicy: residentPolicy,
                    sampleCount: policySamples.count,
                    residentPreloadMS: .make(from: policySamples.map(\.residentPreloadMS)),
                    threeRequestSwitch: .make(from: policySamples.map(\.threeRequestSwitch)),
                    samples: policySamples.sorted { $0.iteration < $1.iteration },
                )
            }
            .sorted { $0.residentPolicy.rawValue < $1.residentPolicy.rawValue }
    }
}

private struct BackendBenchmarkSample: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let iteration: Int
    let residentPreloadMS: Double
    let queuedLivePair: BackendQueuedLivePairBenchmark
}

private struct MarvisResidentPolicyBenchmarkSample: Codable {
    let residentPolicy: SpeakSwiftly.MarvisResidentPolicy
    let iteration: Int
    let residentPreloadMS: Double
    let threeRequestSwitch: MarvisThreeRequestSwitchBenchmark
}

private struct BackendQueuedLivePairBenchmark: Codable {
    let firstRequest: BenchmarkRequest
    let secondRequest: BenchmarkRequest
}

private struct MarvisThreeRequestSwitchBenchmark: Codable {
    let firstRequest: BenchmarkRequest
    let secondRequest: BenchmarkRequest
    let thirdRequest: BenchmarkRequest
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

private struct MarvisThreeRequestSwitchAggregate: Codable {
    let sampleCount: Int
    let firstRequest: BenchmarkRequestAggregate
    let secondRequest: BenchmarkRequestAggregate
    let thirdRequest: BenchmarkRequestAggregate
    let penalties: MarvisThreeRequestSwitchPenaltyAggregate

    static func make(from samples: [MarvisThreeRequestSwitchBenchmark]) -> Self {
        Self(
            sampleCount: samples.count,
            firstRequest: .make(from: samples.map(\.firstRequest)),
            secondRequest: .make(from: samples.map(\.secondRequest)),
            thirdRequest: .make(from: samples.map(\.thirdRequest)),
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
                    queueWaitMS(for: $0.secondRequest.lifecycle)
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

private struct MarvisThreeRequestSwitchPenaltyAggregate: Codable {
    let secondRequestQueueWaitMS: BenchmarkMetricSummary
    let thirdRequestQueueWaitMS: BenchmarkMetricSummary
    let secondRequestFirstAudioPenaltyMS: BenchmarkMetricSummary
    let thirdRequestFirstAudioPenaltyMS: BenchmarkMetricSummary
    let returnToACompletionPenaltyMS: BenchmarkMetricSummary

    static func make(from samples: [MarvisThreeRequestSwitchBenchmark]) -> Self {
        Self(
            secondRequestQueueWaitMS: .make(from: samples.compactMap {
                queueWaitMS(for: $0.secondRequest)
            }),
            thirdRequestQueueWaitMS: .make(from: samples.compactMap {
                queueWaitMS(for: $0.thirdRequest)
            }),
            secondRequestFirstAudioPenaltyMS: .make(from: samples.compactMap {
                firstAudioPenaltyMS(for: $0.firstRequest, comparedTo: $0.secondRequest)
            }),
            thirdRequestFirstAudioPenaltyMS: .make(from: samples.compactMap {
                firstAudioPenaltyMS(for: $0.firstRequest, comparedTo: $0.thirdRequest)
            }),
            returnToACompletionPenaltyMS: .make(from: samples.compactMap {
                completionPenaltyMS(for: $0.firstRequest, comparedTo: $0.thirdRequest)
            }),
        )
    }

    private static func queueWaitMS(for request: BenchmarkRequest) -> Double? {
        guard
            let queuedAtMS = request.lifecycle.queuedAtMS,
            let startedAtMS = request.lifecycle.startedAtMS
        else {
            return nil
        }

        return startedAtMS - queuedAtMS
    }

    private static func firstAudioPenaltyMS(
        for baseline: BenchmarkRequest,
        comparedTo request: BenchmarkRequest,
    ) -> Double? {
        guard
            let baselineFirstAudio = baseline.generation.firstAudioChunkAtMS,
            let requestFirstAudio = request.generation.firstAudioChunkAtMS
        else {
            return nil
        }

        return requestFirstAudio - baselineFirstAudio
    }

    private static func completionPenaltyMS(
        for baseline: BenchmarkRequest,
        comparedTo request: BenchmarkRequest,
    ) -> Double? {
        guard
            let baselineCompleted = baseline.lifecycle.completedAtMS,
            let requestCompleted = request.lifecycle.completedAtMS
        else {
            return nil
        }

        return requestCompleted - baselineCompleted
    }
}
#endif
