#if os(macOS)
import Foundation
@preconcurrency import MLX
import os
@testable import SpeakSwiftly

struct BenchmarkRuntimeSession {
    let runtime: SpeakSwiftly.Runtime
    let logRecorder: BenchmarkLogRecorder
    let signposts: BenchmarkSignpostRecorder
}

enum BenchmarkPlaybackMode: String, Codable {
    case silent
    case audible
}

struct BenchmarkHost: Codable {
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

struct BenchmarkMetricSummary: Codable {
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

struct BenchmarkRequestLifecycleMetrics: Codable {
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

struct BenchmarkRequestGenerationMetrics: Codable {
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

struct BenchmarkRequest: Codable {
    let requestID: String
    let operation: String
    let generatedArtifactID: String?
    let lifecycle: BenchmarkRequestLifecycleMetrics
    let generation: BenchmarkRequestGenerationMetrics
    let resources: BenchmarkRequestResourceMetrics
    let playback: BenchmarkPlaybackMetrics?
}

struct BenchmarkRequestAggregate: Codable {
    let sampleCount: Int
    let lifecycle: BenchmarkLifecycleMetricAggregate
    let generation: BenchmarkGenerationMetricAggregate
    let resources: BenchmarkResourceMetricAggregate
    let playback: BenchmarkPlaybackMetricAggregate

    static func make(from samples: [BenchmarkRequest]) -> Self {
        Self(
            sampleCount: samples.count,
            lifecycle: .make(from: samples.map(\.lifecycle)),
            generation: .make(from: samples.map(\.generation)),
            resources: .make(from: samples.map(\.resources)),
            playback: .make(from: samples.compactMap(\.playback)),
        )
    }
}

struct BenchmarkLifecycleMetricAggregate: Codable {
    let acknowledgedMS: BenchmarkMetricSummary
    let startedMS: BenchmarkMetricSummary
    let bufferingAudioMS: BenchmarkMetricSummary
    let prerollReadyMS: BenchmarkMetricSummary
    let playbackFinishedMS: BenchmarkMetricSummary
    let completedMS: BenchmarkMetricSummary

    static func make(from samples: [BenchmarkRequestLifecycleMetrics]) -> Self {
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

struct BenchmarkGenerationMetricAggregate: Codable {
    let firstTokenMS: BenchmarkMetricSummary
    let infoMS: BenchmarkMetricSummary
    let firstAudioChunkMS: BenchmarkMetricSummary
    let observedTokenCount: BenchmarkMetricSummary
    let audioChunkCount: BenchmarkMetricSummary
    let totalAudioSampleCount: BenchmarkMetricSummary
    let promptTokenCount: BenchmarkMetricSummary
    let generationTokenCount: BenchmarkMetricSummary
    let prefillTimeMS: BenchmarkMetricSummary
    let generateTimeMS: BenchmarkMetricSummary
    let tokensPerSecond: BenchmarkMetricSummary
    let peakMemoryUsageGB: BenchmarkMetricSummary

    static func make(from samples: [BenchmarkRequestGenerationMetrics]) -> Self {
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

struct BenchmarkResourceSnapshot: Codable {
    let label: String
    let elapsedMS: Double
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let processUserCPUTimeNS: Int?
    let processSystemCPUTimeNS: Int?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
    let mlxCacheLimitBytes: Int?
    let mlxMemoryLimitBytes: Int?

    var processCPUTimeNS: Int? {
        guard
            let processUserCPUTimeNS,
            let processSystemCPUTimeNS
        else {
            return nil
        }

        return processUserCPUTimeNS + processSystemCPUTimeNS
    }
}

struct BenchmarkRequestResourceMetrics: Codable {
    let snapshots: [BenchmarkResourceSnapshot]
    let processCPUTimeDeltaMS: Double?
    let maxProcessResidentBytes: Int?
    let maxProcessPhysFootprintBytes: Int?
    let maxMLXActiveMemoryBytes: Int?
    let maxMLXCacheMemoryBytes: Int?
    let maxMLXPeakMemoryBytes: Int?

    static func make(from snapshots: [BenchmarkResourceSnapshot]) -> Self {
        let sortedSnapshots = snapshots.sorted { $0.elapsedMS < $1.elapsedMS }
        return Self(
            snapshots: sortedSnapshots,
            processCPUTimeDeltaMS: cpuTimeDeltaMS(from: sortedSnapshots),
            maxProcessResidentBytes: sortedSnapshots.compactMap(\.processResidentBytes).max(),
            maxProcessPhysFootprintBytes: sortedSnapshots.compactMap(\.processPhysFootprintBytes).max(),
            maxMLXActiveMemoryBytes: sortedSnapshots.compactMap(\.mlxActiveMemoryBytes).max(),
            maxMLXCacheMemoryBytes: sortedSnapshots.compactMap(\.mlxCacheMemoryBytes).max(),
            maxMLXPeakMemoryBytes: sortedSnapshots.compactMap(\.mlxPeakMemoryBytes).max(),
        )
    }

    private static func cpuTimeDeltaMS(from snapshots: [BenchmarkResourceSnapshot]) -> Double? {
        guard
            let first = snapshots.compactMap(\.processCPUTimeNS).first,
            let last = snapshots.compactMap(\.processCPUTimeNS).last,
            last >= first
        else {
            return nil
        }

        return Double(last - first) / 1_000_000
    }
}

struct BenchmarkResourceMetricAggregate: Codable {
    let processCPUTimeDeltaMS: BenchmarkMetricSummary
    let maxProcessResidentBytes: BenchmarkMetricSummary
    let maxProcessPhysFootprintBytes: BenchmarkMetricSummary
    let maxMLXActiveMemoryBytes: BenchmarkMetricSummary
    let maxMLXCacheMemoryBytes: BenchmarkMetricSummary
    let maxMLXPeakMemoryBytes: BenchmarkMetricSummary

    static func make(from samples: [BenchmarkRequestResourceMetrics]) -> Self {
        Self(
            processCPUTimeDeltaMS: .make(from: samples.compactMap(\.processCPUTimeDeltaMS)),
            maxProcessResidentBytes: .make(from: samples.compactMap { $0.maxProcessResidentBytes.map(Double.init) }),
            maxProcessPhysFootprintBytes: .make(from: samples.compactMap { $0.maxProcessPhysFootprintBytes.map(Double.init) }),
            maxMLXActiveMemoryBytes: .make(from: samples.compactMap { $0.maxMLXActiveMemoryBytes.map(Double.init) }),
            maxMLXCacheMemoryBytes: .make(from: samples.compactMap { $0.maxMLXCacheMemoryBytes.map(Double.init) }),
            maxMLXPeakMemoryBytes: .make(from: samples.compactMap { $0.maxMLXPeakMemoryBytes.map(Double.init) }),
        )
    }
}

struct BenchmarkPlaybackMetrics: Codable {
    var startupBufferedAudioMS: Double?
    var timeToFirstChunkMS: Double?
    var timeToPrerollReadyMS: Double?
    var timeFromPrerollReadyToDrainMS: Double?
    var minQueuedAudioMS: Double?
    var maxQueuedAudioMS: Double?
    var avgQueuedAudioMS: Double?
    var queueDepthSampleCount: Double?
    var rebufferEventCount: Double?
    var rebufferTotalDurationMS: Double?
    var longestRebufferDurationMS: Double?
    var starvationEventCount: Double?
    var scheduleCallbackCount: Double?
    var playedBackCallbackCount: Double?
    var fadeInChunkCount: Double?
    var maxInterChunkGapMS: Double?
    var avgInterChunkGapMS: Double?
    var maxScheduleGapMS: Double?
    var avgScheduleGapMS: Double?
    var maxBoundaryDiscontinuity: Double?
    var maxLeadingAbsAmplitude: Double?
    var maxTrailingAbsAmplitude: Double?
}

struct BenchmarkPlaybackMetricAggregate: Codable {
    let sampleCount: Int
    let startupBufferedAudioMS: BenchmarkMetricSummary
    let timeToFirstChunkMS: BenchmarkMetricSummary
    let timeToPrerollReadyMS: BenchmarkMetricSummary
    let timeFromPrerollReadyToDrainMS: BenchmarkMetricSummary
    let minQueuedAudioMS: BenchmarkMetricSummary
    let maxQueuedAudioMS: BenchmarkMetricSummary
    let avgQueuedAudioMS: BenchmarkMetricSummary
    let queueDepthSampleCount: BenchmarkMetricSummary
    let rebufferEventCount: BenchmarkMetricSummary
    let rebufferTotalDurationMS: BenchmarkMetricSummary
    let longestRebufferDurationMS: BenchmarkMetricSummary
    let starvationEventCount: BenchmarkMetricSummary
    let scheduleCallbackCount: BenchmarkMetricSummary
    let playedBackCallbackCount: BenchmarkMetricSummary
    let fadeInChunkCount: BenchmarkMetricSummary
    let maxInterChunkGapMS: BenchmarkMetricSummary
    let avgInterChunkGapMS: BenchmarkMetricSummary
    let maxScheduleGapMS: BenchmarkMetricSummary
    let avgScheduleGapMS: BenchmarkMetricSummary
    let maxBoundaryDiscontinuity: BenchmarkMetricSummary
    let maxLeadingAbsAmplitude: BenchmarkMetricSummary
    let maxTrailingAbsAmplitude: BenchmarkMetricSummary

    static func make(from samples: [BenchmarkPlaybackMetrics]) -> Self {
        Self(
            sampleCount: samples.count,
            startupBufferedAudioMS: .make(from: samples.compactMap(\.startupBufferedAudioMS)),
            timeToFirstChunkMS: .make(from: samples.compactMap(\.timeToFirstChunkMS)),
            timeToPrerollReadyMS: .make(from: samples.compactMap(\.timeToPrerollReadyMS)),
            timeFromPrerollReadyToDrainMS: .make(from: samples.compactMap(\.timeFromPrerollReadyToDrainMS)),
            minQueuedAudioMS: .make(from: samples.compactMap(\.minQueuedAudioMS)),
            maxQueuedAudioMS: .make(from: samples.compactMap(\.maxQueuedAudioMS)),
            avgQueuedAudioMS: .make(from: samples.compactMap(\.avgQueuedAudioMS)),
            queueDepthSampleCount: .make(from: samples.compactMap(\.queueDepthSampleCount)),
            rebufferEventCount: .make(from: samples.compactMap(\.rebufferEventCount)),
            rebufferTotalDurationMS: .make(from: samples.compactMap(\.rebufferTotalDurationMS)),
            longestRebufferDurationMS: .make(from: samples.compactMap(\.longestRebufferDurationMS)),
            starvationEventCount: .make(from: samples.compactMap(\.starvationEventCount)),
            scheduleCallbackCount: .make(from: samples.compactMap(\.scheduleCallbackCount)),
            playedBackCallbackCount: .make(from: samples.compactMap(\.playedBackCallbackCount)),
            fadeInChunkCount: .make(from: samples.compactMap(\.fadeInChunkCount)),
            maxInterChunkGapMS: .make(from: samples.compactMap(\.maxInterChunkGapMS)),
            avgInterChunkGapMS: .make(from: samples.compactMap(\.avgInterChunkGapMS)),
            maxScheduleGapMS: .make(from: samples.compactMap(\.maxScheduleGapMS)),
            avgScheduleGapMS: .make(from: samples.compactMap(\.avgScheduleGapMS)),
            maxBoundaryDiscontinuity: .make(from: samples.compactMap(\.maxBoundaryDiscontinuity)),
            maxLeadingAbsAmplitude: .make(from: samples.compactMap(\.maxLeadingAbsAmplitude)),
            maxTrailingAbsAmplitude: .make(from: samples.compactMap(\.maxTrailingAbsAmplitude)),
        )
    }
}

final class BenchmarkLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stderrObjects = [[String: Any]]()

    private static func double(_ value: Any?) -> Double? {
        switch value {
            case let int as Int:
                Double(int)
            case let double as Double:
                double
            case let number as NSNumber:
                number.doubleValue
            default:
                nil
        }
    }

    func appendStderr(_ message: String) {
        let lines = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        guard !lines.isEmpty else { return }

        lock.withLock {
            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                guard
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }

                stderrObjects.append(object)
            }
        }
    }

    func playbackMetrics(for requestID: String) -> BenchmarkPlaybackMetrics? {
        lock.withLock {
            guard let object = stderrObjects.last(where: {
                $0["event"] as? String == "playback_finished"
                    && $0["request_id"] as? String == requestID
            }) else {
                return nil
            }
            guard let details = object["details"] as? [String: Any] else {
                return nil
            }

            return BenchmarkPlaybackMetrics(
                startupBufferedAudioMS: Self.double(details["startup_buffered_audio_ms"]),
                timeToFirstChunkMS: Self.double(details["time_to_first_chunk_ms"]),
                timeToPrerollReadyMS: Self.double(details["time_to_preroll_ready_ms"]),
                timeFromPrerollReadyToDrainMS: Self.double(details["time_from_preroll_ready_to_drain_ms"]),
                minQueuedAudioMS: Self.double(details["min_queued_audio_ms"]),
                maxQueuedAudioMS: Self.double(details["max_queued_audio_ms"]),
                avgQueuedAudioMS: Self.double(details["avg_queued_audio_ms"]),
                queueDepthSampleCount: Self.double(details["queue_depth_sample_count"]),
                rebufferEventCount: Self.double(details["rebuffer_event_count"]),
                rebufferTotalDurationMS: Self.double(details["rebuffer_total_duration_ms"]),
                longestRebufferDurationMS: Self.double(details["longest_rebuffer_duration_ms"]),
                starvationEventCount: Self.double(details["starvation_event_count"]),
                scheduleCallbackCount: Self.double(details["schedule_callback_count"]),
                playedBackCallbackCount: Self.double(details["played_back_callback_count"]),
                fadeInChunkCount: Self.double(details["fade_in_chunk_count"]),
                maxInterChunkGapMS: Self.double(details["max_inter_chunk_gap_ms"]),
                avgInterChunkGapMS: Self.double(details["avg_inter_chunk_gap_ms"]),
                maxScheduleGapMS: Self.double(details["max_schedule_gap_ms"]),
                avgScheduleGapMS: Self.double(details["avg_schedule_gap_ms"]),
                maxBoundaryDiscontinuity: Self.double(details["max_boundary_discontinuity"]),
                maxLeadingAbsAmplitude: Self.double(details["max_leading_abs_amplitude"]),
                maxTrailingAbsAmplitude: Self.double(details["max_trailing_abs_amplitude"]),
            )
        }
    }
}

enum BenchmarkHarness {
    static func effectivePlaybackMode() -> BenchmarkPlaybackMode {
        speakSwiftlyBackendBenchmarkAudibleEnabled() ? .audible : .silent
    }

    static func withBenchmarkRuntime<T>(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
        qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy = .dualResidentSerialized,
        playbackMode: BenchmarkPlaybackMode = .silent,
        playbackTrace: Bool = false,
        operation: @escaping @Sendable (BenchmarkRuntimeSession) async throws -> T,
    ) async throws -> T {
        let session = try await makeBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: backend,
            qwenConditioningStrategy: qwenConditioningStrategy,
            marvisResidentPolicy: marvisResidentPolicy,
            playbackMode: playbackMode,
            playbackTrace: playbackTrace,
        )

        do {
            let result = try await operation(session)
            await session.runtime.shutdown()
            return result
        } catch {
            await session.runtime.shutdown()
            throw error
        }
    }

    static func makeBenchmarkRuntime(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
        qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy,
        playbackMode: BenchmarkPlaybackMode,
        playbackTrace: Bool,
    ) async throws -> BenchmarkRuntimeSession {
        _ = try SpeakSwiftly.SupportResources.mlxBundleURL()
        _ = try SpeakSwiftly.SupportResources.defaultMetallibURL()

        let liveDependencies = WorkerDependencies.live()
        let logRecorder = BenchmarkLogRecorder()
        let signposts = BenchmarkSignpostRecorder(
            backend: backend,
            playbackMode: playbackMode,
        )
        let dependencies = WorkerDependencies(
            fileManager: liveDependencies.fileManager,
            loadResidentModels: liveDependencies.loadResidentModels,
            loadProfileModel: liveDependencies.loadProfileModel,
            loadCloneTranscriptionModel: liveDependencies.loadCloneTranscriptionModel,
            makePlaybackDriver: {
                switch playbackMode {
                    case .silent:
                        .silent(traceEnabled: playbackTrace)
                    case .audible:
                        AnyPlaybackDriver(AudioPlaybackDriver(traceEnabled: playbackTrace))
                }
            },
            writeWAV: liveDependencies.writeWAV,
            loadAudioSamples: liveDependencies.loadAudioSamples,
            loadAudioFloats: liveDependencies.loadAudioFloats,
            writeStderr: { message in
                logRecorder.appendStderr(message)
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
            persistenceURL: ProfileStore.defaultTextProfilesURL(
                fileManager: dependencies.fileManager,
                stateRootOverride: profileRootURL.path,
            ),
        )
        let playbackQueue = await PlaybackQueue(driver: dependencies.makePlaybackDriver())

        let runtime = SpeakSwiftly.Runtime(
            dependencies: dependencies,
            speechBackend: backend,
            qwenConditioningStrategy: qwenConditioningStrategy,
            marvisResidentPolicy: marvisResidentPolicy,
            profileStore: profileStore,
            generatedFileStore: generatedFileStore,
            generationJobStore: generationJobStore,
            normalizer: normalizer,
            playbackQueue: playbackQueue,
        )
        await runtime.installPlaybackHooks()
        return BenchmarkRuntimeSession(
            runtime: runtime,
            logRecorder: logRecorder,
            signposts: signposts,
        )
    }

    static func awaitResidentReady(
        on runtime: SpeakSwiftly.Runtime,
        signposts: BenchmarkSignpostRecorder,
    ) async throws -> Double {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let updates = await runtime.updates()
        let interval = signposts.beginResidentPreload()
        defer { interval.end() }

        await runtime.start()

        for await update in updates {
            switch update.state {
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
    ) async throws -> SpeakSwiftly.RequestCompletion {
        try await handle.completion()
    }

    static func runRequestBenchmark(
        handle: SpeakSwiftly.RequestHandle,
        signposts: BenchmarkSignpostRecorder,
        logRecorder: BenchmarkLogRecorder? = nil,
    ) async throws -> BenchmarkRequest {
        let clock = ContinuousClock()
        let submittedAt = clock.now
        let requestInterval = signposts.beginRequest()
        defer { requestInterval.end() }
        let submittedSnapshot = resourceSnapshot(
            label: "request_submitted",
            submittedAt: submittedAt,
            clock: clock,
        )

        async let lifecycle = collectLifecycleMetrics(
            from: handle.events,
            submittedAt: submittedAt,
            clock: clock,
            signposts: signposts,
            signpostID: requestInterval.id,
        )
        async let generation = collectGenerationMetrics(
            from: handle.synthesisUpdates,
            submittedAt: submittedAt,
            clock: clock,
            signposts: signposts,
            signpostID: requestInterval.id,
        )

        let (lifecycleMetrics, success, lifecycleSnapshots) = try await lifecycle
        let (generationMetrics, generationSnapshots) = try await generation
        let resourceMetrics = BenchmarkRequestResourceMetrics.make(
            from: [submittedSnapshot] + lifecycleSnapshots + generationSnapshots,
        )
        let playbackMetrics = try await awaitPlaybackMetrics(
            for: handle.id,
            operation: handle.kind.rawValue,
            logRecorder: logRecorder,
        )

        return BenchmarkRequest(
            requestID: handle.id,
            operation: handle.kind.rawValue,
            generatedArtifactID: generatedArtifactID(from: success),
            lifecycle: lifecycleMetrics,
            generation: generationMetrics,
            resources: resourceMetrics,
            playback: playbackMetrics,
        )
    }

    static func writeSummary(
        _ summary: some Encodable,
        timestampedStem: String,
        latestFilename: String,
        generatedAt: Date,
    ) throws -> URL {
        let benchmarksRoot = try packageRootURL()
            .appendingPathComponent(".local/benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: benchmarksRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        let summaryURL = benchmarksRoot.appendingPathComponent("\(timestampedStem)-\(stamp).json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(summary)
        try encoded.write(to: summaryURL, options: .atomic)

        let latestSummaryURL = benchmarksRoot.appendingPathComponent(latestFilename, isDirectory: false)
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
                throw BenchmarkError("The SpeakSwiftly benchmark harness could not find the package root while walking upward from '\(#filePath)'.")
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

    private static func generatedArtifactID(from completion: SpeakSwiftly.RequestCompletion) -> String? {
        if case let .artifact(file) = completion {
            return file.artifactID
        }
        return nil
    }

    private static func collectLifecycleMetrics(
        from events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, any Swift.Error>,
        submittedAt: ContinuousClock.Instant,
        clock: ContinuousClock,
        signposts: BenchmarkSignpostRecorder,
        signpostID: OSSignpostID,
    ) async throws -> (BenchmarkRequestLifecycleMetrics, SpeakSwiftly.RequestCompletion, [BenchmarkResourceSnapshot]) {
        var metrics = BenchmarkRequestLifecycleMetrics()
        var resourceSnapshots = [BenchmarkResourceSnapshot]()

        for try await event in events {
            let elapsedMS = milliseconds(since: submittedAt, clock: clock)

            switch event {
                case let .queued(queued):
                    metrics.queuedAtMS = metrics.queuedAtMS ?? elapsedMS
                    metrics.queueReason = queued.reason.rawValue
                    metrics.queuePosition = queued.queuePosition
                    signposts.emitQueued(id: signpostID)
                    resourceSnapshots.append(resourceSnapshot(label: "queued", submittedAt: submittedAt, clock: clock))
                case .acknowledged:
                    metrics.acknowledgedAtMS = metrics.acknowledgedAtMS ?? elapsedMS
                    signposts.emitAcknowledged(id: signpostID)
                    resourceSnapshots.append(resourceSnapshot(label: "acknowledged", submittedAt: submittedAt, clock: clock))
                case .started:
                    metrics.startedAtMS = metrics.startedAtMS ?? elapsedMS
                    signposts.emitStarted(id: signpostID)
                    resourceSnapshots.append(resourceSnapshot(label: "started", submittedAt: submittedAt, clock: clock))
                case let .progress(progress):
                    switch progress.stage {
                        case .bufferingAudio:
                            metrics.bufferingAudioAtMS = metrics.bufferingAudioAtMS ?? elapsedMS
                            signposts.emitBufferingAudio(id: signpostID)
                            resourceSnapshots.append(resourceSnapshot(label: "buffering_audio", submittedAt: submittedAt, clock: clock))
                        case .prerollReady:
                            metrics.prerollReadyAtMS = metrics.prerollReadyAtMS ?? elapsedMS
                            signposts.emitPrerollReady(id: signpostID)
                            resourceSnapshots.append(resourceSnapshot(label: "preroll_ready", submittedAt: submittedAt, clock: clock))
                        case .playbackFinished:
                            metrics.playbackFinishedAtMS = metrics.playbackFinishedAtMS ?? elapsedMS
                            signposts.emitPlaybackFinished(id: signpostID)
                            resourceSnapshots.append(resourceSnapshot(label: "playback_finished", submittedAt: submittedAt, clock: clock))
                        default:
                            continue
                    }
                case let .completed(completion):
                    metrics.completedAtMS = metrics.completedAtMS ?? elapsedMS
                    signposts.emitCompleted(id: signpostID)
                    resourceSnapshots.append(resourceSnapshot(label: "completed", submittedAt: submittedAt, clock: clock))
                    return (metrics, completion, resourceSnapshots)
            }
        }

        throw BenchmarkError("A benchmark request stream ended before it reported terminal success.")
    }

    private static func collectGenerationMetrics(
        from events: AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error>,
        submittedAt: ContinuousClock.Instant,
        clock: ContinuousClock,
        signposts: BenchmarkSignpostRecorder,
        signpostID: OSSignpostID,
    ) async throws -> (BenchmarkRequestGenerationMetrics, [BenchmarkResourceSnapshot]) {
        var metrics = BenchmarkRequestGenerationMetrics()
        var resourceSnapshots = [BenchmarkResourceSnapshot]()

        for try await update in events {
            let elapsedMS = milliseconds(since: submittedAt, clock: clock)

            switch update.event {
                case .token:
                    if metrics.firstTokenAtMS == nil {
                        metrics.firstTokenAtMS = elapsedMS
                        signposts.emitFirstToken(id: signpostID)
                        resourceSnapshots.append(resourceSnapshot(label: "first_token", submittedAt: submittedAt, clock: clock))
                    }
                    metrics.observedTokenCount += 1
                case let .info(info):
                    metrics.infoAtMS = metrics.infoAtMS ?? elapsedMS
                    metrics.promptTokenCount = info.promptTokenCount
                    metrics.generationTokenCount = info.generationTokenCount
                    metrics.prefillTimeMS = info.prefillTime * 1000
                    metrics.generateTimeMS = info.generateTime * 1000
                    metrics.tokensPerSecond = info.tokensPerSecond
                    metrics.peakMemoryUsageGB = info.peakMemoryUsage
                    signposts.emitGenerationInfo(id: signpostID)
                    resourceSnapshots.append(resourceSnapshot(label: "generation_info", submittedAt: submittedAt, clock: clock))
                case let .audioChunk(sampleCount):
                    if metrics.firstAudioChunkAtMS == nil {
                        metrics.firstAudioChunkAtMS = elapsedMS
                        signposts.emitFirstAudioChunk(id: signpostID)
                        resourceSnapshots.append(resourceSnapshot(label: "first_audio_chunk", submittedAt: submittedAt, clock: clock))
                    }
                    metrics.audioChunkCount += 1
                    metrics.totalAudioSampleCount += sampleCount
            }
        }

        return (metrics, resourceSnapshots)
    }

    private static func resourceSnapshot(
        label: String,
        submittedAt: ContinuousClock.Instant,
        clock: ContinuousClock,
    ) -> BenchmarkResourceSnapshot {
        let mlxSnapshot = Memory.snapshot()
        var usage = rusage_info_current()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rebound)
            }
        }

        return BenchmarkResourceSnapshot(
            label: label,
            elapsedMS: milliseconds(since: submittedAt, clock: clock),
            processResidentBytes: usageResult == 0 ? Int(usage.ri_resident_size) : nil,
            processPhysFootprintBytes: usageResult == 0 ? Int(usage.ri_phys_footprint) : nil,
            processUserCPUTimeNS: usageResult == 0 ? Int(usage.ri_user_time) : nil,
            processSystemCPUTimeNS: usageResult == 0 ? Int(usage.ri_system_time) : nil,
            mlxActiveMemoryBytes: mlxSnapshot.activeMemory,
            mlxCacheMemoryBytes: mlxSnapshot.cacheMemory,
            mlxPeakMemoryBytes: mlxSnapshot.peakMemory,
            mlxCacheLimitBytes: Memory.cacheLimit,
            mlxMemoryLimitBytes: Memory.memoryLimit,
        )
    }

    private static func awaitPlaybackMetrics(
        for requestID: String,
        operation: String,
        logRecorder: BenchmarkLogRecorder?,
    ) async throws -> BenchmarkPlaybackMetrics? {
        guard operation == "generate_speech" else { return nil }
        guard let logRecorder else { return nil }

        for _ in 0..<40 {
            if let metrics = logRecorder.playbackMetrics(for: requestID) {
                return metrics
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw BenchmarkError("Benchmark harness did not observe a playback_finished summary for request '\(requestID)'.")
    }
}

struct BenchmarkError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
