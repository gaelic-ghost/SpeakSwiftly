#if os(macOS)
import Foundation
import os
@testable import SpeakSwiftly

struct BenchmarkRuntimeSession {
    let runtime: SpeakSwiftly.Runtime
    let logRecorder: BenchmarkLogRecorder
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

struct BenchmarkResourceSnapshot: Codable {
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let processCPUTimeMS: Double?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
}

struct BenchmarkWarningSummary: Codable {
    let warningCount: Int
    let playbackWarningCount: Int
    let generationQualityWarningCount: Int
    let reasons: [String: Int]
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
    let playback: BenchmarkPlaybackMetrics?
}

struct BenchmarkRequestAggregate: Codable {
    let sampleCount: Int
    let lifecycle: BenchmarkLifecycleMetricAggregate
    let generation: BenchmarkGenerationMetricAggregate
    let playback: BenchmarkPlaybackMetricAggregate

    static func make(from samples: [BenchmarkRequest]) -> Self {
        Self(
            sampleCount: samples.count,
            lifecycle: .make(from: samples.map(\.lifecycle)),
            generation: .make(from: samples.map(\.generation)),
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

    private static func int(_ value: Any?) -> Int? {
        switch value {
            case let int as Int:
                int
            case let double as Double:
                Int(double)
            case let number as NSNumber:
                number.intValue
            default:
                nil
        }
    }

    private static func max(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
            case let (lhs?, rhs?):
                Swift.max(lhs, rhs)
            case let (lhs?, nil):
                lhs
            case let (nil, rhs?):
                rhs
            case (nil, nil):
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

    func warningSummary(for requestID: String) -> BenchmarkWarningSummary {
        warningSummary(for: [requestID])
    }

    func warningSummary(for requestIDs: [String]) -> BenchmarkWarningSummary {
        let requestIDSet = Set(requestIDs)
        return lock.withLock {
            var reasons = [String: Int]()
            var warningCount = 0
            var playbackWarningCount = 0
            var generationQualityWarningCount = 0

            for object in stderrObjects where requestIDSet.contains(object["request_id"] as? String ?? "") {
                guard object["level"] as? String == "warning" else { continue }

                warningCount += 1
                let event = object["event"] as? String ?? "unknown"
                if event.hasPrefix("playback_") {
                    playbackWarningCount += 1
                }
                if event == "playback_generation_quality_warning" {
                    generationQualityWarningCount += 1
                }

                let details = object["details"] as? [String: Any]
                let reason = details?["reason"] as? String ?? event
                reasons[reason, default: 0] += 1
            }

            return BenchmarkWarningSummary(
                warningCount: warningCount,
                playbackWarningCount: playbackWarningCount,
                generationQualityWarningCount: generationQualityWarningCount,
                reasons: reasons,
            )
        }
    }

    func peakResourceSnapshot() -> BenchmarkResourceSnapshot {
        lock.withLock {
            var processResidentBytes: Int?
            var processPhysFootprintBytes: Int?
            var processCPUTimeNS: Int?
            var mlxActiveMemoryBytes: Int?
            var mlxCacheMemoryBytes: Int?
            var mlxPeakMemoryBytes: Int?

            for object in stderrObjects {
                guard let details = object["details"] as? [String: Any] else { continue }

                processResidentBytes = Self.max(processResidentBytes, Self.int(details["process_resident_bytes"]))
                processPhysFootprintBytes = Self.max(processPhysFootprintBytes, Self.int(details["process_phys_footprint_bytes"]))
                let userCPUTimeNS = Self.int(details["process_user_cpu_time_ns"]) ?? 0
                let systemCPUTimeNS = Self.int(details["process_system_cpu_time_ns"]) ?? 0
                if userCPUTimeNS > 0 || systemCPUTimeNS > 0 {
                    processCPUTimeNS = Self.max(processCPUTimeNS, userCPUTimeNS + systemCPUTimeNS)
                }
                mlxActiveMemoryBytes = Self.max(mlxActiveMemoryBytes, Self.int(details["mlx_active_memory_bytes"]))
                mlxCacheMemoryBytes = Self.max(mlxCacheMemoryBytes, Self.int(details["mlx_cache_memory_bytes"]))
                mlxPeakMemoryBytes = Self.max(mlxPeakMemoryBytes, Self.int(details["mlx_peak_memory_bytes"]))
            }

            return BenchmarkResourceSnapshot(
                processResidentBytes: processResidentBytes,
                processPhysFootprintBytes: processPhysFootprintBytes,
                processCPUTimeMS: processCPUTimeNS.map { Double($0) / 1_000_000 },
                mlxActiveMemoryBytes: mlxActiveMemoryBytes,
                mlxCacheMemoryBytes: mlxCacheMemoryBytes,
                mlxPeakMemoryBytes: mlxPeakMemoryBytes,
            )
        }
    }
}

enum BenchmarkHarness {
    static func effectivePlaybackMode() -> BenchmarkPlaybackMode {
        speakSwiftlyAudibleE2ETestsEnabled() ? .audible : .silent
    }

    static func withBenchmarkRuntime<T>(
        profileRootURL: URL,
        backend: SpeakSwiftly.SpeechBackend,
        qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy,
        playbackMode: BenchmarkPlaybackMode = .silent,
        playbackTrace: Bool = false,
        operation: @escaping @Sendable (BenchmarkRuntimeSession) async throws -> T,
    ) async throws -> T {
        let session = try await makeBenchmarkRuntime(
            profileRootURL: profileRootURL,
            backend: backend,
            qwenConditioningStrategy: qwenConditioningStrategy,
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
        playbackMode: BenchmarkPlaybackMode,
        playbackTrace: Bool,
    ) async throws -> BenchmarkRuntimeSession {
        _ = try SpeakSwiftly.SupportResources.mlxBundleURL()
        _ = try SpeakSwiftly.SupportResources.defaultMetallibURL()

        let liveDependencies = WorkerDependencies.live()
        let logRecorder = BenchmarkLogRecorder()
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
            writeSystemLog: liveDependencies.writeSystemLog,
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
            profileStore: profileStore,
            generatedFileStore: generatedFileStore,
            generationJobStore: generationJobStore,
            normalizer: normalizer,
            playbackQueue: playbackQueue,
        )
        await runtime.installPlaybackHooks()
        return BenchmarkRuntimeSession(runtime: runtime, logRecorder: logRecorder)
    }

    static func awaitResidentReady(on runtime: SpeakSwiftly.Runtime) async throws -> Double {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let updates = await runtime.updates()

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
        logRecorder: BenchmarkLogRecorder? = nil,
        signposts: BenchmarkSignpostRecorder? = nil,
    ) async throws -> BenchmarkRequest {
        let clock = ContinuousClock()
        let submittedAt = clock.now
        let signpostInterval = signposts?.beginRequest()

        async let lifecycle = collectLifecycleMetrics(
            from: handle.events,
            submittedAt: submittedAt,
            clock: clock,
            signposts: signposts,
            signpostID: signpostInterval?.id,
        )
        async let generation = collectGenerationMetrics(
            from: handle.synthesisUpdates,
            submittedAt: submittedAt,
            clock: clock,
            signposts: signposts,
            signpostID: signpostInterval?.id,
        )

        let (lifecycleMetrics, success) = try await lifecycle
        let generationMetrics = try await generation
        let playbackMetrics = try await awaitPlaybackMetrics(
            for: handle.id,
            operation: handle.kind.rawValue,
            logRecorder: logRecorder,
        )
        signpostInterval?.end()

        return BenchmarkRequest(
            requestID: handle.id,
            operation: handle.kind.rawValue,
            generatedArtifactID: generatedArtifactID(from: success),
            lifecycle: lifecycleMetrics,
            generation: generationMetrics,
            playback: playbackMetrics,
        )
    }

    static func writeSummary(
        _ summary: some Encodable,
        timestampedStem: String,
        latestFilename: String,
        generatedAt: Date,
        subdirectory: String? = nil,
    ) throws -> URL {
        var benchmarksRoot = try packageRootURL()
            .appendingPathComponent(".local/benchmarks", isDirectory: true)
        if let subdirectory, !subdirectory.isEmpty {
            benchmarksRoot = benchmarksRoot.appendingPathComponent(subdirectory, isDirectory: true)
        }
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
        signposts: BenchmarkSignpostRecorder?,
        signpostID: OSSignpostID?,
    ) async throws -> (BenchmarkRequestLifecycleMetrics, SpeakSwiftly.RequestCompletion) {
        var metrics = BenchmarkRequestLifecycleMetrics()

        for try await event in events {
            let elapsedMS = milliseconds(since: submittedAt, clock: clock)

            switch event {
                case let .queued(queued):
                    metrics.queuedAtMS = metrics.queuedAtMS ?? elapsedMS
                    metrics.queueReason = queued.reason.rawValue
                    metrics.queuePosition = queued.queuePosition
                    if let signpostID { signposts?.emitQueued(id: signpostID) }
                case .acknowledged:
                    metrics.acknowledgedAtMS = metrics.acknowledgedAtMS ?? elapsedMS
                    if let signpostID { signposts?.emitAcknowledged(id: signpostID) }
                case .started:
                    metrics.startedAtMS = metrics.startedAtMS ?? elapsedMS
                    if let signpostID { signposts?.emitStarted(id: signpostID) }
                case let .progress(progress):
                    switch progress.stage {
                        case .bufferingAudio:
                            metrics.bufferingAudioAtMS = metrics.bufferingAudioAtMS ?? elapsedMS
                        case .prerollReady:
                            metrics.prerollReadyAtMS = metrics.prerollReadyAtMS ?? elapsedMS
                            if let signpostID { signposts?.emitPrerollReady(id: signpostID) }
                        case .playbackFinished:
                            metrics.playbackFinishedAtMS = metrics.playbackFinishedAtMS ?? elapsedMS
                            if let signpostID { signposts?.emitPlaybackFinished(id: signpostID) }
                        default:
                            continue
                    }
                case let .completed(completion):
                    metrics.completedAtMS = metrics.completedAtMS ?? elapsedMS
                    if let signpostID { signposts?.emitCompleted(id: signpostID) }
                    return (metrics, completion)
            }
        }

        throw BenchmarkError("A benchmark request stream ended before it reported terminal success.")
    }

    private static func collectGenerationMetrics(
        from events: AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error>,
        submittedAt: ContinuousClock.Instant,
        clock: ContinuousClock,
        signposts: BenchmarkSignpostRecorder?,
        signpostID: OSSignpostID?,
    ) async throws -> BenchmarkRequestGenerationMetrics {
        var metrics = BenchmarkRequestGenerationMetrics()

        for try await update in events {
            let elapsedMS = milliseconds(since: submittedAt, clock: clock)

            switch update.event {
                case .token:
                    if metrics.firstTokenAtMS == nil, let signpostID {
                        signposts?.emitFirstToken(id: signpostID)
                    }
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
                    if metrics.firstAudioChunkAtMS == nil, let signpostID {
                        signposts?.emitFirstAudioChunk(id: signpostID)
                    }
                    metrics.firstAudioChunkAtMS = metrics.firstAudioChunkAtMS ?? elapsedMS
                    metrics.audioChunkCount += 1
                    metrics.totalAudioSampleCount += sampleCount
            }
        }

        return metrics
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
