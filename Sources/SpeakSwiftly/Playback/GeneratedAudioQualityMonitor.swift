import Foundation

struct GeneratedAudioQualityObservation: Equatable {
    let chunkIndex: Int
    let sampleCount: Int
    let generatedDurationMS: Int
    let totalGeneratedDurationMS: Int
    let peakAmplitude: Double
    let rmsAmplitude: Double
    let nearSilenceRatio: Double
    let clippingRatio: Double
    let nonFiniteSampleCount: Int
    let dcOffset: Double
    let zeroCrossingRate: Double
    let boundaryJump: Double?
    let repeatedWindowSimilarity: Double?
}

enum GeneratedAudioQualityWarningReason: String, Hashable {
    case nonFiniteSamples = "non_finite_samples"
    case clipping
    case repeatedNonSilentWindow = "repeated_non_silent_window"
    case excessiveGeneratedDuration = "excessive_generated_duration"
    case dcOffset = "dc_offset"
}

struct GeneratedAudioQualityWarning: Equatable {
    let reason: GeneratedAudioQualityWarningReason
    let message: String
    let observation: GeneratedAudioQualityObservation
}

struct GeneratedAudioQualityMonitor {
    private enum WarningThresholds {
        static let clippingRatio = 0.005
        static let repeatedWindowSimilarity = 0.995
        static let repeatedWindowMinimumRMSAmplitude = 0.02
        static let repeatedWindowMinimumPeakAmplitude = 0.08
        static let repeatedWindowMinimumGeneratedDurationMS = 10000
        static let excessiveGeneratedDurationMS = 90000
        static let dcOffset = 0.2
    }

    private let sampleRate: Double
    private let nearSilenceThreshold: Float
    private let clippingThreshold: Float
    private let repeatedWindowSampleCount: Int

    private var totalSampleCount = 0
    private var previousTrailingSample: Float?
    private var previousWindow = [Float]()

    init(
        sampleRate: Double,
        nearSilenceThreshold: Float = 0.001,
        clippingThreshold: Float = 0.999,
        repeatedWindowSampleCount: Int = 2048,
    ) {
        self.sampleRate = sampleRate
        self.nearSilenceThreshold = nearSilenceThreshold
        self.clippingThreshold = clippingThreshold
        self.repeatedWindowSampleCount = max(repeatedWindowSampleCount, 1)
    }

    mutating func observe(samples: [Float], chunkIndex: Int) -> GeneratedAudioQualityObservation {
        totalSampleCount += samples.count

        var finiteSampleCount = 0
        var nonFiniteSampleCount = 0
        var nearSilenceSampleCount = 0
        var clippingSampleCount = 0
        var peakAmplitude = 0.0
        var sum = 0.0
        var squaredSum = 0.0
        var firstFiniteSample: Float?
        var lastFiniteSample: Float?
        var previousNonZeroSign: Int?
        var zeroCrossingCount = 0
        var nonZeroSignCount = 0

        for sample in samples {
            guard sample.isFinite else {
                nonFiniteSampleCount += 1
                continue
            }

            finiteSampleCount += 1
            firstFiniteSample = firstFiniteSample ?? sample
            lastFiniteSample = sample

            let absSample = abs(sample)
            if absSample <= nearSilenceThreshold {
                nearSilenceSampleCount += 1
            }
            if absSample >= clippingThreshold {
                clippingSampleCount += 1
            }

            let doubleSample = Double(sample)
            peakAmplitude = max(peakAmplitude, Double(absSample))
            sum += doubleSample
            squaredSum += doubleSample * doubleSample

            let sign = signum(sample)
            guard sign != 0 else { continue }

            nonZeroSignCount += 1
            if let previousNonZeroSign, previousNonZeroSign != sign {
                zeroCrossingCount += 1
            }
            previousNonZeroSign = sign
        }

        let boundaryJump: Double? = if let previousTrailingSample, let firstFiniteSample {
            Double(abs(firstFiniteSample - previousTrailingSample))
        } else {
            nil
        }
        previousTrailingSample = lastFiniteSample ?? previousTrailingSample

        let currentWindow = trailingWindow(from: samples)
        let repeatedWindowSimilarity = similarity(between: previousWindow, and: currentWindow)
        if !currentWindow.isEmpty {
            previousWindow = currentWindow
        }

        let sampleDenominator = Double(max(samples.count, 1))
        let finiteDenominator = Double(max(finiteSampleCount, 1))
        let crossingDenominator = Double(max(nonZeroSignCount - 1, 1))

        return GeneratedAudioQualityObservation(
            chunkIndex: chunkIndex,
            sampleCount: samples.count,
            generatedDurationMS: durationMS(sampleCount: samples.count),
            totalGeneratedDurationMS: durationMS(sampleCount: totalSampleCount),
            peakAmplitude: peakAmplitude,
            rmsAmplitude: sqrt(squaredSum / finiteDenominator),
            nearSilenceRatio: Double(nearSilenceSampleCount) / sampleDenominator,
            clippingRatio: Double(clippingSampleCount) / sampleDenominator,
            nonFiniteSampleCount: nonFiniteSampleCount,
            dcOffset: sum / finiteDenominator,
            zeroCrossingRate: Double(zeroCrossingCount) / crossingDenominator,
            boundaryJump: boundaryJump,
            repeatedWindowSimilarity: repeatedWindowSimilarity,
        )
    }

    func warning(for observation: GeneratedAudioQualityObservation) -> GeneratedAudioQualityWarning? {
        if observation.nonFiniteSampleCount > 0 {
            return GeneratedAudioQualityWarning(
                reason: .nonFiniteSamples,
                message: "SpeakSwiftly detected non-finite generated audio samples before playback scheduling. This usually means the speech backend emitted invalid floating-point audio.",
                observation: observation,
            )
        }

        if observation.clippingRatio >= WarningThresholds.clippingRatio {
            return GeneratedAudioQualityWarning(
                reason: .clipping,
                message: "SpeakSwiftly detected clipped generated audio before playback scheduling. This can sound distorted and may indicate an unstable generation tail.",
                observation: observation,
            )
        }

        if let repeatedWindowSimilarity = observation.repeatedWindowSimilarity,
           repeatedWindowSimilarity >= WarningThresholds.repeatedWindowSimilarity,
           observation.rmsAmplitude >= WarningThresholds.repeatedWindowMinimumRMSAmplitude,
           observation.peakAmplitude >= WarningThresholds.repeatedWindowMinimumPeakAmplitude,
           observation.totalGeneratedDurationMS >= WarningThresholds.repeatedWindowMinimumGeneratedDurationMS {
            return GeneratedAudioQualityWarning(
                reason: .repeatedNonSilentWindow,
                message: "SpeakSwiftly detected a repeated non-silent generated audio window before playback scheduling. This can indicate a looping or runaway speech generation.",
                observation: observation,
            )
        }

        if observation.totalGeneratedDurationMS >= WarningThresholds.excessiveGeneratedDurationMS {
            return GeneratedAudioQualityWarning(
                reason: .excessiveGeneratedDuration,
                message: "SpeakSwiftly detected unusually long generated audio before playback finished. This can indicate a runaway speech generation when the requested text is not long enough to justify the duration.",
                observation: observation,
            )
        }

        if abs(observation.dcOffset) >= WarningThresholds.dcOffset {
            return GeneratedAudioQualityWarning(
                reason: .dcOffset,
                message: "SpeakSwiftly detected a high DC offset in generated audio before playback scheduling. This can indicate an unstable waveform that may produce audible artifacts.",
                observation: observation,
            )
        }

        return nil
    }

    private func durationMS(sampleCount: Int) -> Int {
        Int((Double(sampleCount) / sampleRate * 1000).rounded())
    }

    private func trailingWindow(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }

        return samples.suffix(repeatedWindowSampleCount).map { sample in
            sample.isFinite ? sample : .zero
        }
    }

    private func similarity(between lhs: [Float], and rhs: [Float]) -> Double? {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return nil }

        var dotProduct = 0.0
        var lhsMagnitudeSquared = 0.0
        var rhsMagnitudeSquared = 0.0

        let lhsSuffix = lhs.suffix(count)
        let rhsSuffix = rhs.suffix(count)
        for (lhsSample, rhsSample) in zip(lhsSuffix, rhsSuffix) {
            let lhsValue = Double(lhsSample)
            let rhsValue = Double(rhsSample)
            dotProduct += lhsValue * rhsValue
            lhsMagnitudeSquared += lhsValue * lhsValue
            rhsMagnitudeSquared += rhsValue * rhsValue
        }

        guard lhsMagnitudeSquared > 0, rhsMagnitudeSquared > 0 else { return nil }

        return dotProduct / (sqrt(lhsMagnitudeSquared) * sqrt(rhsMagnitudeSquared))
    }

    private func signum(_ sample: Float) -> Int {
        if sample > 0 { return 1 }
        if sample < 0 { return -1 }
        return 0
    }
}
