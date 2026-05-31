#if os(macOS)
import Foundation
@testable import SpeakSwiftly
import Testing

private let qwenQuantBenchmarkSchemaVersion = 1

@Suite(
    .serialized,
    .tags(.e2e, .qwen, .benchmark),
    .enabled(
        if: speakSwiftlyE2ETestsEnabled(),
        "These end-to-end worker tests are opt-in and require SPEAKSWIFTLY_E2E=1.",
    ),
    .enabled(
        if: speakSwiftlyQwenQuantBenchmarkE2ETestsEnabled(),
        "This Qwen quantization benchmark suite is opt-in and requires SPEAKSWIFTLY_QWEN_QUANT_BENCHMARK_E2E=1.",
    ),
)
struct QwenQuantizationBenchmarkE2ETests {
    @Test func `measure qwen quant backend matrix`() async throws {
        let sandbox = try E2ESandbox()
        defer { sandbox.cleanup() }

        try await Self.provisionBenchmarkProfile(in: sandbox.profileRootURL)

        let generatedAt = Date()
        let deviceLabel = Self.deviceLabel(host: .localMachine())
        let iterations = speakSwiftlyQwenBenchmarkIterations()
        var backendReports = [QwenQuantBackendReport]()

        for backend in speakSwiftlyQwenQuantBenchmarkBackends() {
            var outcomes = [QwenQuantBenchmarkOutcome]()

            for iteration in 1...iterations {
                for scenario in QwenQuantBenchmarkScenario.allCases {
                    await outcomes.append(
                        Self.runOutcome(
                            backend: backend,
                            scenario: scenario,
                            iteration: iteration,
                            profileRootURL: sandbox.profileRootURL,
                        ),
                    )
                }
            }

            backendReports.append(
                QwenQuantBackendReport(
                    backend: backend,
                    modelRepo: backend.residentModelRepo,
                    outcomes: outcomes,
                ),
            )
        }

        let summary = QwenQuantBenchmarkSummary(
            schemaVersion: qwenQuantBenchmarkSchemaVersion,
            generatedAt: generatedAt,
            deviceLabel: deviceLabel,
            host: .localMachine(),
            settings: .current(
                iterations: iterations,
                benchmarkProfileName: Self.benchmarkProfileName,
                playbackTextCharacterCount: E2EHarness.testingPlaybackText.count,
                playbackMode: BenchmarkHarness.effectivePlaybackMode(),
                backends: speakSwiftlyQwenQuantBenchmarkBackends(),
            ),
            backends: backendReports,
        )
        let summaryURL = try BenchmarkHarness.writeSummary(
            summary,
            timestampedStem: "qwen-quant-benchmark-\(deviceLabel)",
            latestFilename: "latest.json",
            generatedAt: generatedAt,
            subdirectory: "qwen-quant/\(deviceLabel)",
        )

        print("SpeakSwiftly qwen quant benchmark summary: \(summaryURL.path)")
        for report in summary.backends {
            print(report.prettyDescription)
        }
    }
}

private extension QwenQuantizationBenchmarkE2ETests {
    static let benchmarkProfileName = "benchmark-profile"
    static let sampleTimeout: Duration = .seconds(20 * 60)

    static func provisionBenchmarkProfile(in profileRootURL: URL) async throws {
        try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: .qwen3_smol,
            qwenConditioningStrategy: .preparedConditioning,
        ) { session in
            _ = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)

            let handle = await session.runtime.voices.create(
                design: benchmarkProfileName,
                from: E2EHarness.testingProfileText,
                vibe: .masc,
                voiceDescription: E2EHarness.testingProfileVoiceDescription,
            )
            _ = try await BenchmarkHarness.awaitSuccess(from: handle)
        }
    }

    static func runOutcome(
        backend: SpeakSwiftly.SpeechBackend,
        scenario: QwenQuantBenchmarkScenario,
        iteration: Int,
        profileRootURL: URL,
    ) async -> QwenQuantBenchmarkOutcome {
        let startedAt = Date()
        do {
            let sample = try await withBenchmarkTimeout(sampleTimeout) {
                try await runSample(
                    backend: backend,
                    scenario: scenario,
                    iteration: iteration,
                    profileRootURL: profileRootURL,
                )
            }
            return QwenQuantBenchmarkOutcome(
                backend: backend,
                scenario: scenario,
                iteration: iteration,
                startedAt: startedAt,
                status: .completed,
                sample: sample,
                failure: nil,
            )
        } catch let timeout as QwenQuantBenchmarkTimeout {
            return QwenQuantBenchmarkOutcome(
                backend: backend,
                scenario: scenario,
                iteration: iteration,
                startedAt: startedAt,
                status: .timedOut,
                sample: nil,
                failure: QwenQuantBenchmarkFailure(message: timeout.description),
            )
        } catch {
            return QwenQuantBenchmarkOutcome(
                backend: backend,
                scenario: scenario,
                iteration: iteration,
                startedAt: startedAt,
                status: .failed,
                sample: nil,
                failure: QwenQuantBenchmarkFailure(message: String(describing: error)),
            )
        }
    }

    static func withBenchmarkTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T,
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw QwenQuantBenchmarkTimeout(timeout: timeout)
            }

            guard let result = try await group.next() else {
                throw QwenQuantBenchmarkTimeout(timeout: timeout)
            }

            group.cancelAll()
            return result
        }
    }

    static func runSample(
        backend: SpeakSwiftly.SpeechBackend,
        scenario: QwenQuantBenchmarkScenario,
        iteration: Int,
        profileRootURL: URL,
    ) async throws -> QwenQuantBenchmarkSample {
        let signposts = BenchmarkSignpostRecorder(backend: backend, workload: scenario.rawValue)
        let sampleInterval = signposts.beginSample()
        defer { sampleInterval.end() }

        return try await BenchmarkHarness.withBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: backend,
            qwenConditioningStrategy: .preparedConditioning,
            playbackMode: BenchmarkHarness.effectivePlaybackMode(),
            playbackTrace: speakSwiftlyPlaybackTraceE2ETestsEnabled(),
        ) { session in
            let residentPreloadInterval = signposts.beginResidentPreload()
            let residentPreloadMS = try await BenchmarkHarness.awaitResidentReady(on: session.runtime)
            residentPreloadInterval.end()

            if scenario == .reload {
                let unloadHandle = await session.runtime.unloadModels()
                _ = try await BenchmarkHarness.awaitSuccess(from: unloadHandle)
                let reloadHandle = await session.runtime.reloadModels()
                _ = try await BenchmarkHarness.awaitSuccess(from: reloadHandle)
            }

            let generatedAudio = try await BenchmarkHarness.runRequestBenchmark(
                handle: session.runtime.generate.audio(
                    text: E2EHarness.testingPlaybackText,
                    voiceProfile: benchmarkProfileName,
                ),
                logRecorder: session.logRecorder,
                signposts: signposts,
            )
            let liveSpeech = try await BenchmarkHarness.runRequestBenchmark(
                handle: session.runtime.generate.speech(
                    text: E2EHarness.testingPlaybackText,
                    voiceProfile: benchmarkProfileName,
                ),
                logRecorder: session.logRecorder,
                signposts: signposts,
            )

            let firstQueued = await session.runtime.generate.speech(
                text: E2EHarness.testingPlaybackText,
                voiceProfile: benchmarkProfileName,
            )
            let secondQueued = await session.runtime.generate.speech(
                text: E2EHarness.testingPlaybackText,
                voiceProfile: benchmarkProfileName,
            )
            async let firstQueuedBenchmark = BenchmarkHarness.runRequestBenchmark(
                handle: firstQueued,
                logRecorder: session.logRecorder,
                signposts: signposts,
            )
            async let secondQueuedBenchmark = BenchmarkHarness.runRequestBenchmark(
                handle: secondQueued,
                logRecorder: session.logRecorder,
                signposts: signposts,
            )
            let queuedLiveSpeech = try await [firstQueuedBenchmark, secondQueuedBenchmark]

            return QwenQuantBenchmarkSample(
                backend: backend,
                scenario: scenario,
                iteration: iteration,
                residentPreloadMS: residentPreloadMS,
                generatedAudio: generatedAudio,
                liveSpeech: liveSpeech,
                queuedLiveSpeech: queuedLiveSpeech,
                warnings: session.logRecorder.warningSummary(
                    for: ([generatedAudio, liveSpeech] + queuedLiveSpeech).map(\.requestID),
                ),
                resources: session.logRecorder.peakResourceSnapshot(),
            )
        }
    }

    static func deviceLabel(host: BenchmarkHost) -> String {
        if let configured = speakSwiftlyQwenQuantBenchmarkDeviceLabel() {
            return slug(configured)
        }

        let memoryGB = Int((Double(host.physicalMemoryBytes) / 1_000_000_000).rounded())
        return slug("\(host.machineArchitecture)-\(memoryGB)gb")
    }

    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "unknown-device" : collapsed
    }
}

private struct QwenQuantBenchmarkSummary: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let deviceLabel: String
    let host: BenchmarkHost
    let settings: QwenQuantBenchmarkSettings
    let backends: [QwenQuantBackendReport]
}

private struct QwenQuantBenchmarkSettings: Codable {
    let iterations: Int
    let benchmarkProfileName: String
    let playbackTextCharacterCount: Int
    let playbackMode: BenchmarkPlaybackMode
    let timestampedSummaryPattern: String
    let latestSummaryFilename: String
    let comparedBackends: [SpeakSwiftly.SpeechBackend]
    let scenarios: [QwenQuantBenchmarkScenario]

    static func current(
        iterations: Int,
        benchmarkProfileName: String,
        playbackTextCharacterCount: Int,
        playbackMode: BenchmarkPlaybackMode,
        backends: [SpeakSwiftly.SpeechBackend],
    ) -> Self {
        Self(
            iterations: iterations,
            benchmarkProfileName: benchmarkProfileName,
            playbackTextCharacterCount: playbackTextCharacterCount,
            playbackMode: playbackMode,
            timestampedSummaryPattern: "qwen-quant-benchmark-<device>-<ISO8601>.json",
            latestSummaryFilename: "latest.json",
            comparedBackends: backends,
            scenarios: QwenQuantBenchmarkScenario.allCases,
        )
    }
}

private struct QwenQuantBackendReport: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let modelRepo: String
    let outcomes: [QwenQuantBenchmarkOutcome]

    var prettyDescription: String {
        let completedCount = outcomes.filter { $0.status == .completed }.count
        let failedCount = outcomes.filter { $0.status == .failed }.count
        let firstAudioMS = BenchmarkMetricSummary.make(
            from: outcomes.compactMap { $0.sample?.liveSpeech.generation.firstAudioChunkAtMS },
        )
        let completedMS = BenchmarkMetricSummary.make(
            from: outcomes.compactMap { $0.sample?.liveSpeech.lifecycle.completedAtMS },
        )
        return "\(backend.rawValue): \(completedCount) completed, \(failedCount) failed, live first audio \(firstAudioMS.prettyAverage) ms, live complete \(completedMS.prettyAverage) ms"
    }
}

private struct QwenQuantBenchmarkOutcome: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let scenario: QwenQuantBenchmarkScenario
    let iteration: Int
    let startedAt: Date
    let status: QwenQuantBenchmarkStatus
    let sample: QwenQuantBenchmarkSample?
    let failure: QwenQuantBenchmarkFailure?
}

private enum QwenQuantBenchmarkStatus: String, Codable {
    case completed
    case failed
    case timedOut
}

private enum QwenQuantBenchmarkScenario: String, Codable, CaseIterable {
    case cold
    case warm
    case reload
}

private struct QwenQuantBenchmarkFailure: Codable {
    let message: String
}

private struct QwenQuantBenchmarkTimeout: Error, CustomStringConvertible {
    let timeout: Duration

    var description: String {
        "Qwen quant benchmark sample timed out after \(timeout). The backend may have stalled during model load, generation, or playback drain."
    }
}

private struct QwenQuantBenchmarkSample: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let scenario: QwenQuantBenchmarkScenario
    let iteration: Int
    let residentPreloadMS: Double
    let generatedAudio: BenchmarkRequest
    let liveSpeech: BenchmarkRequest
    let queuedLiveSpeech: [BenchmarkRequest]
    let warnings: BenchmarkWarningSummary
    let resources: BenchmarkResourceSnapshot
}
#endif
