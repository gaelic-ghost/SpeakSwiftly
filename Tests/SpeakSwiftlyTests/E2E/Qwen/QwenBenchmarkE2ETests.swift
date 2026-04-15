import Foundation
@testable import SpeakSwiftly
import Testing

private let qwenBenchmarkSchemaVersion = 2

// MARK: - SpeakSwiftlyE2ETests.QwenBenchmarkSuite

extension SpeakSwiftlyE2ETests {
    @Suite(
        .serialized,
        .enabled(
            if: SpeakSwiftlyE2ETests.isQwenBenchmarkE2EEnabled,
            "This Qwen resident benchmark suite is opt-in and requires SPEAKSWIFTLY_QWEN_BENCHMARK_E2E=1.",
        ),
    )
    struct QwenBenchmarkSuite {
        @Test func `compare resident backends`() async throws {
            let sandbox = try E2ESandbox()
            defer { sandbox.cleanup() }

            try await Self.provisionBenchmarkProfile(in: sandbox.profileRootURL)

            let iterations = SpeakSwiftlyE2ETests.qwenBenchmarkIterations
            var samples = [QwenBenchmarkSample]()
            samples.reserveCapacity(iterations * 2)

            for backend in [SpeakSwiftly.SpeechBackend.qwen3, .qwen3CustomVoice] {
                for iteration in 1...iterations {
                    try await samples.append(
                        Self.runBenchmarkSample(
                            profileRootURL: sandbox.profileRootURL,
                            backend: backend,
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
                    playbackTextCharacterCount: SpeakSwiftlyE2ETests.testingPlaybackText.count,
                ),
                backends: QwenBackendBenchmarkReport.make(from: samples),
            )
            let summaryURL = try Self.writeBenchmarkSummary(summary)

            print("SpeakSwiftly qwen benchmark summary: \(summaryURL.path)")
            for backend in summary.backends {
                print(backend.prettyDescription)
            }
        }
    }
}

private extension SpeakSwiftlyE2ETests.QwenBenchmarkSuite {
    static let benchmarkProfileName = "benchmark-profile"

    static func provisionBenchmarkProfile(in profileRootURL: URL) async throws {
        try await withBenchmarkRuntime(profileRootURL: profileRootURL, backend: .qwen3) { runtime in
            _ = try await awaitResidentReady(on: runtime)

            let handle = await runtime.voices.create(
                design: benchmarkProfileName,
                from: SpeakSwiftlyE2ETests.testingProfileText,
                vibe: .masc,
                voice: SpeakSwiftlyE2ETests.testingProfileVoiceDescription,
            )
            _ = try await awaitSuccess(from: handle)
        }
    }

    static func runBenchmarkSample(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
        iteration: Int,
    ) async throws -> QwenBenchmarkSample {
        try await withBenchmarkRuntime(profileRootURL: profileRootURL, backend: backend) { runtime in
            let preloadMS = try await awaitResidentReady(on: runtime)
            let generatedFile = try await runRequestBenchmark(
                handle: runtime.generate.audio(
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    with: benchmarkProfileName,
                ),
            )
            let liveSpeech = try await runRequestBenchmark(
                handle: runtime.generate.speech(
                    text: SpeakSwiftlyE2ETests.testingPlaybackText,
                    with: benchmarkProfileName,
                ),
            )

            return QwenBenchmarkSample(
                backend: backend,
                iteration: iteration,
                residentPreloadMS: preloadMS,
                generatedFile: generatedFile,
                liveSpeech: liveSpeech,
            )
        }
    }

    static func withBenchmarkRuntime<T>(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
        operation: @escaping @Sendable (SpeakSwiftly.Runtime) async throws -> T,
    ) async throws -> T {
        let runtime = try await makeBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: backend,
        )

        do {
            let result = try await operation(runtime)
            await runtime.shutdown()
            return result
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    static func makeBenchmarkRuntime(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
    ) async throws -> SpeakSwiftly.Runtime {
        _ = try SpeakSwiftly.SupportResources.mlxBundleURL()
        _ = try SpeakSwiftly.SupportResources.defaultMetallibURL()

        let liveDependencies = WorkerDependencies.live()
        let dependencies = WorkerDependencies(
            fileManager: liveDependencies.fileManager,
            loadResidentModels: liveDependencies.loadResidentModels,
            loadProfileModel: liveDependencies.loadProfileModel,
            loadCloneTranscriptionModel: liveDependencies.loadCloneTranscriptionModel,
            makePlaybackController: {
                .silent(traceEnabled: false)
            },
            writeWAV: liveDependencies.writeWAV,
            loadAudioSamples: liveDependencies.loadAudioSamples,
            loadAudioFloats: liveDependencies.loadAudioFloats,
            writeStdout: { _ in },
            writeStderr: { message in
                fputs("SpeakSwiftly benchmark runtime stderr: \(message)\n", stderr)
            },
            now: liveDependencies.now,
            readRuntimeMemory: liveDependencies.readRuntimeMemory,
        )

        let profileStore = ProfileStore(
            rootURL: profileRootURL,
            fileManager: dependencies.fileManager,
        )
        let generatedFileStore = GeneratedFileStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GeneratedFileStore.directoryName, isDirectory: true),
            fileManager: dependencies.fileManager,
        )
        let generationJobStore = GenerationJobStore(
            rootURL: profileStore.rootURL.appendingPathComponent(GenerationJobStore.directoryName, isDirectory: true),
            fileManager: dependencies.fileManager,
        )
        let normalizer = try SpeakSwiftly.Normalizer(
            persistenceURL: profileStore.rootURL.appending(path: ProfileStore.textProfilesFileName),
        )
        let playbackController = await PlaybackController(driver: dependencies.makePlaybackController())

        let runtime = SpeakSwiftly.Runtime(
            dependencies: dependencies,
            speechBackend: backend,
            profileStore: profileStore,
            generatedFileStore: generatedFileStore,
            generationJobStore: generationJobStore,
            normalizer: normalizer,
            playbackController: playbackController,
        )
        await runtime.installPlaybackHooks()
        return runtime
    }

    static func awaitResidentReady(on runtime: SpeakSwiftly.Runtime) async throws -> Double {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let statuses = await runtime.statusEvents()

        await runtime.start()

        for await status in statuses {
            switch status.stage {
                case .residentModelReady:
                    return milliseconds(since: startedAt, clock: clock)
                case .residentModelFailed:
                    throw BenchmarkError("SpeakSwiftly benchmark runtime failed before the resident models became ready.")
                case .warmingResidentModel, .residentModelsUnloaded:
                    continue
            }
        }

        throw BenchmarkError("SpeakSwiftly benchmark runtime stopped emitting status updates before reporting resident_model_ready.")
    }

    static func awaitSuccess(
        from handle: SpeakSwiftly.RequestHandle,
    ) async throws -> SpeakSwiftly.Success {
        var acknowledgedSuccess: SpeakSwiftly.Success?

        for try await event in handle.events {
            switch event {
                case let .acknowledged(success):
                    acknowledgedSuccess = success
                case let .completed(success):
                    return success
                case .queued, .started, .progress:
                    continue
            }
        }

        if let acknowledgedSuccess {
            return acknowledgedSuccess
        }

        throw BenchmarkError("Request '\(handle.id)' ended before it reported an acknowledged or completed success payload.")
    }

    static func runRequestBenchmark(
        handle: SpeakSwiftly.RequestHandle,
    ) async throws -> QwenRequestBenchmark {
        let clock = ContinuousClock()
        let submittedAt = clock.now

        async let lifecycle = collectLifecycleMetrics(
            from: handle.events,
            submittedAt: submittedAt,
            clock: clock,
        )
        async let generation = collectGenerationMetrics(
            from: handle.generationEvents,
            submittedAt: submittedAt,
            clock: clock,
        )

        let (lifecycleMetrics, success) = try await lifecycle
        let generationMetrics = try await generation

        return QwenRequestBenchmark(
            requestID: handle.id,
            operation: handle.operation,
            generatedArtifactID: success.generatedFile?.artifactID,
            lifecycle: lifecycleMetrics,
            generation: generationMetrics,
        )
    }

    static func collectLifecycleMetrics(
        from events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, any Swift.Error>,
        submittedAt: ContinuousClock.Instant,
        clock: ContinuousClock,
    ) async throws -> (QwenLifecycleMetrics, SpeakSwiftly.Success) {
        var metrics = QwenLifecycleMetrics()
        var acknowledgedSuccess: SpeakSwiftly.Success?

        for try await event in events {
            let elapsedMS = milliseconds(since: submittedAt, clock: clock)

            switch event {
                case let .queued(queued):
                    metrics.queuedAtMS = metrics.queuedAtMS ?? elapsedMS
                    metrics.queueReason = queued.reason.rawValue
                    metrics.queuePosition = queued.queuePosition

                case let .acknowledged(success):
                    metrics.acknowledgedAtMS = metrics.acknowledgedAtMS ?? elapsedMS
                    acknowledgedSuccess = success

                case .started:
                    metrics.startedAtMS = metrics.startedAtMS ?? elapsedMS

                case let .progress(progress):
                    switch progress.stage {
                        case .bufferingAudio:
                            metrics.bufferingAudioAtMS = metrics.bufferingAudioAtMS ?? elapsedMS
                        case .prerollReady:
                            metrics.prerollReadyAtMS = metrics.prerollReadyAtMS ?? elapsedMS
                        case .playbackFinished:
                            metrics.playbackFinishedAtMS = metrics.playbackFinishedAtMS ?? elapsedMS
                        default:
                            continue
                    }

                case let .completed(success):
                    metrics.completedAtMS = metrics.completedAtMS ?? elapsedMS
                    return (metrics, success)
            }
        }

        if let acknowledgedSuccess {
            return (metrics, acknowledgedSuccess)
        }

        throw BenchmarkError("A benchmark request stream ended before it reported terminal success.")
    }

    static func collectGenerationMetrics(
        from events: AsyncThrowingStream<SpeakSwiftly.GenerationEventUpdate, any Swift.Error>,
        submittedAt: ContinuousClock.Instant,
        clock: ContinuousClock,
    ) async throws -> QwenGenerationMetrics {
        var metrics = QwenGenerationMetrics()

        for try await update in events {
            let elapsedMS = milliseconds(since: submittedAt, clock: clock)

            switch update.event {
                case .token:
                    metrics.firstTokenAtMS = metrics.firstTokenAtMS ?? elapsedMS
                    metrics.observedTokenCount += 1

                case let .info(info):
                    metrics.infoAtMS = metrics.infoAtMS ?? elapsedMS
                    metrics.promptTokenCount = info.promptTokenCount
                    metrics.generationTokenCount = info.generationTokenCount
                    metrics.prefillTimeMS = info.prefillTime * 1000
                    metrics.generateTimeMS = info.generateTime * 1000
                    metrics.tokensPerSecond = info.tokensPerSecond
                    metrics.peakMemoryUsageGB = info.peakMemoryUsage

                case let .audioChunk(sampleCount):
                    metrics.firstAudioChunkAtMS = metrics.firstAudioChunkAtMS ?? elapsedMS
                    metrics.audioChunkCount += 1
                    metrics.totalAudioSampleCount += sampleCount
            }
        }

        return metrics
    }

    static func writeBenchmarkSummary(_ summary: QwenBenchmarkSummary) throws -> URL {
        let benchmarksRoot = try packageRootURL()
            .appendingPathComponent(".local/benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: benchmarksRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: summary.generatedAt).replacingOccurrences(of: ":", with: "-")
        let summaryURL = benchmarksRoot.appendingPathComponent("qwen-resident-benchmark-\(stamp).json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(summary)
        try encoded.write(to: summaryURL, options: .atomic)

        let latestSummaryURL = benchmarksRoot.appendingPathComponent("qwen-resident-benchmark-latest.json", isDirectory: false)
        try encoded.write(to: latestSummaryURL, options: .atomic)
        return summaryURL
    }

    static func packageRootURL() throws -> URL {
        let fileManager = FileManager.default
        var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while true {
            let manifestURL = candidateURL.appendingPathComponent("Package.swift", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL != candidateURL else {
                throw BenchmarkError("The qwen benchmark suite could not find the package root while walking upward from '\(#filePath)'.")
            }

            candidateURL = parentURL
        }
    }

    static func milliseconds(
        since instant: ContinuousClock.Instant,
        clock: ContinuousClock,
    ) -> Double {
        let duration = clock.now - instant
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

// MARK: - QwenBenchmarkSummary

private struct QwenBenchmarkSummary: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let host: QwenBenchmarkHost
    let settings: QwenBenchmarkSettings
    let backends: [QwenBackendBenchmarkReport]
}

// MARK: - QwenBenchmarkHost

private struct QwenBenchmarkHost: Codable {
    let machineArchitecture: String
    let operatingSystemVersion: String
    let activeProcessorCount: Int
    let physicalMemoryBytes: UInt64

    static func localMachine() -> Self {
        let processInfo = ProcessInfo.processInfo
        return Self(
            machineArchitecture: hostMachineArchitecture(),
            operatingSystemVersion: processInfo.operatingSystemVersionString,
            activeProcessorCount: processInfo.activeProcessorCount,
            physicalMemoryBytes: processInfo.physicalMemory,
        )
    }

    private static func hostMachineArchitecture() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return "unknown" }

        let machine = systemInfo.machine
        return withUnsafePointer(to: machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: machine)) {
                String(cString: $0)
            }
        }
    }
}

// MARK: - QwenBenchmarkSettings

private struct QwenBenchmarkSettings: Codable {
    let iterations: Int
    let benchmarkProfileName: String
    let playbackTextCharacterCount: Int
    let timestampedSummaryPattern: String
    let latestSummaryFilename: String
    let comparedBackends: [SpeakSwiftly.SpeechBackend]

    static func current(
        iterations: Int,
        benchmarkProfileName: String,
        playbackTextCharacterCount: Int,
    ) -> Self {
        Self(
            iterations: iterations,
            benchmarkProfileName: benchmarkProfileName,
            playbackTextCharacterCount: playbackTextCharacterCount,
            timestampedSummaryPattern: "qwen-resident-benchmark-<ISO8601>.json",
            latestSummaryFilename: "qwen-resident-benchmark-latest.json",
            comparedBackends: [.qwen3, .qwen3CustomVoice],
        )
    }
}

// MARK: - QwenBackendBenchmarkReport

private struct QwenBackendBenchmarkReport: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let sampleCount: Int
    let residentPreloadMS: QwenMetricSummary
    let generatedFile: QwenRequestBenchmarkAggregate
    let liveSpeech: QwenRequestBenchmarkAggregate
    let samples: [QwenBenchmarkSample]

    var prettyDescription: String {
        """
        \(backend.rawValue): preload \(residentPreloadMS.prettyAverage) ms, file complete \(generatedFile.lifecycle.completedMS.prettyAverage) ms, file first audio \(generatedFile.generation.firstAudioChunkMS.prettyAverage) ms, live complete \(liveSpeech.lifecycle.completedMS.prettyAverage) ms, live first audio \(liveSpeech.generation.firstAudioChunkMS.prettyAverage) ms, live preroll \(liveSpeech.lifecycle.prerollReadyMS.prettyAverage) ms, tokens/s \(generatedFile.generation.tokensPerSecond.prettyAverage), peak memory \(generatedFile.generation.peakMemoryUsageGB.prettyAverage) GB
        """
    }

    static func make(from samples: [QwenBenchmarkSample]) -> [Self] {
        Dictionary(grouping: samples, by: \.backend)
            .map { backend, backendSamples in
                Self(
                    backend: backend,
                    sampleCount: backendSamples.count,
                    residentPreloadMS: .make(from: backendSamples.map(\.residentPreloadMS)),
                    generatedFile: .make(from: backendSamples.map(\.generatedFile)),
                    liveSpeech: .make(from: backendSamples.map(\.liveSpeech)),
                    samples: backendSamples.sorted { $0.iteration < $1.iteration },
                )
            }
            .sorted { $0.backend.rawValue < $1.backend.rawValue }
    }
}

// MARK: - QwenBenchmarkSample

private struct QwenBenchmarkSample: Codable {
    let backend: SpeakSwiftly.SpeechBackend
    let iteration: Int
    let residentPreloadMS: Double
    let generatedFile: QwenRequestBenchmark
    let liveSpeech: QwenRequestBenchmark
}

// MARK: - QwenRequestBenchmark

private struct QwenRequestBenchmark: Codable {
    let requestID: String
    let operation: String
    let generatedArtifactID: String?
    let lifecycle: QwenLifecycleMetrics
    let generation: QwenGenerationMetrics
}

// MARK: - QwenLifecycleMetrics

private struct QwenLifecycleMetrics: Codable {
    var queuedAtMS: Double?
    var queueReason: String?
    var queuePosition: Int?
    var acknowledgedAtMS: Double?
    var startedAtMS: Double?
    var bufferingAudioAtMS: Double?
    var prerollReadyAtMS: Double?
    var playbackFinishedAtMS: Double?
    var completedAtMS: Double?
}

// MARK: - QwenGenerationMetrics

private struct QwenGenerationMetrics: Codable {
    var firstTokenAtMS: Double?
    var infoAtMS: Double?
    var firstAudioChunkAtMS: Double?
    var observedTokenCount = 0
    var audioChunkCount = 0
    var totalAudioSampleCount = 0
    var promptTokenCount: Int?
    var generationTokenCount: Int?
    var prefillTimeMS: Double?
    var generateTimeMS: Double?
    var tokensPerSecond: Double?
    var peakMemoryUsageGB: Double?
}

// MARK: - QwenRequestBenchmarkAggregate

private struct QwenRequestBenchmarkAggregate: Codable {
    let sampleCount: Int
    let lifecycle: QwenLifecycleMetricAggregate
    let generation: QwenGenerationMetricAggregate

    static func make(from samples: [QwenRequestBenchmark]) -> Self {
        Self(
            sampleCount: samples.count,
            lifecycle: .make(from: samples.map(\.lifecycle)),
            generation: .make(from: samples.map(\.generation)),
        )
    }
}

// MARK: - QwenLifecycleMetricAggregate

private struct QwenLifecycleMetricAggregate: Codable {
    let acknowledgedMS: QwenMetricSummary
    let startedMS: QwenMetricSummary
    let bufferingAudioMS: QwenMetricSummary
    let prerollReadyMS: QwenMetricSummary
    let playbackFinishedMS: QwenMetricSummary
    let completedMS: QwenMetricSummary

    static func make(from samples: [QwenLifecycleMetrics]) -> Self {
        Self(
            acknowledgedMS: .make(from: samples.compactMap(\.acknowledgedAtMS)),
            startedMS: .make(from: samples.compactMap(\.startedAtMS)),
            bufferingAudioMS: .make(from: samples.compactMap(\.bufferingAudioAtMS)),
            prerollReadyMS: .make(from: samples.compactMap(\.prerollReadyAtMS)),
            playbackFinishedMS: .make(from: samples.compactMap(\.playbackFinishedAtMS)),
            completedMS: .make(from: samples.compactMap(\.completedAtMS)),
        )
    }
}

// MARK: - QwenGenerationMetricAggregate

private struct QwenGenerationMetricAggregate: Codable {
    let firstTokenMS: QwenMetricSummary
    let infoMS: QwenMetricSummary
    let firstAudioChunkMS: QwenMetricSummary
    let observedTokenCount: QwenMetricSummary
    let audioChunkCount: QwenMetricSummary
    let totalAudioSampleCount: QwenMetricSummary
    let promptTokenCount: QwenMetricSummary
    let generationTokenCount: QwenMetricSummary
    let prefillTimeMS: QwenMetricSummary
    let generateTimeMS: QwenMetricSummary
    let tokensPerSecond: QwenMetricSummary
    let peakMemoryUsageGB: QwenMetricSummary

    static func make(from samples: [QwenGenerationMetrics]) -> Self {
        Self(
            firstTokenMS: .make(from: samples.compactMap(\.firstTokenAtMS)),
            infoMS: .make(from: samples.compactMap(\.infoAtMS)),
            firstAudioChunkMS: .make(from: samples.compactMap(\.firstAudioChunkAtMS)),
            observedTokenCount: .make(from: samples.map { Double($0.observedTokenCount) }),
            audioChunkCount: .make(from: samples.map { Double($0.audioChunkCount) }),
            totalAudioSampleCount: .make(from: samples.map { Double($0.totalAudioSampleCount) }),
            promptTokenCount: .make(from: samples.compactMap { $0.promptTokenCount.map(Double.init) }),
            generationTokenCount: .make(from: samples.compactMap { $0.generationTokenCount.map(Double.init) }),
            prefillTimeMS: .make(from: samples.compactMap(\.prefillTimeMS)),
            generateTimeMS: .make(from: samples.compactMap(\.generateTimeMS)),
            tokensPerSecond: .make(from: samples.compactMap(\.tokensPerSecond)),
            peakMemoryUsageGB: .make(from: samples.compactMap(\.peakMemoryUsageGB)),
        )
    }
}

// MARK: - QwenMetricSummary

private struct QwenMetricSummary: Codable {
    let count: Int
    let min: Double?
    let average: Double?
    let max: Double?

    var prettyAverage: String {
        guard let average else { return "n/a" }

        return String(format: "%.2f", average)
    }

    static func make(from values: [Double]) -> Self {
        guard !values.isEmpty else {
            return Self(count: 0, min: nil, average: nil, max: nil)
        }

        return Self(
            count: values.count,
            min: values.min(),
            average: values.reduce(0, +) / Double(values.count),
            max: values.max(),
        )
    }
}

// MARK: - BenchmarkError

private struct BenchmarkError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
