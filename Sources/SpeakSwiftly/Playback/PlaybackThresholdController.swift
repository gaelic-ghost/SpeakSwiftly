import Foundation

enum PlaybackComplexityClass: String {
    case compact
    case balanced
    case extended
}

enum PlaybackTuningProfile: Equatable {
    case standard
    case firstDrainedLiveMarvis
}

struct PlaybackAdaptiveThresholds: Equatable {
    let complexityClass: PlaybackComplexityClass
    let startupBufferTargetMS: Int
    let lowWaterTargetMS: Int
    let resumeBufferTargetMS: Int
    let chunkGapWarningMS: Int
    let scheduleGapWarningMS: Int
}

enum PlaybackPhase: String {
    case warmup
    case steady
    case recovery
}

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

    private let tuningProfile: PlaybackTuningProfile

    private var chunkDurationsMS = [Int]()
    private var interChunkGapsMS = [Int]()
    private var rebufferCount = 0
    private var starvationCount = 0
    private var stableChunkStreak = 0
    private var preRebufferScheduleGapWarnings = 0
    private var startupBufferFloorMS: Int
    private var lowWaterFloorMS: Int
    private var resumeBufferFloorMS: Int
    private var chunkGapWarningFloorMS: Int
    private var scheduleGapWarningFloorMS: Int

    init(text: String, tuningProfile: PlaybackTuningProfile = .standard) {
        self.tuningProfile = tuningProfile
        thresholds = Self.seedThresholds(for: text, phase: .warmup, tuningProfile: tuningProfile)
        startupBufferFloorMS = thresholds.startupBufferTargetMS
        lowWaterFloorMS = thresholds.lowWaterTargetMS
        resumeBufferFloorMS = thresholds.resumeBufferTargetMS
        chunkGapWarningFloorMS = thresholds.chunkGapWarningMS
        scheduleGapWarningFloorMS = thresholds.scheduleGapWarningMS
    }

    private static func seedThresholds(
        for text: String,
        phase: PlaybackPhase,
        tuningProfile: PlaybackTuningProfile,
    ) -> PlaybackAdaptiveThresholds {
        seededThresholds(for: classify(text: text), phase: phase, tuningProfile: tuningProfile)
    }

    private static func seededThresholds(
        for complexityClass: PlaybackComplexityClass,
        phase: PlaybackPhase,
        tuningProfile: PlaybackTuningProfile,
    ) -> PlaybackAdaptiveThresholds {
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
        let tuningBias = tuningThresholdBias(for: complexityClass, phase: phase, tuningProfile: tuningProfile)
        return PlaybackAdaptiveThresholds(
            complexityClass: base.complexityClass,
            startupBufferTargetMS: min(
                Self.maxStartupBufferTargetMS,
                base.startupBufferTargetMS + phaseBias.startupBufferMS + tuningBias.startupBufferMS,
            ),
            lowWaterTargetMS: min(
                Self.maxLowWaterTargetMS,
                base.lowWaterTargetMS + phaseBias.lowWaterMS + tuningBias.lowWaterMS,
            ),
            resumeBufferTargetMS: min(
                Self.maxResumeBufferTargetMS,
                base.resumeBufferTargetMS + phaseBias.resumeBufferMS + tuningBias.resumeBufferMS,
            ),
            chunkGapWarningMS: min(
                Self.maxChunkGapWarningMS,
                base.chunkGapWarningMS + phaseBias.chunkGapWarningMS + tuningBias.chunkGapWarningMS,
            ),
            scheduleGapWarningMS: min(
                Self.maxScheduleGapWarningMS,
                base.scheduleGapWarningMS + phaseBias.scheduleGapWarningMS + tuningBias.scheduleGapWarningMS,
            ),
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

    private static func tuningThresholdBias(
        for complexityClass: PlaybackComplexityClass,
        phase: PlaybackPhase,
        tuningProfile: PlaybackTuningProfile,
    ) -> (
        startupBufferMS: Int,
        lowWaterMS: Int,
        resumeBufferMS: Int,
        chunkGapWarningMS: Int,
        scheduleGapWarningMS: Int,
    ) {
        guard tuningProfile == .firstDrainedLiveMarvis else {
            return (0, 0, 0, 0, 0)
        }

        return switch (complexityClass, phase) {
            case (.compact, .warmup):
                (960, 420, 1160, 0, 0)
            case (.balanced, .warmup):
                (1600, 700, 1900, 0, 0)
            case (.compact, .recovery):
                (600, 240, 760, 0, 0)
            case (.balanced, .recovery):
                (1000, 420, 1260, 0, 0)
            case (_, .steady), (.extended, _):
                (0, 0, 0, 0, 0)
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

        let seeded = Self.seededThresholds(
            for: thresholds.complexityClass,
            phase: phase,
            tuningProfile: tuningProfile,
        )
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
        preRebufferScheduleGapWarnings = 0

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
        preRebufferScheduleGapWarnings = 0

        let avgChunkDurationMS = average(chunkDurationsMS) ?? Self.defaultChunkDurationMS
        let avgInterChunkGapMS = average(interChunkGapsMS) ?? max(avgChunkDurationMS, Self.defaultChunkDurationMS)
        let maxInterChunkGapMS = interChunkGapsMS.max() ?? avgInterChunkGapMS
        let jitterMS = max(maxInterChunkGapMS - avgInterChunkGapMS, 0)
        let cadenceDeficitMS = max(avgInterChunkGapMS - avgChunkDurationMS, 0)
        let immediateRecoveryPenalty = tuningProfile == .firstDrainedLiveMarvis ? 1 : 0
        let effectiveRebufferCount = max(rebufferCount - 1, immediateRecoveryPenalty)
        guard effectiveRebufferCount > 0 else { return }

        let rebufferPenaltyMS = max(avgChunkDurationMS / 2, 40) * effectiveRebufferCount
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

    mutating func recordScheduleGapDistress(gapMS: Int, queuedAudioMS: Int) {
        let avgChunkDurationMS = average(chunkDurationsMS) ?? Self.defaultChunkDurationMS
        let avgInterChunkGapMS = average(interChunkGapsMS) ?? max(avgChunkDurationMS, Self.defaultChunkDurationMS)
        let severeGapFloorMS = thresholds.scheduleGapWarningMS + max(avgChunkDurationMS / 3, 24)
        let distressRiskBandMS = thresholds.lowWaterTargetMS + max(avgChunkDurationMS * 6, thresholds.lowWaterTargetMS)

        guard queuedAudioMS <= distressRiskBandMS else {
            preRebufferScheduleGapWarnings = 0
            return
        }
        guard gapMS >= severeGapFloorMS else { return }

        preRebufferScheduleGapWarnings += 1
        let requiredWarningCount = tuningProfile == .firstDrainedLiveMarvis ? 2 : 3
        guard preRebufferScheduleGapWarnings >= requiredWarningCount else { return }

        preRebufferScheduleGapWarnings = 0
        phase = .recovery
        stableChunkStreak = 0

        let distressPenaltyMS = max(avgChunkDurationMS / 2, 40) * (tuningProfile == .firstDrainedLiveMarvis ? 2 : 1)
        let lowWaterTargetMS = min(
            Self.maxLowWaterTargetMS,
            max(
                thresholds.lowWaterTargetMS,
                lowWaterFloorMS,
                queuedAudioMS + avgChunkDurationMS + distressPenaltyMS,
            ),
        )
        let resumeBufferTargetMS = min(
            Self.maxResumeBufferTargetMS,
            max(
                thresholds.resumeBufferTargetMS,
                resumeBufferFloorMS,
                lowWaterTargetMS + max(avgChunkDurationMS * 3, avgInterChunkGapMS * 2) + distressPenaltyMS * 2,
            ),
        )
        let startupBufferTargetMS = min(
            Self.maxStartupBufferTargetMS,
            max(thresholds.startupBufferTargetMS, startupBufferFloorMS, resumeBufferTargetMS),
        )
        let scheduleGapWarningMS = min(
            Self.maxScheduleGapWarningMS,
            max(thresholds.scheduleGapWarningMS, scheduleGapWarningFloorMS, severeGapFloorMS + distressPenaltyMS / 2),
        )

        applyThresholds(
            PlaybackAdaptiveThresholds(
                complexityClass: thresholds.complexityClass,
                startupBufferTargetMS: startupBufferTargetMS,
                lowWaterTargetMS: lowWaterTargetMS,
                resumeBufferTargetMS: resumeBufferTargetMS,
                chunkGapWarningMS: thresholds.chunkGapWarningMS,
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
        preRebufferScheduleGapWarnings = 0
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
