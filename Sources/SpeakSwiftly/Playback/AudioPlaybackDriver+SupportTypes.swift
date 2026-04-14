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

// MARK: - AudioPlaybackRequestState

@MainActor
final class AudioPlaybackRequestState {
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

// MARK: - AudioPlaybackRecoveryReason

enum AudioPlaybackRecoveryReason: String {
    case systemWake = "system_wake"
    case outputDeviceChange = "output_device_change"
    case engineConfigurationChange = "engine_configuration_change"
}
