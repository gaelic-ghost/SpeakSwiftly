@preconcurrency import AppKit
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import TextForSpeech

// MARK: - PlaybackEvent

enum PlaybackEvent {
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
        fadeInChunkCount: Int,
    )
    case trace(PlaybackTraceEvent)
    case starved
}

// MARK: - PlaybackEnvironmentEvent

enum PlaybackEnvironmentEvent {
    case outputDeviceObserved(currentDevice: String?)
    case outputDeviceChanged(previousDevice: String?, currentDevice: String?)
    case engineConfigurationChanged(engineIsRunning: Bool)
    case systemSleepStateChanged(isSleeping: Bool)
    case screenSleepStateChanged(isSleeping: Bool)
    case sessionActivityChanged(isActive: Bool)
    case recoveryStateChanged(reason: String, stage: String, attempt: Int?, currentDevice: String?)
    case interJobBoopPlayed(durationMS: Int, frequencyHz: Double, sampleRate: Double)
}

// MARK: - PlaybackTraceEvent

struct PlaybackTraceEvent {
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

// MARK: - PlaybackComplexityClass

enum PlaybackComplexityClass: String {
    case compact
    case balanced
    case extended
}

// MARK: - PlaybackAdaptiveThresholds

struct PlaybackAdaptiveThresholds: Equatable {
    let complexityClass: PlaybackComplexityClass
    let startupBufferTargetMS: Int
    let lowWaterTargetMS: Int
    let resumeBufferTargetMS: Int
    let chunkGapWarningMS: Int
    let scheduleGapWarningMS: Int
}

// MARK: - PlaybackPhase

enum PlaybackPhase: String {
    case warmup
    case steady
    case recovery
}

// MARK: - PlaybackThresholdController

struct PlaybackThresholdController {
    private static let codecTokenRateHz = 12.5
    private static let adaptationSampleCount = 6
    private static let warmupStableChunkRequirement = 6
    private static let recoveryStableChunkRequirement = 4
    private static let maxStartupBufferTargetMS = 20000
    private static let maxResumeBufferTargetMS = 24000
    private static let maxLowWaterTargetMS = 12000
    private static let maxChunkGapWarningMS = 1200
    private static let maxScheduleGapWarningMS = 900

    private static var defaultChunkDurationMS: Int {
        Int((2.0 / codecTokenRateHz * 1000).rounded())
    }

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
        thresholds = Self.seedThresholds(for: text, phase: .warmup)
        startupBufferFloorMS = thresholds.startupBufferTargetMS
        lowWaterFloorMS = thresholds.lowWaterTargetMS
        resumeBufferFloorMS = thresholds.resumeBufferTargetMS
        chunkGapWarningFloorMS = thresholds.chunkGapWarningMS
        scheduleGapWarningFloorMS = thresholds.scheduleGapWarningMS
    }

    private static func seedThresholds(
        for text: String,
        phase: PlaybackPhase,
    ) -> PlaybackAdaptiveThresholds {
        seededThresholds(for: classify(text: text), phase: phase)
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
                    scheduleGapWarningMS: 180,
                )
            case .balanced:
                PlaybackAdaptiveThresholds(
                    complexityClass: .balanced,
                    startupBufferTargetMS: 520,
                    lowWaterTargetMS: 220,
                    resumeBufferTargetMS: 520,
                    chunkGapWarningMS: 520,
                    scheduleGapWarningMS: 220,
                )
            case .extended:
                PlaybackAdaptiveThresholds(
                    complexityClass: .extended,
                    startupBufferTargetMS: 12800,
                    lowWaterTargetMS: 4800,
                    resumeBufferTargetMS: 16000,
                    chunkGapWarningMS: 900,
                    scheduleGapWarningMS: 400,
                )
        }

        let phaseBias = phaseThresholdBias(for: complexityClass, phase: phase)
        return PlaybackAdaptiveThresholds(
            complexityClass: base.complexityClass,
            startupBufferTargetMS: min(Self.maxStartupBufferTargetMS, base.startupBufferTargetMS + phaseBias.startupBufferMS),
            lowWaterTargetMS: min(Self.maxLowWaterTargetMS, base.lowWaterTargetMS + phaseBias.lowWaterMS),
            resumeBufferTargetMS: min(Self.maxResumeBufferTargetMS, base.resumeBufferTargetMS + phaseBias.resumeBufferMS),
            chunkGapWarningMS: min(Self.maxChunkGapWarningMS, base.chunkGapWarningMS + phaseBias.chunkGapWarningMS),
            scheduleGapWarningMS: min(Self.maxScheduleGapWarningMS, base.scheduleGapWarningMS + phaseBias.scheduleGapWarningMS),
        )
    }

    private static func phaseThresholdBias(for complexityClass: PlaybackComplexityClass, phase: PlaybackPhase) -> (
        startupBufferMS: Int,
        lowWaterMS: Int,
        resumeBufferMS: Int,
        chunkGapWarningMS: Int,
        scheduleGapWarningMS: Int,
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
            cadenceDeficitMS: cadenceDeficitMS,
        )

        let seeded = Self.seededThresholds(for: thresholds.complexityClass, phase: phase)
        let phaseMargins = phaseAdaptiveMargins(
            for: phase,
            avgChunkDurationMS: avgChunkDurationMS,
            avgInterChunkGapMS: avgInterChunkGapMS,
            cadenceDeficitMS: cadenceDeficitMS,
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
                    + phaseMargins.startupBufferMS,
            ),
        )
        let lowWaterTargetMS = min(
            Self.maxLowWaterTargetMS,
            max(
                lowWaterFloorMS,
                seeded.lowWaterTargetMS,
                avgInterChunkGapMS
                    + max(jitterMS, avgChunkDurationMS / 2)
                    + cadenceDeficitMS * 2
                    + phaseMargins.lowWaterMS,
            ),
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
                    + phaseMargins.resumeBufferMS,
            ),
        )
        let chunkGapWarningMS = min(
            Self.maxChunkGapWarningMS,
            max(chunkGapWarningFloorMS, seeded.chunkGapWarningMS, avgInterChunkGapMS + avgChunkDurationMS),
        )
        let scheduleGapWarningMS = min(
            Self.maxScheduleGapWarningMS,
            max(scheduleGapWarningFloorMS, seeded.scheduleGapWarningMS, avgInterChunkGapMS - max(avgChunkDurationMS / 4, 8)),
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: chunkGapWarningMS,
                scheduleGapWarningMS: scheduleGapWarningMS,
            ),
            preserveFloors: false,
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
                avgChunkDurationMS * (4 + starvationCount),
            ),
        )
        let lowWaterTargetMS = min(
            Self.maxLowWaterTargetMS,
            max(
                thresholds.lowWaterTargetMS,
                resumeBufferTargetMS - max(avgChunkDurationMS * 2, avgInterChunkGapMS),
            ),
        )
        let startupBufferTargetMS = min(
            Self.maxStartupBufferTargetMS,
            max(thresholds.startupBufferTargetMS, resumeBufferTargetMS),
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: thresholds.chunkGapWarningMS,
                scheduleGapWarningMS: thresholds.scheduleGapWarningMS,
            ),
            preserveFloors: true,
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
            resumeBufferMS: max(rebufferPenaltyMS * 4, avgChunkDurationMS),
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
                    + repeatedRebufferMargins.startupBufferMS,
            ),
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
                    + repeatedRebufferMargins.lowWaterMS,
            ),
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
                    + repeatedRebufferMargins.resumeBufferMS,
            ),
        )
        let chunkGapWarningMS = min(
            Self.maxChunkGapWarningMS,
            max(
                thresholds.chunkGapWarningMS,
                chunkGapWarningFloorMS,
                avgInterChunkGapMS + avgChunkDurationMS + rebufferPenaltyMS,
            ),
        )
        let scheduleGapWarningMS = min(
            Self.maxScheduleGapWarningMS,
            max(
                thresholds.scheduleGapWarningMS,
                scheduleGapWarningFloorMS,
                avgInterChunkGapMS - max(avgChunkDurationMS / 4, 8) + max(rebufferPenaltyMS / 2, 12),
            ),
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: chunkGapWarningMS,
                scheduleGapWarningMS: scheduleGapWarningMS,
            ),
            preserveFloors: true,
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
            scheduleGapWarningMS: max(thresholds.scheduleGapWarningMS, scheduleGapWarningFloorMS),
        )
    }

    private mutating func updatePhase(
        latestInterChunkGapMS: Int?,
        avgChunkDurationMS: Int,
        avgInterChunkGapMS: Int,
        jitterMS: Int,
        cadenceDeficitMS: Int,
    ) {
        guard let latestInterChunkGapMS else { return }

        if isStableChunk(
            latestInterChunkGapMS: latestInterChunkGapMS,
            avgChunkDurationMS: avgChunkDurationMS,
            avgInterChunkGapMS: avgInterChunkGapMS,
            jitterMS: jitterMS,
            cadenceDeficitMS: cadenceDeficitMS,
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
        cadenceDeficitMS: Int,
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
        cadenceDeficitMS: Int,
    ) -> (
        startupBufferMS: Int,
        lowWaterMS: Int,
        resumeBufferMS: Int,
    ) {
        switch phase {
            case .warmup:
                (
                    max(avgInterChunkGapMS, cadenceDeficitMS * 6),
                    max(avgChunkDurationMS / 2, cadenceDeficitMS * 2),
                    max(avgChunkDurationMS, cadenceDeficitMS * 3),
                )
            case .recovery:
                (
                    max(avgChunkDurationMS / 2, cadenceDeficitMS * 3),
                    max(avgChunkDurationMS / 3, cadenceDeficitMS),
                    max(avgChunkDurationMS / 2, cadenceDeficitMS * 2),
                )
            case .steady:
                (0, 0, 0)
        }
    }

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }

        return values.reduce(0, +) / values.count
    }
}

// MARK: - PlaybackMetricsConfiguration

enum PlaybackMetricsConfiguration {
    static let rebufferThrashWarningCount = 3
    static let rebufferThrashWindowMS = 2000
}

// MARK: - PlaybackSummary

struct PlaybackSummary {
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

// MARK: - RuntimeMemorySnapshot

struct RuntimeMemorySnapshot {
    let processResidentBytes: Int?
    let processPhysFootprintBytes: Int?
    let processUserCPUTimeNS: Int?
    let processSystemCPUTimeNS: Int?
    let mlxActiveMemoryBytes: Int?
    let mlxCacheMemoryBytes: Int?
    let mlxPeakMemoryBytes: Int?
    let mlxCacheLimitBytes: Int?
    let mlxMemoryLimitBytes: Int?
}

// MARK: - AudioPlaybackDriver

@MainActor
final class AudioPlaybackDriver {
    fileprivate enum PlaybackConfiguration {
        static let minimumDrainTimeout: Duration = .seconds(5)
        static let drainTimeoutPaddingMS = 3000
        static let drainProgressCheckIntervalMS = 500
        static let drainProgressStallTimeoutMS = 8000
        static let environmentInstabilityWindowMS = 8000
        static let recoveryStabilizationDelayMS = 900
        static let recoveryMaximumAttempts = 3
        static let lowQueueThresholdMS = 100
        static let channels: AVAudioChannelCount = 1
        static let interJobBoopDurationMS = 90
        static let interJobBoopFrequencyHz = 1176.0
        static let interJobBoopAmplitude: Float = 0.14
        static let interJobBoopFadeMS = 10
        static let interJobBoopTimeout: Duration = .seconds(2)

        static func drainTimeout(forQueuedAudioMS queuedAudioMS: Int) -> Duration {
            let paddedQueuedAudioMS = queuedAudioMS + drainTimeoutPaddingMS
            return max(minimumDrainTimeout, .milliseconds(paddedQueuedAudioMS))
        }
    }

    // MARK: - Request State

    @MainActor
    private final class RequestPlaybackState {
        struct QueuedBuffer {
            let pcmBuffer: AVAudioPCMBuffer
            let frameCount: Int
            let firstSample: Float
            let lastSample: Float
            let fadeInApplied: Bool
            let chunkIndex: Int
            var bufferIndex: Int?
            var engineGeneration: Int?
        }

        let requestID: UInt64
        var thresholdsController: PlaybackThresholdController
        var generationFinished = false
        var isRebuffering = false
        var queuedBuffers = [QueuedBuffer]()
        var queuedSampleCount = 0
        var nextBufferIndex = 0
        var engineGeneration = 0
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
            Int((Double(max(queuedSampleCount, 0)) / sampleRate * 1000).rounded())
        }

        func recordQueuedAudioDepth(sampleRate: Double) {
            let currentQueuedAudioMS = queuedAudioMS(sampleRate: sampleRate)
            minQueuedAudioMS = min(minQueuedAudioMS ?? currentQueuedAudioMS, currentQueuedAudioMS)
            maxQueuedAudioMS = max(maxQueuedAudioMS ?? currentQueuedAudioMS, currentQueuedAudioMS)
            queueDepthTotalMS += currentQueuedAudioMS
            queueDepthSampleCount += 1
        }

        func enqueueBuffer(
            _ pcmBuffer: AVAudioPCMBuffer,
            frameCount: Int,
            firstSample: Float,
            lastSample: Float,
            fadeInApplied: Bool,
            chunkIndex: Int,
        ) {
            queuedBuffers.append(
                QueuedBuffer(
                    pcmBuffer: pcmBuffer,
                    frameCount: frameCount,
                    firstSample: firstSample,
                    lastSample: lastSample,
                    fadeInApplied: fadeInApplied,
                    chunkIndex: chunkIndex,
                    bufferIndex: nil,
                    engineGeneration: nil,
                ),
            )
            queuedSampleCount += frameCount
        }

        func reserveQueuedBufferIndicesForCurrentGeneration() -> [QueuedBuffer] {
            guard !queuedBuffers.isEmpty else { return [] }

            var reserved = [QueuedBuffer]()
            for index in queuedBuffers.indices where queuedBuffers[index].bufferIndex == nil {
                let bufferIndex = nextBufferIndex + 1
                nextBufferIndex = bufferIndex
                queuedBuffers[index].bufferIndex = bufferIndex
                queuedBuffers[index].engineGeneration = engineGeneration
                reserved.append(queuedBuffers[index])
            }
            return reserved
        }

        func markQueuedBuffersForReschedule() {
            engineGeneration += 1
            for index in queuedBuffers.indices {
                queuedBuffers[index].bufferIndex = nil
                queuedBuffers[index].engineGeneration = nil
            }
        }

        func completeQueuedBuffer(
            bufferIndex: Int,
            engineGeneration: Int,
        ) -> QueuedBuffer? {
            guard let queueIndex = queuedBuffers.firstIndex(where: {
                $0.bufferIndex == bufferIndex && $0.engineGeneration == engineGeneration
            }) else {
                return nil
            }

            let completedBuffer = queuedBuffers.remove(at: queueIndex)
            queuedSampleCount = max(0, queuedSampleCount - completedBuffer.frameCount)
            return completedBuffer
        }
    }

    private enum RecoveryReason: String {
        case systemWake = "system_wake"
        case outputDeviceChange = "output_device_change"
        case engineConfigurationChange = "engine_configuration_change"
    }

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamingFormat: AVAudioFormat?
    private var engineSampleRate: Double?
    private var nextRequestID: UInt64 = 0
    private let traceEnabled: Bool
    private var engineConfigurationObserver: NSObjectProtocol?
    private var workspaceObservers = [NSObjectProtocol]()
    private var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain,
    )
    private var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock?
    private var lastEnvironmentInstabilityAt: Date?
    private var recoveryTask: Task<Void, Never>?
    private var isSystemSleeping = false
    private var isScreenSleeping = false
    private var isSessionActive = true
    private var playbackRecoveryReason: RecoveryReason?
    private var playbackRecoveryAttempt = 0
    private var routingArbitration = AVAudioRoutingArbiter.shared
    private var activeRequestState: RequestPlaybackState?
    private var activeEventSink: (@Sendable (PlaybackEvent) async -> Void)?
    private var activeRuntimeFailure: WorkerError?
    private var lastObservedOutputDeviceDescription: String?
    private var playbackState: PlaybackState = .idle
    private var isPlaybackPausedManually = false
    private var environmentEventSink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?
    private var shouldPlayInterJobBoop = false

    private var isPlaybackRecoveryActive: Bool {
        playbackRecoveryReason != nil || isSystemSleeping
    }

    private var shouldSuppressDrainProgressTimeout: Bool {
        if isPlaybackRecoveryActive || isScreenSleeping || !isSessionActive {
            return true
        }
        guard let lastEnvironmentInstabilityAt else { return false }

        return Date().timeIntervalSince(lastEnvironmentInstabilityAt) * 1000
            <= Double(PlaybackConfiguration.environmentInstabilityWindowMS)
    }

    init(traceEnabled: Bool = false) {
        self.traceEnabled = traceEnabled
        lastObservedOutputDeviceDescription = currentDefaultOutputDeviceDescription()
        installEngineConfigurationObserver()
        installWorkspaceObservers()
        installDefaultOutputDeviceObserver()
    }

    func setEnvironmentEventSink(
        _ sink: (@Sendable (PlaybackEnvironmentEvent) async -> Void)?,
    ) {
        environmentEventSink = sink
        guard let sink else { return }

        Task {
            await sink(PlaybackEnvironmentEvent.outputDeviceObserved(currentDevice: lastObservedOutputDeviceDescription))
        }
    }

    func prepare(sampleRate: Double) async throws -> Bool {
        let needsSetup = audioEngine == nil || playerNode == nil || engineSampleRate != sampleRate
        if needsSetup {
            try await rebuildEngine(sampleRate: sampleRate)
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
        onEvent: @escaping @Sendable (PlaybackEvent) async -> Void,
    ) async throws -> PlaybackSummary {
        _ = try await prepare(sampleRate: sampleRate)
        try await playInterJobBoopIfNeeded(sampleRate: sampleRate)

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
        var lastChunkReceivedAt: Date?
        var interChunkGapTotalMS = 0
        var interChunkGapCount = 0
        var maxInterChunkGapMS: Int?
        var lastScheduleAt: Date?
        var scheduleGapTotalMS = 0
        var scheduleGapCount = 0
        var maxScheduleGapMS: Int?
        var lastPreparedTrailingSample: Float?

        func bufferedAudioMS() -> Int {
            state.queuedAudioMS(sampleRate: sampleRate)
        }

        func scheduleQueuedBuffer(
            _ queuedBuffer: RequestPlaybackState.QueuedBuffer,
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
                if startedPlayback,
                   let bufferIndex = queuedBuffer.bufferIndex,
                   gapMS >= state.thresholdsController.thresholds.scheduleGapWarningMS {
                    await onEvent(
                        .scheduleGapWarning(
                            gapMS: gapMS,
                            bufferIndex: bufferIndex,
                            queuedAudioMS: queuedAudioBeforeMS,
                        ),
                    )
                }
            } else {
                scheduleGapMS = nil
            }
            lastScheduleAt = scheduledAt
            let currentBufferIndex = queuedBuffer.bufferIndex ?? 0
            let currentEngineGeneration = queuedBuffer.engineGeneration ?? state.engineGeneration

            let leadingAbs = Double(abs(queuedBuffer.firstSample))
            let trailingAbs = Double(abs(queuedBuffer.lastSample))
            state.maxLeadingAbsAmplitude = max(state.maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
            state.maxTrailingAbsAmplitude = max(state.maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
            if queuedBuffer.fadeInApplied {
                state.fadeInChunkCount += 1
            }
            if let lastTrailingSample = state.lastTrailingSample {
                let jump = Double(abs(queuedBuffer.firstSample - lastTrailingSample))
                state.maxBoundaryDiscontinuity = max(state.maxBoundaryDiscontinuity ?? jump, jump)
            }
            state.lastTrailingSample = queuedBuffer.lastSample

            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: sampleRate)
            let queuedAudioAfterMS = state.queuedAudioMS(sampleRate: sampleRate)
            if traceEnabled {
                await onEvent(
                    .trace(
                        PlaybackTraceEvent(
                            name: "buffer_scheduled",
                            chunkIndex: queuedBuffer.chunkIndex,
                            bufferIndex: currentBufferIndex,
                            sampleCount: queuedBuffer.frameCount,
                            durationMS: Int((Double(queuedBuffer.frameCount) / sampleRate * 1000).rounded()),
                            queuedAudioBeforeMS: queuedAudioBeforeMS,
                            queuedAudioAfterMS: queuedAudioAfterMS,
                            gapMS: scheduleGapMS,
                            isRebuffering: state.isRebuffering,
                            fadeInApplied: queuedBuffer.fadeInApplied,
                        ),
                    ),
                )
            }
            scheduleBuffer(queuedBuffer.pcmBuffer, callbackType: .dataPlayedBack) { callbackType in
                guard callbackType == .dataPlayedBack else { return }

                Task { @MainActor in
                    guard requestID + 1 == self.nextRequestID else { return }
                    guard
                        state.completeQueuedBuffer(
                            bufferIndex: currentBufferIndex,
                            engineGeneration: currentEngineGeneration,
                        ) != nil
                    else {
                        return
                    }

                    state.playedBackCallbackCount += 1
                    state.recordQueuedAudioDepth(sampleRate: sampleRate)

                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if self.traceEnabled {
                        await onEvent(
                            .trace(
                                PlaybackTraceEvent(
                                    name: "buffer_played_back",
                                    chunkIndex: queuedBuffer.chunkIndex,
                                    bufferIndex: currentBufferIndex,
                                    sampleCount: queuedBuffer.frameCount,
                                    durationMS: Int((Double(queuedBuffer.frameCount) / sampleRate * 1000).rounded()),
                                    queuedAudioBeforeMS: nil,
                                    queuedAudioAfterMS: currentQueuedAudioMS,
                                    gapMS: nil,
                                    isRebuffering: state.isRebuffering,
                                    fadeInApplied: queuedBuffer.fadeInApplied,
                                ),
                            ),
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
                                now.timeIntervalSince($0) * 1000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                            }
                            await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                        }
                        await onEvent(.starved)
                        return
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= state.thresholdsController.thresholds.lowWaterTargetMS,
                       !state.isRebuffering {
                        state.isRebuffering = true
                        state.rebufferEventCount += 1
                        state.thresholdsController.recordRebuffer()
                        let now = Date()
                        state.rebufferStartedAt = now
                        state.recentRebufferStartTimes.append(now)
                        state.recentRebufferStartTimes.removeAll {
                            now.timeIntervalSince($0) * 1000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
                        }
                        self.playerNode?.pause()
                        await onEvent(.rebufferStarted(queuedAudioMS: currentQueuedAudioMS, thresholds: state.thresholdsController.thresholds))
                        if !state.emittedRebufferThrashWarning,
                           state.recentRebufferStartTimes.count >= PlaybackMetricsConfiguration.rebufferThrashWarningCount {
                            state.emittedRebufferThrashWarning = true
                            await onEvent(
                                .rebufferThrashWarning(
                                    rebufferEventCount: state.rebufferEventCount,
                                    windowMS: PlaybackMetricsConfiguration.rebufferThrashWindowMS,
                                ),
                            )
                        }
                    }

                    if !state.generationFinished,
                       currentQueuedAudioMS <= PlaybackConfiguration.lowQueueThresholdMS,
                       !state.emittedLowQueueWarning {
                        state.emittedLowQueueWarning = true
                        await onEvent(.queueDepthLow(queuedAudioMS: currentQueuedAudioMS))
                    } else if currentQueuedAudioMS > PlaybackConfiguration.lowQueueThresholdMS {
                        state.emittedLowQueueWarning = false
                    }

                    if state.isRebuffering,
                       currentQueuedAudioMS >= state.thresholdsController.thresholds.resumeBufferTargetMS || state.generationFinished {
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

        func scheduleQueuedBuffersIfPossible() async throws {
            guard !isPlaybackRecoveryActive else { return }

            let queuedBuffers = state.reserveQueuedBufferIndicesForCurrentGeneration()
            for queuedBuffer in queuedBuffers {
                try throwIfActivePlaybackInterrupted()
                try await scheduleQueuedBuffer(queuedBuffer)
            }
        }

        do {
            for try await chunk in stream {
                try throwIfActivePlaybackInterrupted()
                guard !chunk.isEmpty else { continue }

                let now = Date()
                let chunkDurationMS = Int((Double(chunk.count) / sampleRate * 1000).rounded())
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
                                queuedAudioBeforeMS: bufferedAudioMS(),
                                queuedAudioAfterMS: nil,
                                gapMS: interChunkGapMS,
                                isRebuffering: state.isRebuffering,
                                fadeInApplied: !emittedFirstChunk,
                            ),
                        ),
                    )
                }
                if let buffer = makePCMBuffer(
                    from: chunk,
                    sampleRate: sampleRate,
                    previousTrailingSample: lastPreparedTrailingSample,
                    applyFadeIn: !emittedFirstChunk,
                ) {
                    lastPreparedTrailingSample = buffer.lastSample
                    state.enqueueBuffer(
                        buffer.buffer,
                        frameCount: buffer.frameCount,
                        firstSample: buffer.firstSample,
                        lastSample: buffer.lastSample,
                        fadeInApplied: buffer.fadeInApplied,
                        chunkIndex: chunkCount,
                    )
                    if startedPlayback {
                        try await scheduleQueuedBuffersIfPossible()
                        if state.isRebuffering {
                            let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                            if currentQueuedAudioMS >= state.thresholdsController.thresholds.resumeBufferTargetMS {
                                if !isPlaybackPausedManually, !isPlaybackRecoveryActive {
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
                    }
                }

                if !emittedFirstChunk {
                    emittedFirstChunk = true
                    timeToFirstChunkMS = milliseconds(since: startedAt)
                    await onEvent(.firstChunk)
                }

                if !startedPlayback, bufferedAudioMS() >= state.thresholdsController.thresholds.startupBufferTargetMS {
                    startupBufferedAudioMS = bufferedAudioMS()
                    startedPlayback = true
                    emittedPrerollReady = true
                    timeToPrerollReadyMS = milliseconds(since: startedAt)
                    if !isPlaybackPausedManually {
                        playbackState = .playing
                    }
                    try await scheduleQueuedBuffersIfPossible()
                    await onEvent(.prerollReady(startupBufferedAudioMS: startupBufferedAudioMS ?? 0, thresholds: state.thresholdsController.thresholds))
                }
            }

            state.generationFinished = true
            if startedPlayback, state.isRebuffering {
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
            if !startedPlayback, !state.queuedBuffers.isEmpty {
                startupBufferedAudioMS = bufferedAudioMS()
                startedPlayback = true
                try await scheduleQueuedBuffersIfPossible()
                if state.isRebuffering {
                    let currentQueuedAudioMS = state.queuedAudioMS(sampleRate: sampleRate)
                    if !isPlaybackPausedManually, !isPlaybackRecoveryActive {
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
                sampleRate: sampleRate,
            )
            if let maxBoundaryDiscontinuity = state.maxBoundaryDiscontinuity,
               let maxLeadingAbsAmplitude = state.maxLeadingAbsAmplitude,
               let maxTrailingAbsAmplitude = state.maxTrailingAbsAmplitude {
                await onEvent(
                    .bufferShapeSummary(
                        maxBoundaryDiscontinuity: maxBoundaryDiscontinuity,
                        maxLeadingAbsAmplitude: maxLeadingAbsAmplitude,
                        maxTrailingAbsAmplitude: maxTrailingAbsAmplitude,
                        fadeInChunkCount: state.fadeInChunkCount,
                    ),
                )
            }
            let timeFromPrerollReadyToDrainMS: Int? = if let timeToPrerollReadyMS {
                max(0, milliseconds(since: startedAt) - timeToPrerollReadyMS)
            } else {
                nil
            }

            resetPlayerNodeForNextRequest()
            shouldPlayInterJobBoop = true

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
                fadeInChunkCount: state.fadeInChunkCount,
            )
        } catch is CancellationError {
            resetPlayerNodeForNextRequest()
            shouldPlayInterJobBoop = false
            throw CancellationError()
        } catch {
            resetPlayerNodeForNextRequest()
            shouldPlayInterJobBoop = false
            if let workerError = error as? WorkerError {
                throw workerError
            }

            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback failed while scheduling generated audio into the local audio player. \(error.localizedDescription)",
            )
        }
    }

    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        tearDownPlaybackHardware(leavingArbitration: true)
        playbackRecoveryReason = nil
        playbackRecoveryAttempt = 0
        lastEnvironmentInstabilityAt = nil
        playbackState = .idle
        isPlaybackPausedManually = false
        shouldPlayInterJobBoop = false
        routingArbitration.leave()
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
        let queuedAudioMS = activeRequestState.queuedAudioMS(sampleRate: engineSampleRate ?? 24000)
        if !activeRequestState.isRebuffering
            || queuedAudioMS >= activeRequestState.thresholdsController.thresholds.resumeBufferTargetMS
            || activeRequestState.generationFinished {
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
        sampleRate: Double,
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
                    message: "Live playback timed out after generated audio finished because the local audio player did not report drain completion within \(drainTimeout.components.seconds) seconds.",
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
                            isPausedManually: self.isPlaybackPausedManually,
                        )
                    }

                    if snapshot.queuedAudioMS == 0 {
                        return
                    }
                    if await MainActor.run(body: { self.shouldSuppressDrainProgressTimeout }) {
                        lastProgressAt = Date()
                        continue
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

                    let stalledForMS = Int((Date().timeIntervalSince(lastProgressAt) * 1000).rounded())
                    if stalledForMS >= PlaybackConfiguration.drainProgressStallTimeoutMS {
                        throw WorkerError(
                            code: .audioPlaybackTimeout,
                            message: "Live playback stalled after generated audio finished because the local audio player stopped reporting drain progress for \(PlaybackConfiguration.drainProgressStallTimeoutMS / 1000) seconds while \(snapshot.queuedAudioMS) ms of audio remained queued.",
                        )
                    }
                }
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Engine Management

    private func rebuildEngine(sampleRate: Double) async throws {
        tearDownPlaybackHardware(leavingArbitration: true)
        try await beginRoutingArbitration()

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels,
        )

        guard let format else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback could not create an AVAudioFormat for sample rate \(sampleRate).",
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
    }

    private func tearDownPlaybackHardware(leavingArbitration: Bool) {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        streamingFormat = nil
        engineSampleRate = nil
        if leavingArbitration {
            routingArbitration.leave()
        }
    }

    private func beginRoutingArbitration() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routingArbitration.begin(category: .playback) { _, error in
                if let error {
                    continuation.resume(
                        throwing: WorkerError(
                            code: .audioPlaybackFailed,
                            message: "SpeakSwiftly could not begin macOS audio routing arbitration before starting local playback. \(error.localizedDescription)",
                        ),
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // MARK: - System Observers

    private func installEngineConfigurationObserver() {
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let engine = audioEngine else { return }

                let engineIsRunning = engine.isRunning
                markEnvironmentInstability()
                if let environmentEventSink {
                    await environmentEventSink(.engineConfigurationChanged(engineIsRunning: engineIsRunning))
                }
                if let activeEventSink {
                    await activeEventSink(.engineConfigurationChanged(engineIsRunning: engineIsRunning))
                }
                beginPlaybackRecovery(reason: .engineConfigurationChange)
            }
        }
    }

    private func installWorkspaceObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemSleepStateChange(isSleeping: true)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemSleepStateChange(isSleeping: false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenSleepStateChange(isSleeping: true)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenSleepStateChange(isSleeping: false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSessionActivityChange(isActive: false)
                }
            },
        )
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: nil,
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSessionActivityChange(isActive: true)
                }
            },
        )
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
            listener,
        )
    }

    private func handleDefaultOutputDeviceChange() {
        let previousDevice = lastObservedOutputDeviceDescription
        let currentDevice = currentDefaultOutputDeviceDescription()
        guard previousDevice != currentDevice else { return }

        lastObservedOutputDeviceDescription = currentDevice
        markEnvironmentInstability()

        if let environmentEventSink {
            Task {
                await environmentEventSink(
                    .outputDeviceChanged(previousDevice: previousDevice, currentDevice: currentDevice),
                )
            }
        }

        if let activeEventSink {
            Task {
                await activeEventSink(
                    .outputDeviceChanged(previousDevice: previousDevice, currentDevice: currentDevice),
                )
            }
        }

        beginPlaybackRecovery(reason: .outputDeviceChange)
    }

    private func handleSystemSleepStateChange(isSleeping: Bool) {
        isSystemSleeping = isSleeping
        markEnvironmentInstability()
        emitEnvironmentEvent(.systemSleepStateChanged(isSleeping: isSleeping))

        guard activeRequestState != nil else { return }

        if isSleeping {
            playerNode?.pause()
            return
        }

        beginPlaybackRecovery(reason: .systemWake)
    }

    private func handleScreenSleepStateChange(isSleeping: Bool) {
        isScreenSleeping = isSleeping
        markEnvironmentInstability()
        emitEnvironmentEvent(.screenSleepStateChanged(isSleeping: isSleeping))
    }

    private func handleSessionActivityChange(isActive: Bool) {
        isSessionActive = isActive
        markEnvironmentInstability()
        emitEnvironmentEvent(.sessionActivityChanged(isActive: isActive))
    }

    private func emitEnvironmentEvent(_ event: PlaybackEnvironmentEvent) {
        guard let environmentEventSink else { return }

        Task {
            await environmentEventSink(event)
        }
    }

    private func markEnvironmentInstability() {
        lastEnvironmentInstabilityAt = Date()
    }

    private func beginPlaybackRecovery(reason: RecoveryReason) {
        guard let activeRequestState else { return }
        guard activeRuntimeFailure == nil else { return }
        guard !isSystemSleeping || reason == .systemWake else { return }

        recoveryTask?.cancel()
        playbackRecoveryReason = reason
        playbackRecoveryAttempt = 0
        activeRequestState.markQueuedBuffersForReschedule()
        playerNode?.pause()
        emitEnvironmentEvent(
            .recoveryStateChanged(
                reason: reason.rawValue,
                stage: "scheduled",
                attempt: nil,
                currentDevice: lastObservedOutputDeviceDescription,
            ),
        )

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await performPlaybackRecovery(reason: reason)
        }
    }

    private func performPlaybackRecovery(reason: RecoveryReason) async {
        guard let activeRequestState else {
            playbackRecoveryReason = nil
            return
        }
        guard let sampleRate = engineSampleRate else {
            interruptActivePlayback(
                with: WorkerError(
                    code: .audioPlaybackFailed,
                    message: "SpeakSwiftly could not recover local playback after a \(reason.rawValue) event because the active playback sample rate was no longer available.",
                ),
            )
            return
        }

        while playbackRecoveryAttempt < PlaybackConfiguration.recoveryMaximumAttempts {
            playbackRecoveryAttempt += 1
            let attempt = playbackRecoveryAttempt
            emitEnvironmentEvent(
                .recoveryStateChanged(
                    reason: reason.rawValue,
                    stage: "attempting",
                    attempt: attempt,
                    currentDevice: lastObservedOutputDeviceDescription,
                ),
            )

            do {
                try await Task.sleep(for: .milliseconds(PlaybackConfiguration.recoveryStabilizationDelayMS))
                try Task.checkCancellation()
                try await rebuildEngine(sampleRate: sampleRate)
                activeRequestState.markQueuedBuffersForReschedule()
                try await rescheduleActiveRequestBuffers(activeRequestState)
                if !isPlaybackPausedManually,
                   !activeRequestState.isRebuffering,
                   !isSystemSleeping {
                    playerNode?.play()
                }
                playbackRecoveryReason = nil
                playbackRecoveryAttempt = 0
                emitEnvironmentEvent(
                    .recoveryStateChanged(
                        reason: reason.rawValue,
                        stage: "recovered",
                        attempt: attempt,
                        currentDevice: lastObservedOutputDeviceDescription,
                    ),
                )
                return
            } catch is CancellationError {
                return
            } catch {
                markEnvironmentInstability()
                emitEnvironmentEvent(
                    .recoveryStateChanged(
                        reason: reason.rawValue,
                        stage: "attempt_failed",
                        attempt: attempt,
                        currentDevice: lastObservedOutputDeviceDescription,
                    ),
                )
            }
        }

        interruptActivePlayback(
            with: WorkerError(
                code: .audioPlaybackFailed,
                message: "Live playback could not recover after macOS reported a \(reason.rawValue) event. SpeakSwiftly attempted to rebuild the audio engine \(PlaybackConfiguration.recoveryMaximumAttempts) times, but the output route never stabilized enough to resume the active request.",
            ),
        )
    }

    private func rescheduleActiveRequestBuffers(_ state: RequestPlaybackState) async throws {
        let queuedBuffers = state.reserveQueuedBufferIndicesForCurrentGeneration()
        for queuedBuffer in queuedBuffers {
            try throwIfActivePlaybackInterrupted()
            scheduleBuffer(queuedBuffer.pcmBuffer, callbackType: .dataPlayedBack) { [weak self] callbackType in
                guard callbackType == .dataPlayedBack else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard state.completeQueuedBuffer(
                        bufferIndex: queuedBuffer.bufferIndex ?? 0,
                        engineGeneration: queuedBuffer.engineGeneration ?? state.engineGeneration,
                    ) != nil else {
                        return
                    }

                    state.playedBackCallbackCount += 1
                    state.recordQueuedAudioDepth(sampleRate: engineSampleRate ?? 24000)
                    if state.generationFinished, state.queuedSampleCount == 0 {
                        state.drainContinuation?.resume()
                        state.drainContinuation = nil
                    }
                }
            }
            state.scheduleCallbackCount += 1
            state.recordQueuedAudioDepth(sampleRate: engineSampleRate ?? 24000)
        }
    }

    // MARK: - Interruption Handling

    private func interruptActivePlayback(with error: WorkerError) {
        guard activeRequestState != nil else { return }
        guard activeRuntimeFailure == nil else { return }

        activeRuntimeFailure = error
        shouldPlayInterJobBoop = false
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
            mElement: kAudioObjectPropertyElementMain,
        )
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &dataSize,
            &deviceID,
        )

        guard deviceStatus == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }

        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.stride)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        let nameStatus = withUnsafeMutablePointer(to: &deviceName) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                UnsafeMutableRawPointer(pointer),
            )
        }

        if nameStatus == noErr {
            let name = "\(deviceName)"
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
        applyFadeIn: Bool,
    ) -> (buffer: AVAudioPCMBuffer, frameCount: Int, firstSample: Float, lastSample: Float, fadeInApplied: Bool)? {
        guard let format = streamingFormat ?? AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: PlaybackConfiguration.channels,
        ) else {
            return nil
        }

        let processedSamples = shapePlaybackSamples(
            samples,
            sampleRate: format.sampleRate,
            previousTrailingSample: previousTrailingSample,
            applyFadeIn: applyFadeIn,
        )
        guard let firstSample = processedSamples.first, let lastSample = processedSamples.last else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(processedSamples.count),
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(processedSamples.count)
        if let channelData = buffer.floatChannelData {
            processedSamples.withUnsafeBufferPointer { src in
                guard let baseAddress = src.baseAddress else {
                    return
                }

                channelData[0].update(from: baseAddress, count: processedSamples.count)
            }
        }

        return (
            buffer: buffer,
            frameCount: Int(buffer.frameLength),
            firstSample: firstSample,
            lastSample: lastSample,
            fadeInApplied: applyFadeIn,
        )
    }

    private func scheduleBuffer(
        _ buffer: AVAudioPCMBuffer,
        callbackType: AVAudioPlayerNodeCompletionCallbackType,
        completion: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void,
    ) {
        playerNode?.scheduleBuffer(
            buffer,
            completionCallbackType: callbackType,
            completionHandler: completion,
        )
    }

    // MARK: - Inter-Job Boop

    private func playInterJobBoopIfNeeded(sampleRate: Double) async throws {
        guard shouldPlayInterJobBoop else { return }

        shouldPlayInterJobBoop = false

        guard
            let buffer = makePCMBuffer(
                from: makeInterJobBoopSamples(sampleRate: sampleRate),
                sampleRate: sampleRate,
                previousTrailingSample: nil,
                applyFadeIn: false,
            )?.buffer
        else {
            throw WorkerError(
                code: .audioPlaybackFailed,
                message: "SpeakSwiftly could not synthesize the short inter-job playback boop buffer for sample rate \(sampleRate).",
            )
        }

        if playerNode?.isPlaying == false {
            playerNode?.play()
        }

        let playbackTask = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                scheduleBuffer(buffer, callbackType: .dataPlayedBack) { callbackType in
                    guard callbackType == .dataPlayedBack else { return }

                    continuation.resume()
                }
            }
        }
        defer { playbackTask.cancel() }

        let timeoutTask = Task {
            try await Task.sleep(for: PlaybackConfiguration.interJobBoopTimeout)
            throw WorkerError(
                code: .audioPlaybackTimeout,
                message: "SpeakSwiftly timed out while trying to play the short inter-job playback boop before the next live request could begin.",
            )
        }
        defer { timeoutTask.cancel() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await playbackTask.value }
            group.addTask { try await timeoutTask.value }

            _ = try await group.next()
            group.cancelAll()
        }

        if let environmentEventSink {
            await environmentEventSink(
                .interJobBoopPlayed(
                    durationMS: PlaybackConfiguration.interJobBoopDurationMS,
                    frequencyHz: PlaybackConfiguration.interJobBoopFrequencyHz,
                    sampleRate: sampleRate,
                ),
            )
        }
    }
}

// MARK: - Sample Shaping

func makeInterJobBoopSamples(sampleRate: Double) -> [Float] {
    let sampleCount = max(
        1,
        Int((sampleRate * Double(AudioPlaybackDriver.PlaybackConfiguration.interJobBoopDurationMS)) / 1000.0),
    )
    let fadeSampleCount = max(
        1,
        Int((sampleRate * Double(AudioPlaybackDriver.PlaybackConfiguration.interJobBoopFadeMS)) / 1000.0),
    )

    return (0..<sampleCount).map { index in
        let time = Double(index) / sampleRate
        let phase = 2.0 * Double.pi * AudioPlaybackDriver.PlaybackConfiguration.interJobBoopFrequencyHz * time
        let fadeEnvelope: Double = if index < fadeSampleCount {
            Double(index) / Double(fadeSampleCount)
        } else if index >= sampleCount - fadeSampleCount {
            Double(sampleCount - index) / Double(fadeSampleCount)
        } else {
            1
        }

        return Float(sin(phase) * fadeEnvelope) * AudioPlaybackDriver.PlaybackConfiguration.interJobBoopAmplitude
    }
}

func shapePlaybackSamples(
    _ samples: [Float],
    sampleRate: Double,
    previousTrailingSample: Float?,
    applyFadeIn: Bool,
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
                        maximumSampleValue,
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

func milliseconds(since start: Date) -> Int {
    Int((Date().timeIntervalSince(start) * 1000).rounded())
}
