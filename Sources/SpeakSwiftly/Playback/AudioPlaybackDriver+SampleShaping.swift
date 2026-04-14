import Foundation

// MARK: - Sample Shaping

func makeInterJobBoopSamples(sampleRate: Double) -> [Float] {
    let sampleCount = max(
        1,
        Int((sampleRate * Double(AudioPlaybackConfiguration.interJobBoopDurationMS)) / 1000.0),
    )
    let fadeSampleCount = max(
        1,
        Int((sampleRate * Double(AudioPlaybackConfiguration.interJobBoopFadeMS)) / 1000.0),
    )

    return (0..<sampleCount).map { index in
        let time = Double(index) / sampleRate
        let phase = 2.0 * Double.pi * AudioPlaybackConfiguration.interJobBoopFrequencyHz * time
        let fadeEnvelope: Double = if index < fadeSampleCount {
            Double(index) / Double(fadeSampleCount)
        } else if index >= sampleCount - fadeSampleCount {
            Double(sampleCount - index) / Double(fadeSampleCount)
        } else {
            1
        }

        return Float(sin(phase) * fadeEnvelope) * AudioPlaybackConfiguration.interJobBoopAmplitude
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
