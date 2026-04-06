@preconcurrency import AVFoundation
import CoreAudio
import Darwin
import Foundation
@preconcurrency import MLX
import MLXAudioCore
import TextForSpeech

// MARK: - Playback Environment

private enum WorkerEnvironment {
    static let silentPlayback = "SPEAKSWIFTLY_SILENT_PLAYBACK"
    static let playbackTrace = "SPEAKSWIFTLY_PLAYBACK_TRACE"
}

enum PlaybackEvent: Sendable {
    case firstChunk
    case prerollReady(startupBufferedAudioMS: Int, thresholds: PlaybackAdaptiveThresholds)
    case queueDepthLow(queuedAudioMS: Int)
    case rebufferStarted(queuedAudioMS: Int, thresholds: PlaybackAdaptiveThresholds)
    case rebufferResumed(bufferedAudioMS: Int, thresholds: PlaybackAdaptiveThresholds)
    case chunkGapWarning(gapMS: Int, chunkIndex: Int)
    case scheduleGapWarning(gapMS: Int, bufferIndex: Int, queuedAudioMS: Int)
    case rebufferThrashWarning(rebufferEventCount: Int, windowMS: Int)
    case outputDeviceChanged(previousDevice: String?, currentDevice: String?)
    case engineConfigurationChanged(engineIsRunning: Bool)
    case bufferShapeSummary(
        maxBoundaryDiscontinuity: Double,
        maxLeadingAbsAmplitude: Double,
        maxTrailingAbsAmplitude: Double,
        fadeInChunkCount: Int
    )
    case trace(PlaybackTraceEvent)
    case starved
}

struct PlaybackTraceEvent: Sendable {
    let name: String
    let chunkIndex: Int?
    let bufferIndex: Int?
    let sampleCount: Int?
    let durationMS: Int?
    let queuedAudioBeforeMS: Int?
    let queuedAudioAfterMS: Int?
    let gapMS: Int?
    let isRebuffering: Bool?
    let fadeInApplied: Bool?
}

enum PlaybackComplexityClass: String, Sendable {
    case compact
    case balanced
    case extended
}

struct PlaybackAdaptiveThresholds: Sendable, Equatable {
    let complexityClass: PlaybackComplexityClass
    let startupBufferTargetMS: Int
    let lowWaterTargetMS: Int
    let resumeBufferTargetMS: Int
    let chunkGapWarningMS: Int
    let scheduleGapWarningMS: Int
}

enum PlaybackPhase: String, Sendable {
    case warmup
    case steady
    case recovery
}

struct PlaybackThresholdController: Sendable {
    private static let codecTokenRateHz = 12.5
    private static let adaptationSampleCount = 6
    private static let warmupStableChunkRequirement = 6
    private static let recoveryStableChunkRequirement = 4
    private static let maxStartupBufferTargetMS = 20_000
    private static let maxResumeBufferTargetMS = 24_000
    private static let maxLowWaterTargetMS = 12_000
    private static let maxChunkGapWarningMS = 1_200
    private static let maxScheduleGapWarningMS = 900

    private(set) var thresholds: PlaybackAdaptiveThresholds
    private(set) var phase: PlaybackPhase = .warmup
    private var chunkDurationsMS = [Int]()
    private var interChunkGapsMS = [Int]()
    private var rebufferCount = 0
    private var starvationCount = 0
    private var stableChunkStreak = 0
    private var startupBufferFloorMS: Int
    private var lowWaterFloorMS: Int
    private var resumeBufferFloorMS: Int
    private var chunkGapWarningFloorMS: Int
    private var scheduleGapWarningFloorMS: Int

    init(text: String) {
        thresholds = Self.seedThresholds(for: text)
        startupBufferFloorMS = thresholds.startupBufferTargetMS
        lowWaterFloorMS = thresholds.lowWaterTargetMS
        resumeBufferFloorMS = thresholds.resumeBufferTargetMS
        chunkGapWarningFloorMS = thresholds.chunkGapWarningMS
        scheduleGapWarningFloorMS = thresholds.scheduleGapWarningMS
    }

    mutating func recordChunk(durationMS: Int, interChunkGapMS: Int?) {
        chunkDurationsMS.append(durationMS)
        if chunkDurationsMS.count > Self.adaptationSampleCount {
            chunkDurationsMS.removeFirst()
        }

        if let interChunkGapMS {
            interChunkGapsMS.append(interChunkGapMS)
            if interChunkGapsMS.count > Self.adaptationSampleCount {
                interChunkGapsMS.removeFirst()
            }
        }

        guard
            let avgChunkDurationMS = average(chunkDurationsMS),
            let avgInterChunkGapMS = average(interChunkGapsMS)
        else {
            return
        }

        let maxInterChunkGapMS = interChunkGapsMS.max() ?? avgInterChunkGapMS
        let jitterMS = max(maxInterChunkGapMS - avgInterChunkGapMS, 0)
        let cadenceDeficitMS = max(avgInterChunkGapMS - avgChunkDurationMS, 0)
        updatePhase(
            latestInterChunkGapMS: interChunkGapMS,
            avgChunkDurationMS: avgChunkDurationMS,
            avgInterChunkGapMS: avgInterChunkGapMS,
            jitterMS: jitterMS,
            cadenceDeficitMS: cadenceDeficitMS
        )

        let seeded = Self.seededThresholds(for: thresholds.complexityClass, phase: phase)
        let phaseMargins = phaseAdaptiveMargins(
            for: phase,
            avgChunkDurationMS: avgChunkDurationMS,
            avgInterChunkGapMS: avgInterChunkGapMS,
            cadenceDeficitMS: cadenceDeficitMS
        )
        let startupBufferTargetMS = min(
            Self.maxStartupBufferTargetMS,
            max(
                startupBufferFloorMS,
                seeded.startupBufferTargetMS,
                Int((Double(avgInterChunkGapMS) * 2.2).rounded())
                    + avgChunkDurationMS
                    + jitterMS
                    + cadenceDeficitMS * 4
                    + phaseMargins.startupBufferMS
            )
        )
        let lowWaterTargetMS = min(
            Self.maxLowWaterTargetMS,
            max(
                lowWaterFloorMS,
                seeded.lowWaterTargetMS,
                avgInterChunkGapMS
                    + max(jitterMS, avgChunkDurationMS / 2)
                    + cadenceDeficitMS * 2
                    + phaseMargins.lowWaterMS
            )
        )
        let resumeBufferTargetMS = min(
            Self.maxResumeBufferTargetMS,
            max(
                resumeBufferFloorMS,
                seeded.resumeBufferTargetMS,
                startupBufferTargetMS,
                lowWaterTargetMS
                    + max(avgChunkDurationMS * 2, avgInterChunkGapMS)
                    + cadenceDeficitMS * 4
                    + phaseMargins.resumeBufferMS
            )
        )
        let chunkGapWarningMS = min(
            Self.maxChunkGapWarningMS,
            max(chunkGapWarningFloorMS, seeded.chunkGapWarningMS, avgInterChunkGapMS + avgChunkDurationMS)
        )
        let scheduleGapWarningMS = min(
            Self.maxScheduleGapWarningMS,
            max(scheduleGapWarningFloorMS, seeded.scheduleGapWarningMS, avgInterChunkGapMS - max(avgChunkDurationMS / 4, 8))
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: chunkGapWarningMS,
                scheduleGapWarningMS: scheduleGapWarningMS
            ),
            preserveFloors: false
        )
    }

    mutating func recordStarvation() {
        starvationCount += 1
        phase = .recovery
        stableChunkStreak = 0

        let avgChunkDurationMS = average(chunkDurationsMS) ?? Self.defaultChunkDurationMS
        let avgInterChunkGapMS = average(interChunkGapsMS) ?? max(avgChunkDurationMS, Self.defaultChunkDurationMS)
        let resumeBufferTargetMS = min(
            Self.maxResumeBufferTargetMS,
            max(
                thresholds.resumeBufferTargetMS,
                avgInterChunkGapMS * (3 + starvationCount),
                avgChunkDurationMS * (4 + starvationCount)
            )
        )
        let lowWaterTargetMS = min(
            Self.maxLowWaterTargetMS,
            max(
                thresholds.lowWaterTargetMS,
                resumeBufferTargetMS - max(avgChunkDurationMS * 2, avgInterChunkGapMS)
            )
        )
        let startupBufferTargetMS = min(
            Self.maxStartupBufferTargetMS,
            max(thresholds.startupBufferTargetMS, resumeBufferTargetMS)
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: thresholds.chunkGapWarningMS,
                scheduleGapWarningMS: thresholds.scheduleGapWarningMS
            ),
            preserveFloors: true
        )
    }

    mutating func recordRebuffer() {
        rebufferCount += 1
        if phase != .recovery {
            phase = .recovery
        }
        stableChunkStreak = 0

        guard rebufferCount >= 2 else { return }

        let avgChunkDurationMS = average(chunkDurationsMS) ?? Self.defaultChunkDurationMS
        let avgInterChunkGapMS = average(interChunkGapsMS) ?? max(avgChunkDurationMS, Self.defaultChunkDurationMS)
        let maxInterChunkGapMS = interChunkGapsMS.max() ?? avgInterChunkGapMS
        let jitterMS = max(maxInterChunkGapMS - avgInterChunkGapMS, 0)
        let cadenceDeficitMS = max(avgInterChunkGapMS - avgChunkDurationMS, 0)
        let rebufferPenaltyMS = max(avgChunkDurationMS / 2, 40) * (rebufferCount - 1)
        let repeatedRebufferMargins = (
            startupBufferMS: max(rebufferPenaltyMS * 8, avgChunkDurationMS),
            lowWaterMS: max(rebufferPenaltyMS * 3, avgChunkDurationMS / 2),
            resumeBufferMS: max(rebufferPenaltyMS * 4, avgChunkDurationMS)
        )

        let startupBufferTargetMS = min(
            Self.maxStartupBufferTargetMS,
            max(
                thresholds.startupBufferTargetMS,
                startupBufferFloorMS,
                avgInterChunkGapMS * 2
                    + avgChunkDurationMS
                    + jitterMS
                    + cadenceDeficitMS * 4
                    + repeatedRebufferMargins.startupBufferMS
            )
        )
        let lowWaterTargetMS = min(
            Self.maxLowWaterTargetMS,
            max(
                thresholds.lowWaterTargetMS,
                lowWaterFloorMS,
                avgInterChunkGapMS
                    + jitterMS
                    + max(avgChunkDurationMS / 2, 20)
                    + cadenceDeficitMS * 2
                    + repeatedRebufferMargins.lowWaterMS
            )
        )
        let resumeBufferTargetMS = min(
            Self.maxResumeBufferTargetMS,
            max(
                thresholds.resumeBufferTargetMS,
                resumeBufferFloorMS,
                startupBufferTargetMS,
                lowWaterTargetMS
                    + max(avgChunkDurationMS * 2, avgInterChunkGapMS)
                    + cadenceDeficitMS * 4
                    + repeatedRebufferMargins.resumeBufferMS
            )
        )
        let chunkGapWarningMS = min(
            Self.maxChunkGapWarningMS,
            max(
                thresholds.chunkGapWarningMS,
                chunkGapWarningFloorMS,
                avgInterChunkGapMS + avgChunkDurationMS + rebufferPenaltyMS
            )
        )
        let scheduleGapWarningMS = min(
            Self.maxScheduleGapWarningMS,
            max(
                thresholds.scheduleGapWarningMS,
                scheduleGapWarningFloorMS,
                avgInterChunkGapMS - max(avgChunkDurationMS / 4, 8) + max(rebufferPenaltyMS / 2, 12)
            )
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: chunkGapWarningMS,
                scheduleGapWarningMS: scheduleGapWarningMS
            ),
            preserveFloors: true
        )
    }

    private mutating func applyThresholds(_ thresholds: PlaybackAdaptiveThresholds, preserveFloors: Bool) {
        if preserveFloors {
            startupBufferFloorMS = max(startupBufferFloorMS, thresholds.startupBufferTargetMS)
            lowWaterFloorMS = max(lowWaterFloorMS, thresholds.lowWaterTargetMS)
            resumeBufferFloorMS = max(resumeBufferFloorMS, thresholds.resumeBufferTargetMS)
            chunkGapWarningFloorMS = max(chunkGapWarningFloorMS, thresholds.chunkGapWarningMS)
            scheduleGapWarningFloorMS = max(scheduleGapWarningFloorMS, thresholds.scheduleGapWarningMS)
        }

        self.thresholds = PlaybackAdaptiveThresholds(
            complexityClass: thresholds.complexityClass,
            startupBufferTargetMS: max(thresholds.startupBufferTargetMS, startupBufferFloorMS),
            lowWaterTargetMS: max(thresholds.lowWaterTargetMS, lowWaterFloorMS),
            resumeBufferTargetMS: max(thresholds.resumeBufferTargetMS, resumeBufferFloorMS),
            chunkGapWarningMS: max(thresholds.chunkGapWarningMS, chunkGapWarningFloorMS),
            scheduleGapWarningMS: max(thresholds.scheduleGapWarningMS, scheduleGapWarningFloorMS)
        )
    }

    private static var defaultChunkDurationMS: Int {
        Int((2.0 / codecTokenRateHz * 1_000).rounded())
    }

    private static func seedThresholds(for text: String) -> PlaybackAdaptiveThresholds {
        seededThresholds(for: classify(text: text), phase: .steady)
    }

    private static func seededThresholds(for complexityClass: PlaybackComplexityClass, phase: PlaybackPhase) -> PlaybackAdaptiveThresholds {
        let base = switch complexityClass {
        case .compact:
            PlaybackAdaptiveThresholds(
                complexityClass: .compact,
                startupBufferTargetMS: 360,
                lowWaterTargetMS: 140,
                resumeBufferTargetMS: 360,
                chunkGapWarningMS: 450,
                scheduleGapWarningMS: 180
            )
        case .balanced:
            PlaybackAdaptiveThresholds(
                complexityClass: .balanced,
                startupBufferTargetMS: 520,
                lowWaterTargetMS: 220,
                resumeBufferTargetMS: 520,
                chunkGapWarningMS: 520,
                scheduleGapWarningMS: 220
            )
        case .extended:
            PlaybackAdaptiveThresholds(
                complexityClass: .extended,
                startupBufferTargetMS: 12_800,
                lowWaterTargetMS: 4_800,
                resumeBufferTargetMS: 16_000,
                chunkGapWarningMS: 900,
                scheduleGapWarningMS: 400
            )
        }

        let phaseBias = phaseThresholdBias(for: complexityClass, phase: phase)
        return PlaybackAdaptiveThresholds(
            complexityClass: base.complexityClass,
            startupBufferTargetMS: min(Self.maxStartupBufferTargetMS, base.startupBufferTargetMS + phaseBias.startupBufferMS),
            lowWaterTargetMS: min(Self.maxLowWaterTargetMS, base.lowWaterTargetMS + phaseBias.lowWaterMS),
            resumeBufferTargetMS: min(Self.maxResumeBufferTargetMS, base.resumeBufferTargetMS + phaseBias.resumeBufferMS),
            chunkGapWarningMS: min(Self.maxChunkGapWarningMS, base.chunkGapWarningMS + phaseBias.chunkGapWarningMS),
            scheduleGapWarningMS: min(Self.maxScheduleGapWarningMS, base.scheduleGapWarningMS + phaseBias.scheduleGapWarningMS)
        )
    }

    private static func phaseThresholdBias(for complexityClass: PlaybackComplexityClass, phase: PlaybackPhase) -> (
        startupBufferMS: Int,
        lowWaterMS: Int,
        resumeBufferMS: Int,
        chunkGapWarningMS: Int,
        scheduleGapWarningMS: Int
    ) {
        switch (complexityClass, phase) {
        case (_, .steady):
            (0, 0, 0, 0, 0)
        case (.compact, .warmup):
            (120, 80, 180, 40, 20)
        case (.balanced, .warmup):
            (200, 120, 280, 50, 30)
        case (.extended, .warmup):
            (320, 200, 480, 60, 40)
        case (.compact, .recovery):
            (80, 60, 140, 30, 20)
        case (.balanced, .recovery):
            (140, 100, 220, 40, 30)
        case (.extended, .recovery):
            (220, 160, 360, 50, 40)
        }
    }

    private mutating func updatePhase(
        latestInterChunkGapMS: Int?,
        avgChunkDurationMS: Int,
        avgInterChunkGapMS: Int,
        jitterMS: Int,
        cadenceDeficitMS: Int
    ) {
        guard let latestInterChunkGapMS else { return }

        if isStableChunk(
            latestInterChunkGapMS: latestInterChunkGapMS,
            avgChunkDurationMS: avgChunkDurationMS,
            avgInterChunkGapMS: avgInterChunkGapMS,
            jitterMS: jitterMS,
            cadenceDeficitMS: cadenceDeficitMS
        ) {
            stableChunkStreak += 1
        } else {
            stableChunkStreak = 0
        }

        let requiredStableChunkCount = switch phase {
        case .warmup:
            Self.warmupStableChunkRequirement
        case .recovery:
            Self.recoveryStableChunkRequirement
        case .steady:
            Int.max
        }

        guard phase != .steady else { return }
        guard interChunkGapsMS.count >= Self.adaptationSampleCount else { return }
        guard stableChunkStreak >= requiredStableChunkCount else { return }

        phase = .steady
        stableChunkStreak = 0
    }

    private func isStableChunk(
        latestInterChunkGapMS: Int,
        avgChunkDurationMS: Int,
        avgInterChunkGapMS: Int,
        jitterMS: Int,
        cadenceDeficitMS: Int
    ) -> Bool {
        let allowedJitterMS = max(avgChunkDurationMS / 2, 40)
        guard jitterMS <= allowedJitterMS else { return false }

        let allowedGapMS = avgInterChunkGapMS + max(jitterMS, avgChunkDurationMS / 4, 20)
        guard latestInterChunkGapMS <= allowedGapMS else { return false }

        if phase != .steady {
            let sustainableCadenceMarginMS = max(avgChunkDurationMS / 6, 16)
            guard cadenceDeficitMS <= sustainableCadenceMarginMS else { return false }
        }

        return true
    }

    private func phaseAdaptiveMargins(
        for phase: PlaybackPhase,
        avgChunkDurationMS: Int,
        avgInterChunkGapMS: Int,
        cadenceDeficitMS: Int
    ) -> (
        startupBufferMS: Int,
        lowWaterMS: Int,
        resumeBufferMS: Int
    ) {
        switch phase {
        case .warmup:
            (
                max(avgInterChunkGapMS, cadenceDeficitMS * 6),
                max(avgChunkDurationMS / 2, cadenceDeficitMS * 2),
                max(avgChunkDurationMS, cadenceDeficitMS * 3)
            )
        case .recovery:
            (
                max(avgChunkDurationMS / 2, cadenceDeficitMS * 3),
                max(avgChunkDurationMS / 3, cadenceDeficitMS),
                max(avgChunkDurationMS / 2, cadenceDeficitMS * 2)
            )
        case .steady:
            (0, 0, 0)
        }
    }

    private static func classify(text: String) -> PlaybackComplexityClass {
        let textLength = text.count
        return switch textLength {
        case ..<220:
            PlaybackComplexityClass.compact
        case ..<620:
            PlaybackComplexityClass.balanced
        default:
            PlaybackComplexityClass.extended
        }
    }

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }
}

// MARK: - Playback Metrics

enum PlaybackMetricsConfiguration {
    static let rebufferThrashWarningCount = 3
    static let rebufferThrashWindowMS = 2_000
}

struct PlaybackSummary: Sendable {
    let thresholds: PlaybackAdaptiveThresholds
    let chunkCount: Int
    let sampleCount: Int
    let startupBufferedAudioMS: Int?
    let timeToFirstChunkMS: Int?
    let timeToPrerollReadyMS: Int?
    let timeFromPrerollReadyToDrainMS: Int?
    let minQueuedAudioMS: Int?
    let maxQueuedAudioMS: Int?
    let avgQueuedAudioMS: Int?
    let queueDepthSampleCount: Int
    let rebufferEventCount: Int
    let rebufferTotalDurationMS: Int
    let longestRebufferDurationMS: Int
    let starvationEventCount: Int
    let scheduleCallbackCount: Int
    let playedBackCallbackCount: Int
    let maxInterChunkGapMS: Int?
    let avgInterChunkGapMS: Int?
    let maxScheduleGapMS: Int?
    let avgScheduleGapMS: Int?
    let maxBoundaryDiscontinuity: Double?
    let maxLeadingAbsAmplitude: Double?
    let maxTrailingAbsAmplitude: Double?
    let fadeInChunkCount: Int
}

struct RuntimeMemorySnapshot: Sendable {
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
    let mlxCacheLimitBytes: Int?
    let mlxMemoryLimitBytes: Int?
}

// MARK: - Type-Erased Playback Controller

final class AnyPlaybackController: @unchecked Sendable {
    private let prepareImpl: @Sendable (_ sampleRate: Double) async throws -> Bool
    private let playImpl: @Sendable (
        _ sampleRate: Double,
        _ text: String,
        _ stream: AsyncThrowingStream<[Float], Error>,
        _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary
    private let stopImpl: @Sendable () async -> Void
    private let pauseImpl: @Sendable () async -> PlaybackState
    private let resumeImpl: @Sendable () async -> PlaybackState
    private let stateImpl: @Sendable () async -> PlaybackState

    init(
        prepare: @escaping @Sendable (_ sampleRate: Double) async throws -> Bool,
        play: @escaping @Sendable (
            _ sampleRate: Double,
            _ text: String,
            _ stream: AsyncThrowingStream<[Float], Error>,
            _ onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
        ) async throws -> PlaybackSummary,
        stop: @escaping @Sendable () async -> Void,
        pause: @escaping @Sendable () async -> PlaybackState,
        resume: @escaping @Sendable () async -> PlaybackState,
        state: @escaping @Sendable () async -> PlaybackState
    ) {
        prepareImpl = prepare
        playImpl = play
        stopImpl = stop
        pauseImpl = pause
        resumeImpl = resume
        stateImpl = state
    }

    convenience init(_ controller: AudioPlaybackDriver) {
        self.init(
            prepare: { sampleRate in
                try await controller.prepare(sampleRate: sampleRate)
            },
            play: { sampleRate, text, stream, onEvent in
                try await controller.play(
                    sampleRate: sampleRate,
                    text: text,
                    stream: stream,
                    onEvent: onEvent
                )
            },
            stop: {
                await controller.stop()
            },
            pause: {
                await controller.pause()
            },
            resume: {
                await controller.resume()
            },
            state: {
                await controller.state()
            }
        )
    }

    static func silent(traceEnabled: Bool = false) -> AnyPlaybackController {
        AnyPlaybackController(
            prepare: { _ in true },
            play: { sampleRate, text, stream, onEvent in
                let startedAt = Date()
                let thresholds = PlaybackThresholdController(text: text).thresholds
                var emittedFirstChunk = false
                var emittedPrerollReady = false
                var chunkCount = 0
                var sampleCount = 0
                var startupBufferedAudioMS: Int?
                var timeToFirstChunkMS: Int?
                var timeToPrerollReadyMS: Int?
                var minQueuedAudioMS: Int?
                var maxQueuedAudioMS: Int?
                var queueDepthTotalMS = 0
                var queueDepthSampleCount = 0
                var maxInterChunkGapMS: Int?
                var interChunkGapTotalMS = 0
                var interChunkGapCount = 0
                var maxBoundaryDiscontinuity: Double?
                var maxLeadingAbsAmplitude: Double?
                var maxTrailingAbsAmplitude: Double?
                var fadeInChunkCount = 0
                let starvationEventCount = 0
                var pendingSampleCount = 0
                var lastChunkAt: Date?
                var previousTrailingSample: Float?

                func bufferedAudioMS() -> Int {
                    Int((Double(pendingSampleCount) / sampleRate * 1_000).rounded())
                }

                func recordQueueDepth() {
                    let queuedAudioMS = bufferedAudioMS()
                    minQueuedAudioMS = min(minQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
                    maxQueuedAudioMS = max(maxQueuedAudioMS ?? queuedAudioMS, queuedAudioMS)
                    queueDepthTotalMS += queuedAudioMS
                    queueDepthSampleCount += 1
                }

                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }
                    let now = Date()
                    chunkCount += 1
                    sampleCount += chunk.count
                    pendingSampleCount += chunk.count
                    recordQueueDepth()

                    if let lastChunkAt {
                        let gapMS = milliseconds(since: lastChunkAt)
                        maxInterChunkGapMS = max(maxInterChunkGapMS ?? gapMS, gapMS)
                        interChunkGapTotalMS += gapMS
                        interChunkGapCount += 1
                        if gapMS >= thresholds.chunkGapWarningMS {
                            await onEvent(.chunkGapWarning(gapMS: gapMS, chunkIndex: chunkCount))
                        }
                    }
                    lastChunkAt = now

                    if let firstSample = chunk.first, let lastSample = chunk.last {
                        let leadingAbs = Double(abs(firstSample))
                        let trailingAbs = Double(abs(lastSample))
                        maxLeadingAbsAmplitude = max(maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
                        maxTrailingAbsAmplitude = max(maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
                        if let previousTrailingSample {
                            let jump = Double(abs(firstSample - previousTrailingSample))
                            maxBoundaryDiscontinuity = max(maxBoundaryDiscontinuity ?? jump, jump)
                        }
                        previousTrailingSample = lastSample
                    }

                    if !emittedFirstChunk {
                        emittedFirstChunk = true
                        fadeInChunkCount = 1
                        timeToFirstChunkMS = milliseconds(since: startedAt)
                        await onEvent(.firstChunk)
                    }

                    if !emittedPrerollReady, bufferedAudioMS() >= thresholds.startupBufferTargetMS {
                        emittedPrerollReady = true
                        startupBufferedAudioMS = bufferedAudioMS()
                        minQueuedAudioMS = startupBufferedAudioMS
                        timeToPrerollReadyMS = milliseconds(since: startedAt)
                        await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: thresholds))
                    }

                    if traceEnabled {
                        await onEvent(
                            .trace(
                                PlaybackTraceEvent(
                                    name: "chunk_received",
                                    chunkIndex: chunkCount,
                                    bufferIndex: nil,
                                    sampleCount: chunk.count,
                                    durationMS: Int((Double(chunk.count) / sampleRate * 1_000).rounded()),
                                    queuedAudioBeforeMS: nil,
                                    queuedAudioAfterMS: bufferedAudioMS(),
                                    gapMS: maxInterChunkGapMS,
                                    isRebuffering: false,
                                    fadeInApplied: chunkCount == 1
                                )
                            )
                        )
                    }
                }

                if !emittedPrerollReady, pendingSampleCount > 0 {
                    emittedPrerollReady = true
                    startupBufferedAudioMS = bufferedAudioMS()
                    minQueuedAudioMS = startupBufferedAudioMS
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: thresholds))
                }

                let timeFromPrerollReadyToDrainMS: Int?
                if let timeToPrerollReadyMS {
                    timeFromPrerollReadyToDrainMS = max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
                } else {
                    timeFromPrerollReadyToDrainMS = nil
                }

                if let maxBoundaryDiscontinuity, let maxLeadingAbsAmplitude, let maxTrailingAbsAmplitude {
                    await onEvent(
                        .bufferShapeSummary(
                            maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                            maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                            maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                            fadeInChunkCount: fadeInChunkCount
                        )
                    )
                }

                return PlaybackSummary(
                    thresholds: thresholds,
                    chunkCount: chunkCount,
                    sampleCount: sampleCount,
                    startupBufferedAudioMS: startupBufferedAudioMS,
                    timeToFirstChunkMS: timeToFirstChunkMS,
                    timeToPrerollReadyMS: timeToPrerollReadyMS,
                    timeFromPrerollReadyToDrainMS: timeFromPrerollReadyToDrainMS,
                    minQueuedAudioMS: minQueuedAudioMS,
                    maxQueuedAudioMS: maxQueuedAudioMS,
                    avgQueuedAudioMS: queueDepthSampleCount == 0 ? nil : queueDepthTotalMS / queueDepthSampleCount,
                    queueDepthSampleCount: queueDepthSampleCount,
                    rebufferEventCount: 0,
                    rebufferTotalDurationMS: 0,
                    longestRebufferDurationMS: 0,
                    starvationEventCount: starvationEventCount,
                    scheduleCallbackCount: chunkCount,
                    playedBackCallbackCount: chunkCount,
                    maxInterChunkGapMS: maxInterChunkGapMS,
                    avgInterChunkGapMS: interChunkGapCount == 0 ? nil : interChunkGapTotalMS / interChunkGapCount,
                    maxScheduleGapMS: nil,
                    avgScheduleGapMS: nil,
                    maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                    maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                    maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                    fadeInChunkCount: fadeInChunkCount
                )
            },
            stop: {},
            pause: { .idle },
            resume: { .idle },
            state: { .idle }
        )
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        try await prepareImpl(sampleRate)
    }

    func play(
        sampleRate: Double,
        text: String,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary {
        try await playImpl(sampleRate, text, stream, onEvent)
    }

    func stop() async {
        await stopImpl()
    }

    func pause() async -> PlaybackState {
        await pauseImpl()
    }

    func resume() async -> PlaybackState {
        await resumeImpl()
    }

    func state() async -> PlaybackState {
        await stateImpl()
    }
}

// MARK: - Playback Jobs

final class PlaybackJob: @unchecked Sendable {
    let requestID: String
    let op: String
    let text: String
    let normalizedText: String
    let profileName: String
    let textProfileName: String?
    let textContext: TextForSpeech.Context?
    let sourceFormat: TextForSpeech.SourceFormat?
    let textFeatures: SpeechTextForensicFeatures
    let textSections: [SpeechTextForensicSection]
    let stream: AsyncThrowingStream<[Float], any Swift.Error>
    let continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation
    var sampleRate: Double?
    var generationTask: Task<Void, Never>?
    var playbackTask: Task<Void, Never>?

    init(
        requestID: String,
        op: String,
        text: String,
        normalizedText: String,
        profileName: String,
        textProfileName: String?,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?,
        textFeatures: SpeechTextForensicFeatures,
        textSections: [SpeechTextForensicSection],
        stream: AsyncThrowingStream<[Float], any Swift.Error>,
        continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation
    ) {
        self.requestID = requestID
        self.op = op
        self.text = text
        self.normalizedText = normalizedText
        self.profileName = profileName
        self.textProfileName = textProfileName
        self.textContext = textContext
        self.sourceFormat = sourceFormat
        self.textFeatures = textFeatures
        self.textSections = textSections
        self.stream = stream
        self.continuation = continuation
    }
}

struct PlaybackHooks: Sendable {
    let handleEvent: @Sendable (PlaybackEvent, PlaybackJob) async -> Void
    let logFinished: @Sendable (PlaybackJob, PlaybackSummary, Double) async -> Void
    let completeJob: @Sendable (PlaybackJob, Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>) async -> Void
}

actor PlaybackController {
    struct ActivePlayback: Sendable {
        let requestID: String
        let task: Task<Void, Never>
    }

    private let driver: AnyPlaybackController
    private var hooks: PlaybackHooks?
    private var activePlayback: ActivePlayback?
    private var jobs = [String: PlaybackJob]()
    private var queue = [String]()

    init(driver: AnyPlaybackController) {
        self.driver = driver
    }

    // MARK: - Binding

    func bind(_ hooks: PlaybackHooks) {
        self.hooks = hooks
    }

    // MARK: - Driver Control

    func prepare(sampleRate: Double) async throws -> Bool {
        try await driver.prepare(sampleRate: sampleRate)
    }

    func handle(_ action: PlaybackAction) async -> PlaybackState {
        switch action {
        case .pause:
            return await driver.pause()
        case .resume:
            return await driver.resume()
        case .state:
            return await driver.state()
        }
    }

    // MARK: - Queue Ownership

    func enqueue(_ job: PlaybackJob) {
        jobs[job.requestID] = job
        queue.append(job.requestID)
    }

    func setGenerationTask(_ task: Task<Void, Never>?, for requestID: String) {
        jobs[requestID]?.generationTask = task
    }

    func job(for requestID: String) -> PlaybackJob? {
        jobs[requestID]
    }

    func jobCount() -> Int {
        jobs.count
    }

    func activeRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let requestID = activePlayback?.requestID, let job = jobs[requestID] else { return nil }
        return ActiveWorkerRequestSummary(id: requestID, op: job.op, profileName: job.profileName)
    }

    func queuedRequestSummaries() -> [QueuedWorkerRequestSummary] {
        let waitingQueue = queue.filter { $0 != activePlayback?.requestID }
        return waitingQueue.enumerated().compactMap { offset, requestID in
            guard let job = jobs[requestID] else { return nil }
            return QueuedWorkerRequestSummary(
                id: requestID,
                op: job.op,
                profileName: job.profileName,
                queuePosition: offset + 1
            )
        }
    }

    func stateSnapshot() async -> SpeakSwiftly.PlaybackStateSnapshot {
        SpeakSwiftly.PlaybackStateSnapshot(
            state: await driver.state(),
            activeRequest: activeRequestSummary()
        )
    }

    func clearQueued(excluding protectedRequestIDs: Set<String>) -> [PlaybackJob] {
        let waitingRequestIDs = queue.filter { !protectedRequestIDs.contains($0) }
        let removedJobs = waitingRequestIDs.compactMap { requestID in
            let job = jobs.removeValue(forKey: requestID)
            queue.removeAll { $0 == requestID }
            return job
        }
        return removedJobs
    }

    func cancel(requestID: String) async -> PlaybackJob? {
        guard let job = jobs[requestID] else { return nil }

        job.generationTask?.cancel()
        job.playbackTask?.cancel()
        queue.removeAll { $0 == requestID }
        jobs.removeValue(forKey: requestID)

        if activePlayback?.requestID == requestID {
            activePlayback = nil
            await driver.stop()
        }

        return job
    }

    func discard(requestID: String) -> PlaybackJob? {
        queue.removeAll { $0 == requestID }
        return jobs.removeValue(forKey: requestID)
    }

    func shutdown() async -> [PlaybackJob] {
        let activeTask = activePlayback?.task
        activePlayback = nil
        activeTask?.cancel()

        for job in jobs.values {
            job.generationTask?.cancel()
            job.playbackTask?.cancel()
        }

        let cancelledJobs = Array(jobs.values)
        jobs.removeAll()
        queue.removeAll()
        await driver.stop()
        return cancelledJobs
    }

    // MARK: - Playback Execution

    func startNextIfPossible() async {
        guard activePlayback == nil else { return }
        guard let requestID = queue.first, let job = jobs[requestID] else { return }
        guard let sampleRate = job.sampleRate else { return }
        guard let hooks else { return }

        let task = Task {
            await self.runPlayback(for: job, sampleRate: sampleRate, hooks: hooks)
        }
        activePlayback = ActivePlayback(requestID: requestID, task: task)
        job.playbackTask = task
    }

    private func runPlayback(
        for job: PlaybackJob,
        sampleRate: Double,
        hooks: PlaybackHooks
    ) async {
        let result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>

        do {
            let playbackSummary = try await driver.play(
                sampleRate: sampleRate,
                text: job.normalizedText,
                stream: job.stream
            ) { event in
                await hooks.handleEvent(event, job)
            }
            await hooks.logFinished(job, playbackSummary, sampleRate)
            result = .success(SpeakSwiftly.Runtime.WorkerSuccessPayload(id: job.requestID))
        } catch is CancellationError {
            result = .failure(
                WorkerError(
                    code: .requestCancelled,
                    message: "Request '\(job.requestID)' was cancelled before it could complete."
                )
            )
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Live playback failed for request '\(job.requestID)' due to an unexpected internal error. \(error.localizedDescription)"
                )
            )
        }

        await finishPlayback(requestID: job.requestID, result: result, hooks: hooks)
    }

    private func finishPlayback(
        requestID: String,
        result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>,
        hooks: PlaybackHooks
    ) async {
        guard activePlayback?.requestID == requestID else { return }

        activePlayback = nil
        queue.removeAll { $0 == requestID }

        guard let job = jobs.removeValue(forKey: requestID) else {
            await startNextIfPossible()
            return
        }

        job.generationTask = nil
        job.playbackTask = nil
        await hooks.completeJob(job, result)
        await startNextIfPossible()
    }
}

// MARK: - AVFoundation Playback Driver

@MainActor
final class AudioPlaybackDriver {
    // MARK: - Request State

    @MainActor
    private final class RequestPlaybackState {
        let requestID: UInt64
        var thresholdsController: PlaybackThresholdController
        var generationFinished = false
        var isRebuffering = false
        var scheduledSampleCount = 0
        var playedBackSampleCount = 0
        var minQueuedAudioMS: Int?
        var maxQueuedAudioMS: Int?
        var queueDepthTotalMS = 0
        var queueDepthSampleCount = 0
        var rebufferEventCount = 0
        var rebufferStartedAt: Date?
        var rebufferTotalDurationMS = 0
        var longestRebufferDurationMS = 0
        var recentRebufferStartTimes = [Date]()
        var emittedRebufferThrashWarning = false
        var starvationEventCount = 0
        var emittedLowQueueWarning = false
        var scheduleCallbackCount = 0
        var playedBackCallbackCount = 0
        var lastTrailingSample: Float?
        var maxBoundaryDiscontinuity: Double?
        var maxLeadingAbsAmplitude: Double?
        var maxTrailingAbsAmplitude: Double?
        var fadeInChunkCount = 0
        var drainContinuation: CheckedContinuation<Void, Error>?

        init(requestID: UInt64, text: String) {
            self.requestID = requestID
            thresholdsController = PlaybackThresholdController(text: text)
        }

        func queuedAudioMS(sampleRate: Double) -> Int {
            let queuedSamples = max(scheduledSampleCount - playedBackSampleCount, 0)
            return Int((Double(queuedSamples) / sampleRate * 1_000).rounded())
        }

        func recordQueuedAudioDepth(sampleRate: Double) {
            let currentQueuedAudioMS = queuedAudioMS(sampleRate: sampleRate)
            minQueuedAudioMS = min(minQueuedAudioMS ?? currentQueuedAudioMS, currentQueuedAudioMS)
            maxQueuedAudioMS = max(maxQueuedAudioMS ?? currentQueuedAudioMS, currentQueuedAudioMS)
            queueDepthTotalMS += currentQueuedAudioMS
            queueDepthSampleCount += 1
        }
    }

    private enum PlaybackConfiguration {
        static let minimumDrainTimeout: Duration = .seconds(5)
        static let drainTimeoutPaddingMS = 3_000
        static let drainProgressCheckIntervalMS = 500
        static let drainProgressStallTimeoutMS = 8_000
        static let lowQueueThresholdMS = 100
        static let channels: AVAudioChannelCount = 1

        static func drainTimeout(forQueuedAudioMS queuedAudioMS: Int) -> Duration {
            let paddedQueuedAudioMS = queuedAudioMS + drainTimeoutPaddingMS
            return max(minimumDrainTimeout, .milliseconds(paddedQueuedAudioMS))
        }
    }

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingFormat: AVAudioFormat?
    private var engineSampleRate: Double?
    private var nextRequestID: UInt64 = 0
    private let traceEnabled: Bool
    private var engineConfigurationObserver: NSObjectProtocol?
    private var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    private var activeRequestState: RequestPlaybackState?
    private var activeEventSink: (@Sendable (PlaybackEvent) async -> Void)?
    private var activeRuntimeFailure: WorkerError?
    private var lastObservedOutputDeviceDescription: String?
    private var playbackState: PlaybackState = .idle
    private var isPlaybackPausedManually = false

    // MARK: - Lifecycle

    init(traceEnabled: Bool = false) {
        self.traceEnabled = traceEnabled
        lastObservedOutputDeviceDescription = currentDefaultOutputDeviceDescription()
        installEngineConfigurationObserver()
        installDefaultOutputDeviceObserver()
    }

    func prepare(sampleRate: Double) throws -> Bool {
        let needsSetup = audioEngine == nil || playerNode == nil || engineSampleRate != sampleRate
        if needsSetup {
            try rebuildEngine(sampleRate: sampleRate)
        } else if audioEngine?.isRunning == false {
            try audioEngine?.start()
        }

        if playerNode?.isPlaying == false {
            playerNode?.play()
        }

        return needsSetup
    }

    func play(
        sampleRate: Double,
        text: String,
        stream: AsyncThrowingStream<[Float], Error>,
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void
    ) async throws -> PlaybackSummary {
        _ = try prepare(sampleRate: sampleRate)

        let startedAt = Date()
        let requestID = nextRequestID
        nextRequestID += 1
        let state = RequestPlaybackState(requestID: requestID, text: text)
        activeRequestState = state
        activeEventSink = onEvent
        activeRuntimeFailure = nil
        playbackState = .idle
        defer {
            activeRequestState = nil
            activeEventSink = nil
            activeRuntimeFailure = nil
            playbackState = .idle
            isPlaybackPausedManually = false
        }
        var emittedFirstChunk = false
        var emittedPrerollReady = false
        var startedPlayback = false
        var chunkCount = 0
        var sampleCount = 0
        var startupBufferedAudioMS: Int?
        var timeToFirstChunkMS: Int?
        var timeToPrerollReadyMS: Int?
        var pendingBuffers = [
            (
                buffer: AVAudioPCMBuffer,
                frameCount: Int,
                firstSample: Float,
                lastSample: Float,
                fadeInApplied: Bool,
                chunkIndex: Int
            )
        ]()
        var pendingSampleCount = 0
        var lastChunkReceivedAt: Date?
        var interChunkGapTotalMS = 0
        var interChunkGapCount = 0
        var maxInterChunkGapMS: Int?
        var lastScheduleAt: Date?
        var scheduleGapTotalMS = 0
        var scheduleGapCount = 0
        var maxScheduleGapMS: Int?
        var bufferIndex = 0
        var lastPreparedTrailingSample: Float?

        func bufferedAudioMS() -> Int {
            Int((Double(pendingSampleCount) / sampleRate * 1_000).rounded())
        }

        func scheduleForPlayback(
            _ buffer: AVAudioPCMBuffer,
            frameCount: Int,
            firstSample: Float,
            lastSample: Float,
            fadeInApplied: Bool,
            chunkIndex: Int
        ) async throws {
            try throwIfActivePlaybackInterrupted()
            let queuedAudioBeforeMS = state.queuedAudioMS(sampleRate: sampleRate)
            let scheduledAt = Date()
            let scheduleGapMS: Int?
            if let lastScheduleAt {
                let gapMS = milliseconds(since: lastScheduleAt)
                scheduleGapMS = gapMS
                maxScheduleGapMS = max(maxScheduleGapMS ?? gapMS, gapMS)
                scheduleGapTotalMS += gapMS
                scheduleGapCount += 1
                if startedPlayback, gapMS >= state.thresholdsController.thresholds.scheduleGapWarningMS {
                    await onEvent(
                        .scheduleGapWarning(
                            gapMS: gapMS,
                            bufferIndex: bufferIndex + 1,
                            queuedAudioMS: queuedAudioBeforeMS
                        )
                    )
                }
            } else {
                scheduleGapMS = nil
            }
            lastScheduleAt = scheduledAt
            bufferIndex += 1
            let currentBufferIndex = bufferIndex

            let leadingAbs = Double(abs(firstSample))
            let trailingAbs = Double(abs(lastSample))
            state.maxLeadingAbsAmplitude = max(state.maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
            state.maxTrailingAbsAmplitude = max(state.maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
            if fadeInApplied {
                state.fadeInChunkCount += 1
            }
            if let lastTrailingSample = state.lastTrailingSample {
                let jump = Double(abs(firstSample - lastTrailingSample))
                state.maxBoundaryDiscontinuity = max(state.maxBoundaryDiscontinuity ?? jump, jump)
            }
            state.lastTrailingSample = lastSample

            state.scheduledSampleCount += frameCount
            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: sampleRate)
            let queuedAudioAfterMS = state.queuedAudioMS(sampleRate: sampleRate)
            if traceEnabled {
                await onEvent(
                    .trace(
                        PlaybackTraceEvent(
                            name: "buffer_scheduled",
                            chunkIndex: chunkIndex,
                            bufferIndex: currentBufferIndex,
                            sampleCount: frameCount,
                            durationMS: Int((Double(frameCount) / sampleRate * 1_000).rounded()),
                            queuedAudioBeforeMS: queuedAudioBeforeMS,
                            queuedAudioAfterMS: queuedAudioAfterMS,
                            gapMS: scheduleGapMS,
                            isRebuffering: state.isRebuffering,
                            fadeInApplied: fadeInApplied
                        )
                    )
                )
            }
            scheduleBuffer(buffer, callbackType: .dataPlayedBack) { callbackType in
                guard callbackType == .dataPlayedBack else { return }
                Task { @MainActor in
                    guard requestID + 1 == self.nextRequestID else { return }

                    state.playedBackSampleCount += frameCount
                    state.playedBackCallbackCount += 1
                    state.recordQueuedAudioDepth(sampleRate: sampleRate)

                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if self.traceEnabled {
                        await onEvent(
                            .trace(
                                PlaybackTraceEvent(
                                    name: "buffer_played_back",
                                    chunkIndex: chunkIndex,
                                    bufferIndex: currentBufferIndex,
                                    sampleCount: frameCount,
                                    durationMS: Int((Double(frameCount) / sampleRate * 1_000).rounded()),
                                    queuedAudioBeforeMS: nil,
                                    queuedAudioAfterMS: currentQueuedAudioMS,
                                    gapMS: nil,
                                    isRebuffering: state.isRebuffering,
                                    fadeInApplied: fadeInApplied
                                )
                            )
                        )
                    }
                    if !state.generationFinished, currentQueuedAudioMS <= 0 {
                        state.starvationEventCount += 1
                        state.thresholdsController.recordStarvation()
                        if !state.isRebuffering {
                            state.isRebuffering = true
                            state.rebufferEventCount += 1
                            state.thresholdsController.recordRebuffer()
                            let now = Date()
                            state.rebufferStartedAt = now
                            state.recentRebufferStartTimes.append(now)
                            state.recentRebufferStartTimes.removeAll {
                                now.timeIntervalSince($0) * 1_000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                            }
                            await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                        }
                        await onEvent(.starved)
                        return
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= state.thresholdsController.thresholds.lowWaterTargetMS,
                       !state.isRebuffering
                    {
                        state.isRebuffering = true
                        state.rebufferEventCount += 1
                        state.thresholdsController.recordRebuffer()
                        let now = Date()
                        state.rebufferStartedAt = now
                        state.recentRebufferStartTimes.append(now)
                        state.recentRebufferStartTimes.removeAll {
                            now.timeIntervalSince($0) * 1_000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                        }
                        self.playerNode?.pause()
                        await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                        if !state.emittedRebufferThrashWarning,
                           state.recentRebufferStartTimes.count >= PlaybackMetricsConfiguration.rebufferThrashWarningCount
                        {
                            state.emittedRebufferThrashWarning = true
                            await onEvent(
                                .rebufferThrashWarning(
                                    rebufferEventCount: state.rebufferEventCount,
                                    windowMS: PlaybackMetricsConfiguration.rebufferThrashWindowMS
                                )
                            )
                        }
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= PlaybackConfiguration.lowQueueThresholdMS,
                       !state.emittedLowQueueWarning
                    {
                        state.emittedLowQueueWarning = true
                        await onEvent(.queueDepthLow(queuedAudioMS: currentQueuedAudioMS))
                    } else if currentQueuedAudioMS > PlaybackConfiguration.lowQueueThresholdMS {
                        state.emittedLowQueueWarning = false
                    }

                    if state.isRebuffering,
                       (currentQueuedAudioMS >= state.thresholdsController.thresholds.resumeBufferTargetMS || state.generationFinished)
                    {
                        if !self.isPlaybackPausedManually {
                            self.playerNode?.play()
                        }
                        state.isRebuffering = false
                        if let rebufferStartedAt = state.rebufferStartedAt {
                            let durationMS = milliseconds(since: rebufferStartedAt)
                            state.rebufferTotalDurationMS += durationMS
                            state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                            state.rebufferStartedAt = nil
                        }
                        await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                    }

                    if state.generationFinished, currentQueuedAudioMS == 0 {
                        state.drainContinuation?.resume()
                        state.drainContinuation = nil
                    }
                }
            }
        }

        do {
            for try await chunk in stream {
                try throwIfActivePlaybackInterrupted()
                guard !chunk.isEmpty else { continue }
                let now = Date()
                let chunkDurationMS = Int((Double(chunk.count) / sampleRate * 1_000).rounded())
                let interChunkGapMS: Int?
                chunkCount += 1
                sampleCount += chunk.count
                if let lastChunkReceivedAt {
                    let gapMS = milliseconds(since: lastChunkReceivedAt)
                    interChunkGapMS = gapMS
                    maxInterChunkGapMS = max(maxInterChunkGapMS ?? gapMS, gapMS)
                    interChunkGapTotalMS += gapMS
                    interChunkGapCount += 1
                    state.thresholdsController.recordChunk(durationMS: chunkDurationMS, interChunkGapMS: gapMS)
                    if startedPlayback, gapMS >= state.thresholdsController.thresholds.chunkGapWarningMS {
                        await onEvent(.chunkGapWarning(gapMS: gapMS, chunkIndex: chunkCount))
                    }
                } else {
                    interChunkGapMS = nil
                    state.thresholdsController.recordChunk(durationMS: chunkDurationMS, interChunkGapMS: nil)
                }
                lastChunkReceivedAt = now
                if traceEnabled {
                    await onEvent(
                        .trace(
                            PlaybackTraceEvent(
                                name: "chunk_received",
                                chunkIndex: chunkCount,
                                bufferIndex: nil,
                                sampleCount: chunk.count,
                                durationMS: chunkDurationMS,
                                queuedAudioBeforeMS: startedPlayback ? state.queuedAudioMS(sampleRate: sampleRate) : bufferedAudioMS(),
                                queuedAudioAfterMS: nil,
                                gapMS: interChunkGapMS,
                                isRebuffering: state.isRebuffering,
                                fadeInApplied: !emittedFirstChunk
                            )
                        )
                    )
                }
                if let buffer = makePCMBuffer(
                    from: chunk,
                    sampleRate: sampleRate,
                    previousTrailingSample: lastPreparedTrailingSample,
                    applyFadeIn: !emittedFirstChunk
                ) {
                    lastPreparedTrailingSample = buffer.lastSample
                    let frameCount = buffer.frameCount
                    if startedPlayback {
                        try await scheduleForPlayback(
                            buffer.buffer,
                            frameCount: frameCount,
                            firstSample: buffer.firstSample,
                            lastSample: buffer.lastSample,
                            fadeInApplied: buffer.fadeInApplied,
                            chunkIndex: chunkCount
                        )
                        if state.isRebuffering {
                            let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                            if currentQueuedAudioMS >= state.thresholdsController.thresholds.resumeBufferTargetMS {
                                if !isPlaybackPausedManually {
                                    playerNode?.play()
                                }
                                state.isRebuffering = false
                                if let rebufferStartedAt = state.rebufferStartedAt {
                                    let durationMS = milliseconds(since: rebufferStartedAt)
                                    state.rebufferTotalDurationMS += durationMS
                                    state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                                    state.rebufferStartedAt = nil
                                }
                                await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                            }
                        }
                    } else {
                        pendingBuffers.append(
                            (
                                buffer: buffer.buffer,
                                frameCount: frameCount,
                                firstSample: buffer.firstSample,
                                lastSample: buffer.lastSample,
                                fadeInApplied: buffer.fadeInApplied,
                                chunkIndex: chunkCount
                            )
                        )
                        pendingSampleCount += frameCount
                    }
                }

                if !emittedFirstChunk {
                    emittedFirstChunk = true
                    timeToFirstChunkMS = milliseconds(since: startedAt)
                    await onEvent(.firstChunk)
                }

                if !startedPlayback, bufferedAudioMS() >= state.thresholdsController.thresholds.startupBufferTargetMS {
                    startupBufferedAudioMS = bufferedAudioMS()

                    for pending in pendingBuffers {
                        try await scheduleForPlayback(
                            pending.buffer,
                            frameCount: pending.frameCount,
                            firstSample: pending.firstSample,
                            lastSample: pending.lastSample,
                            fadeInApplied: pending.fadeInApplied,
                            chunkIndex: pending.chunkIndex
                        )
                    }

                    pendingBuffers.removeAll(keepingCapacity: true)
                    pendingSampleCount = 0
                    startedPlayback = true
                    emittedPrerollReady = true
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    if !isPlaybackPausedManually {
                        playbackState = .playing
                    }
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: state.thresholdsController.thresholds))
                }
            }

            state.generationFinished = true
            if !startedPlayback, !pendingBuffers.isEmpty {
                startupBufferedAudioMS = bufferedAudioMS()

                for pending in pendingBuffers {
                    try await scheduleForPlayback(
                        pending.buffer,
                        frameCount: pending.frameCount,
                        firstSample: pending.firstSample,
                        lastSample: pending.lastSample,
                        fadeInApplied: pending.fadeInApplied,
                        chunkIndex: pending.chunkIndex
                    )
                }

                pendingBuffers.removeAll(keepingCapacity: true)
                pendingSampleCount = 0
                startedPlayback = true
                if state.isRebuffering {
                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if !isPlaybackPausedManually {
                        playerNode?.play()
                    }
                    state.isRebuffering = false
                    if let rebufferStartedAt = state.rebufferStartedAt {
                        let durationMS = milliseconds(since: rebufferStartedAt)
                        state.rebufferTotalDurationMS += durationMS
                        state.longestRebufferDurationMS = max(state.longestRebufferDurationMS, durationMS)
                        state.rebufferStartedAt = nil
                    }
                    await onEvent(.rebufferResumed(bufferedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                }
                if !isPlaybackPausedManually {
                    playbackState = .playing
                }
            }

            if !emittedPrerollReady, chunkCount > 0 {
                emittedPrerollReady = true
                startupBufferedAudioMS = startupBufferedAudioMS ?? state.queuedAudioMS(sampleRate: sampleRate)
                timeToPrerollReadyMS = milliseconds(since: startedAt)
                await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: state.thresholdsController.thresholds))
            }

            try throwIfActivePlaybackInterrupted()
            try await waitForPlaybackDrain(
                state: state,
                sampleRate: sampleRate
            )
            if let maxBoundaryDiscontinuity = state.maxBoundaryDiscontinuity,
               let maxLeadingAbsAmplitude = state.maxLeadingAbsAmplitude,
               let maxTrailingAbsAmplitude = state.maxTrailingAbsAmplitude
            {
                await onEvent(
                    .bufferShapeSummary(
                        maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                        maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                        maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                        fadeInChunkCount: state.fadeInChunkCount
                    )
                )
            }
            let timeFromPrerollReadyToDrainMS: Int?
            if let timeToPrerollReadyMS {
                timeFromPrerollReadyToDrainMS = max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
            } else {
                timeFromPrerollReadyToDrainMS = nil
            }

            resetPlayerNodeForNextRequest()

            return PlaybackSummary(
                thresholds: state.thresholdsController.thresholds,
                chunkCount: chunkCount,
                sampleCount: sampleCount,
                startupBufferedAudioMS: startupBufferedAudioMS,
                timeToFirstChunkMS: timeToFirstChunkMS,
                timeToPrerollReadyMS: timeToPrerollReadyMS,
                timeFromPrerollReadyToDrainMS: timeFromPrerollReadyToDrainMS,
                minQueuedAudioMS: state.minQueuedAudioMS,
                maxQueuedAudioMS: state.maxQueuedAudioMS,
                avgQueuedAudioMS: state.queueDepthSampleCount == 0 ? nil : state.queueDepthTotalMS / state.queueDepthSampleCount,
                queueDepthSampleCount: state.queueDepthSampleCount,
                rebufferEventCount: state.rebufferEventCount,
                rebufferTotalDurationMS: state.rebufferTotalDurationMS,
                longestRebufferDurationMS: state.longestRebufferDurationMS,
                starvationEventCount: state.starvationEventCount,
                scheduleCallbackCount: state.scheduleCallbackCount,
                playedBackCallbackCount: state.playedBackCallbackCount,
                maxInterChunkGapMS: maxInterChunkGapMS,
                avgInterChunkGapMS: interChunkGapCount == 0 ? nil : interChunkGapTotalMS / interChunkGapCount,
                maxScheduleGapMS: maxScheduleGapMS,
                avgScheduleGapMS: scheduleGapCount == 0 ? nil : scheduleGapTotalMS / scheduleGapCount,
                maxBoundaryDiscontinuity: state.maxBoundaryDiscontinuity,
                maxLeadingAbsAmplitude: state.maxLeadingAbsAmplitude,
                maxTrailingAbsAmplitude: state.maxTrailingAbsAmplitude,
                fadeInChunkCount: state.fadeInChunkCount
            )
        } catch is CancellationError {
            resetPlayerNodeForNextRequest()
            throw CancellationError()
        } catch {
            resetPlayerNodeForNextRequest()
            if let workerError = error as? WorkerError {
                throw workerError
            }

            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback failed while scheduling generated audio into the local audio player. \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        streamingFormat = nil
        engineSampleRate = nil
        playbackState = .idle
        isPlaybackPausedManually = false
    }

    func pause() -> PlaybackState {
        guard activeRequestState != nil else {
            playbackState = .idle
            return playbackState
        }

        playerNode?.pause()
        isPlaybackPausedManually = true
        playbackState = .paused
        return playbackState
    }

    func resume() -> PlaybackState {
        guard let activeRequestState else {
            playbackState = .idle
            return playbackState
        }

        isPlaybackPausedManually = false
        let queuedAudioMS = activeRequestState.queuedAudioMS(sampleRate: engineSampleRate ?? 24_000)
        if !activeRequestState.isRebuffering
            || queuedAudioMS >= activeRequestState.thresholdsController.thresholds.resumeBufferTargetMS
            || activeRequestState.generationFinished
        {
            playerNode?.play()
        }
        playbackState = .playing
        return playbackState
    }

    func state() -> PlaybackState {
        playbackState
    }

    // MARK: - Drain Handling

    private func waitForPlaybackDrain(
        state: RequestPlaybackState,
        sampleRate: Double
    ) async throws {
        let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
        if currentQueuedAudioMS == 0 {
            return
        }
        let drainTimeout = PlaybackConfiguration.drainTimeout(forQueuedAudioMS: currentQueuedAudioMS)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        state.drainContinuation = continuation
                        if state.queuedAudioMS(sampleRate: sampleRate) == 0 {
                            state.drainContinuation?.resume()
                            state.drainContinuation = nil
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: drainTimeout)
                throw WorkerError(
                    code: .audioPlaybackTimeout,
                    message: "Live playback timed out after generated audio finished because the local audio player did not report drain completion within \(drainTimeout.components.seconds) seconds."
                )
            }
            group.addTask {
                var lastPlayedBackCallbackCount = await MainActor.run {
                    state.playedBackCallbackCount
                }
                var lastProgressAt = Date()

                while true {
                    try await Task.sleep(for: .milliseconds(PlaybackConfiguration.drainProgressCheckIntervalMS))
                    let snapshot = await MainActor.run {
                        (
                            playedBackCallbackCount: state.playedBackCallbackCount,
                            queuedAudioMS: state.queuedAudioMS(sampleRate: sampleRate),
                            isPausedManually: self.isPlaybackPausedManually
                        )
                    }

                    if snapshot.queuedAudioMS == 0 {
                        return
                    }
                    if snapshot.isPausedManually {
                        lastProgressAt = Date()
                        continue
                    }
                    if snapshot.playedBackCallbackCount != lastPlayedBackCallbackCount {
                        lastPlayedBackCallbackCount = snapshot.playedBackCallbackCount
                        lastProgressAt = Date()
                        continue
                    }

                    let stalledForMS = Int((Date().timeIntervalSince(lastProgressAt) * 1_000).rounded())
                    if stalledForMS >= PlaybackConfiguration.drainProgressStallTimeoutMS {
                        throw WorkerError(
                            code: .audioPlaybackTimeout,
                            message: "Live playback stalled after generated audio finished because the local audio player stopped reporting drain progress for \(PlaybackConfiguration.drainProgressStallTimeoutMS / 1_000) seconds while \(snapshot.queuedAudioMS) ms of audio remained queued."
                        )
                    }
                }
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Engine Management

    private func rebuildEngine(sampleRate: Double) throws {
        stop()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels
        )

        guard let format else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback could not create an AVAudioFormat for sample rate \(sampleRate)."
            )
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        node.play()

        audioEngine = engine
        playerNode = node
        streamingFormat = format
        engineSampleRate = sampleRate
    }

    private func resetPlayerNodeForNextRequest() {
        playerNode?.stop()
        playerNode?.reset()
        playerNode?.play()
    }

    // MARK: - System Observers

    private func installEngineConfigurationObserver() {
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let engine = self.audioEngine else { return }

                let engineIsRunning = engine.isRunning
                if let activeEventSink {
                    await activeEventSink(.engineConfigurationChanged(engineIsRunning: engineIsRunning))
                }

                interruptActivePlayback(
                    with: WorkerError(
                        code: .audioPlaybackFailed,
                        message: "Live playback stopped because macOS reported an AVAudioEngine configuration change during an active SpeakSwiftly request. The engine was running: \(engineIsRunning ? "yes" : "no"). The current request is being failed immediately so queued work can continue."
                    )
                )
            }
        }
    }

    private func installDefaultOutputDeviceObserver() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDefaultOutputDeviceChange()
            }
        }
        defaultOutputDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputDeviceAddress,
            DispatchQueue.main,
            listener
        )
    }

    private func handleDefaultOutputDeviceChange() {
        let previousDevice = lastObservedOutputDeviceDescription
        let currentDevice = currentDefaultOutputDeviceDescription()
        guard previousDevice != currentDevice else { return }
        lastObservedOutputDeviceDescription = currentDevice

        if let activeEventSink {
            Task {
                await activeEventSink(
                    .outputDeviceChanged(previousDevice: previousDevice, currentDevice: currentDevice)
                )
            }
        }

        interruptActivePlayback(
            with: WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback stopped because macOS switched the default output device from '\(previousDevice ?? "unknown output device")' to '\(currentDevice ?? "unknown output device")' during an active SpeakSwiftly request. The current request is being failed immediately so queued work can continue."
            )
        )
    }

    // MARK: - Interruption Handling

    private func interruptActivePlayback(with error: WorkerError) {
        guard activeRequestState != nil else { return }
        guard activeRuntimeFailure == nil else { return }

        activeRuntimeFailure = error
        stop()
        activeRequestState?.drainContinuation?.resume(throwing: error)
        activeRequestState?.drainContinuation = nil
    }

    private func throwIfActivePlaybackInterrupted() throws {
        if let activeRuntimeFailure {
            throw activeRuntimeFailure
        }
    }

    // MARK: - Device Inspection

    private func currentDefaultOutputDeviceDescription() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard deviceStatus == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        var deviceName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &deviceName
        )

        if let deviceName, nameStatus == noErr {
            let name = deviceName.takeUnretainedValue() as String
            if !name.isEmpty {
                return "\(name) [\(deviceID)]"
            }
        }

        return "AudioObjectID \(deviceID)"
    }

    // MARK: - Buffer Preparation

    private func makePCMBuffer(
        from samples: [Float],
        sampleRate: Double,
        previousTrailingSample: Float?,
        applyFadeIn: Bool
    ) -> (buffer: AVAudioPCMBuffer, frameCount: Int, firstSample: Float, lastSample: Float, fadeInApplied: Bool)? {
        guard let format = streamingFormat ?? AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels
        ) else {
            return nil
        }

        let processedSamples = shapePlaybackSamples(
            samples,
            sampleRate: format.sampleRate,
            previousTrailingSample: previousTrailingSample,
            applyFadeIn: applyFadeIn
        )
        guard let firstSample = processedSamples.first, let lastSample = processedSamples.last else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(processedSamples.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(processedSamples.count)
        if let channelData = buffer.floatChannelData {
            processedSamples.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: processedSamples.count)
            }
        }

        return (
            buffer: buffer,
            frameCount: Int(buffer.frameLength),
            firstSample: firstSample,
            lastSample: lastSample,
            fadeInApplied: applyFadeIn
        )
    }

    private func scheduleBuffer(
        _ buffer: AVAudioPCMBuffer,
        callbackType: AVAudioPlayerNodeCompletionCallbackType,
        completion: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void
    ) {
        playerNode?.scheduleBuffer(
            buffer,
            completionCallbackType: callbackType,
            completionHandler: completion
        )
    }
}

// MARK: - Sample Shaping

func shapePlaybackSamples(
    _ samples: [Float],
    sampleRate: Double,
    previousTrailingSample: Float?,
    applyFadeIn: Bool
) -> [Float] {
    guard !samples.isEmpty else { return [] }

    let minimumSampleValue: Float = -1
    let maximumSampleValue: Float = 1

    var processedSamples = samples.map { sample in
        if !sample.isFinite {
            return Float.zero
        }
        return min(max(sample, minimumSampleValue), maximumSampleValue)
    }

    if let previousTrailingSample, let currentLeadingSample = processedSamples.first {
        let boundaryJump = currentLeadingSample - previousTrailingSample
        if abs(boundaryJump) >= 0.08 {
            let rampSampleCount = min(max(Int(sampleRate * 0.005), 8), processedSamples.count)
            if rampSampleCount > 0 {
                let rampDivisor = Float(max(rampSampleCount - 1, 1))
                for index in 0..<rampSampleCount {
                    let progress = Float(index) / rampDivisor
                    let correction = boundaryJump * (1 - progress)
                    processedSamples[index] = min(
                        max(processedSamples[index] - correction, minimumSampleValue),
                        maximumSampleValue
                    )
                }
            }
        }
    }

    if applyFadeIn {
        let fadeInSampleCount = min(Int(sampleRate * 0.01), processedSamples.count)
        if fadeInSampleCount > 0 {
            let fadeDivisor = Float(max(fadeInSampleCount - 1, 1))
            for index in 0..<fadeInSampleCount {
                let factor = Float(index) / fadeDivisor
                processedSamples[index] *= factor
            }
        }
    }

    return processedSamples
}

private func milliseconds(since start: Date) -> Int {
    Int((Date().timeIntervalSince(start) * 1_000).rounded())
}

// MARK: - Dependencies

struct WorkerDependencies {
    let fileManager: FileManager
    let loadResidentModel: @Sendable () async throws -> AnySpeechModel
    let loadProfileModel: @Sendable () async throws -> AnySpeechModel
    let loadCloneTranscriptionModel: @Sendable () async throws -> AnyCloneTranscriptionModel
    let makePlaybackController: @MainActor @Sendable () -> AnyPlaybackController
    let writeWAV: @Sendable (_ samples: [Float], _ sampleRate: Int, _ url: URL) throws -> Void
    let loadAudioSamples: @Sendable (_ url: URL, _ sampleRate: Int) throws -> MLXArray?
    let loadAudioFloats: @Sendable (_ url: URL, _ sampleRate: Int) throws -> [Float]
    let writeStdout: @Sendable (Data) throws -> Void
    let writeStderr: @Sendable (String) -> Void
    let now: @Sendable () -> Date
    let readRuntimeMemory: @Sendable () -> RuntimeMemorySnapshot?

    static func live(fileManager: FileManager = .default) -> WorkerDependencies {
        let environment = ProcessInfo.processInfo.environment

        return WorkerDependencies(
            fileManager: fileManager,
            loadResidentModel: { try await ModelFactory.loadResidentModel() },
            loadProfileModel: { try await ModelFactory.loadProfileModel() },
            loadCloneTranscriptionModel: { try await ModelFactory.loadCloneTranscriptionModel() },
            makePlaybackController: {
                if environment[WorkerEnvironment.silentPlayback] == "1" {
                    return .silent(traceEnabled: environment[WorkerEnvironment.playbackTrace] == "1")
                }

                return AnyPlaybackController(
                    AudioPlaybackDriver(traceEnabled: environment[WorkerEnvironment.playbackTrace] == "1")
                )
            },
            writeWAV: { samples, sampleRate, url in
                try AudioUtils.writeWavFile(
                    samples: samples,
                    sampleRate: Double(sampleRate),
                    fileURL: url
                )
            },
            loadAudioSamples: { url, sampleRate in
                let (_, audio) = try MLXAudioCore.loadAudioArray(from: url, sampleRate: sampleRate)
                return audio
            },
            loadAudioFloats: loadFloatAudioSamples,
            writeStdout: { data in
                try FileHandle.standardOutput.write(contentsOf: data)
            },
            writeStderr: { message in
                do {
                    try FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
                } catch {
                    fputs(message + "\n", stderr)
                }
            },
            now: Date.init,
            readRuntimeMemory: currentRuntimeMemorySnapshot
        )
    }
}

private func loadFloatAudioSamples(from url: URL, sampleRate: Int) throws -> [Float] {
    let audioFile = try AVAudioFile(forReading: url)
    let format = audioFile.processingFormat
    let sourceSampleRate = Int(format.sampleRate.rounded())
    let frameCapacity = max(AVAudioFrameCount(audioFile.length), 1)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not allocate an audio buffer while reading '\(url.path)'."
        )
    }

    try audioFile.read(into: buffer)

    guard let channelData = buffer.floatChannelData else {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not access floating-point samples while decoding '\(url.path)'. The file may use an unsupported audio format."
        )
    }

    let channelCount = Int(format.channelCount)
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return [] }

    var mono = [Float](repeating: 0, count: frameLength)

    if channelCount == 1 {
        mono = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    } else {
        let divisor = Float(channelCount)
        for frameIndex in 0..<frameLength {
            var sum: Float = 0
            for channelIndex in 0..<channelCount {
                sum += channelData[channelIndex][frameIndex]
            }
            mono[frameIndex] = sum / divisor
        }
    }

    guard sampleRate > 0 else {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly was asked to decode '\(url.path)' with invalid target sample rate \(sampleRate)."
        )
    }

    if sourceSampleRate == sampleRate {
        return mono
    }

    do {
        return try resampleAudio(mono, from: sourceSampleRate, to: sampleRate)
    } catch {
        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not resample '\(url.path)' from \(sourceSampleRate) Hz to \(sampleRate) Hz. \(error.localizedDescription)"
        )
    }
}

private func currentRuntimeMemorySnapshot() -> RuntimeMemorySnapshot? {
    var usage = rusage_info_current()
    let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
            proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rebound)
        }
    }

    let snapshot = Memory.snapshot()
    return RuntimeMemorySnapshot(
        processResidentBytes: usageResult == 0 ? Int(usage.ri_resident_size) : nil,
        processPhysFootprintBytes: usageResult == 0 ? Int(usage.ri_phys_footprint) : nil,
        mlxActiveMemoryBytes: snapshot.activeMemory,
        mlxCacheMemoryBytes: snapshot.cacheMemory,
        mlxPeakMemoryBytes: snapshot.peakMemory,
        mlxCacheLimitBytes: Memory.cacheLimit,
        mlxMemoryLimitBytes: Memory.memoryLimit
    )
}
