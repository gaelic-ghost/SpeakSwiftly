import Foundation

public struct VolumeWindow: Codable, Equatable {
    public let index: Int
    public let startSeconds: Double
    public let durationSeconds: Double
    public let rms: Double
    public let peak: Double
}

public struct VolumeBucket: Codable, Equatable {
    public let label: String
    public let startWindow: Int
    public let endWindow: Int
    public let averageRMS: Double
    public let averagePeak: Double
}

public struct VolumeSummary: Codable, Equatable {
    public let durationSeconds: Double
    public let sampleCount: Int
    public let sampleRate: Int
    public let windowSeconds: Double
    public let windowCount: Int
    public let firstRMS: Double
    public let lastRMS: Double
    public let endpointRMSDeltaPercent: Double
    public let slopePerWindow: Double
    public let firstPeak: Double
    public let lastPeak: Double
    public let headRMS: Double
    public let tailRMS: Double
    public let tailHeadRatio: Double
    public let lastWindowAverageCount: Int
    public let lastWindowAverageRMS: Double
    public let buckets: [VolumeBucket]
}

public struct ProbeAnalysis: Codable, Equatable {
    public let sampleRate: Int
    public let sampleCount: Int
    public let durationSeconds: Double
    public let windowSeconds: Double
    public let analyzedSampleStart: Int
    public let analyzedSampleCount: Int
    public let windows: [VolumeWindow]
    public let summary: VolumeSummary?
}

public struct ParsedFloatWAV: Equatable {
    public let sampleRate: Int
    public let channelCount: Int
    public let samples: [Float]
}

public enum VolumeProbeAnalysisError: LocalizedError, Equatable {
    case invalidAnalysisInput(String)
    case invalidWAV(String)

    public var errorDescription: String? {
        switch self {
            case let .invalidAnalysisInput(message):
                message
            case let .invalidWAV(message):
                message
        }
    }
}

public func analyzeVolume(
    samples: [Float],
    sampleRate: Int,
    windowSeconds: Double,
    maxSampleCount: Int? = nil,
) throws -> ProbeAnalysis {
    guard sampleRate > 0 else {
        throw VolumeProbeAnalysisError.invalidAnalysisInput("SpeakSwiftlyTesting could not analyze volume because sampleRate must be greater than zero.")
    }
    guard windowSeconds > 0 else {
        throw VolumeProbeAnalysisError.invalidAnalysisInput("SpeakSwiftlyTesting could not analyze volume because windowSeconds must be greater than zero.")
    }

    if let maxSampleCount, maxSampleCount < 0 {
        throw VolumeProbeAnalysisError.invalidAnalysisInput("SpeakSwiftlyTesting could not analyze volume because maxSampleCount must be zero or greater.")
    }

    let analyzedSampleCount = min(maxSampleCount ?? samples.count, samples.count)
    let analyzedSamples = Array(samples.prefix(analyzedSampleCount))
    let durationSeconds = Double(analyzedSampleCount) / Double(sampleRate)
    let framesPerWindow = max(1, Int((Double(sampleRate) * windowSeconds).rounded()))
    var windows = [VolumeWindow]()
    windows.reserveCapacity(max(1, analyzedSamples.count / framesPerWindow))

    var index = 0
    var start = 0
    while start < analyzedSamples.count {
        let end = min(start + framesPerWindow, analyzedSamples.count)
        let segment = Array(analyzedSamples[start..<end])
        let durationSeconds = Double(segment.count) / Double(sampleRate)
        let rms = rootMeanSquare(segment)
        let peak = segment.map { abs($0) }.max() ?? 0
        windows.append(
            VolumeWindow(
                index: index + 1,
                startSeconds: Double(start) / Double(sampleRate),
                durationSeconds: durationSeconds,
                rms: rms,
                peak: Double(peak),
            ),
        )
        index += 1
        start = end
    }

    return ProbeAnalysis(
        sampleRate: sampleRate,
        sampleCount: samples.count,
        durationSeconds: Double(samples.count) / Double(sampleRate),
        windowSeconds: windowSeconds,
        analyzedSampleStart: 0,
        analyzedSampleCount: analyzedSampleCount,
        windows: windows,
        summary: summarizeWindows(
            windows,
            durationSeconds: durationSeconds,
            sampleCount: analyzedSampleCount,
            sampleRate: sampleRate,
            windowSeconds: windowSeconds,
        ),
    )
}

public func analyzeVolume(
    at path: String,
    windowSeconds: Double,
    maxSampleCount: Int? = nil,
) throws -> ProbeAnalysis {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let wav = try parseFloatWAV(data)
    return try analyzeVolume(
        samples: wav.samples,
        sampleRate: wav.sampleRate,
        windowSeconds: windowSeconds,
        maxSampleCount: maxSampleCount,
    )
}

public func rootMeanSquare(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }

    let sum = samples.reduce(into: 0.0) { partialResult, sample in
        let value = Double(sample)
        partialResult += value * value
    }
    return Foundation.sqrt(sum / Double(samples.count))
}

public func summarizeWindows(
    _ windows: [VolumeWindow],
    durationSeconds: Double,
    sampleCount: Int,
    sampleRate: Int,
    windowSeconds: Double,
) -> VolumeSummary? {
    guard let first = windows.first, let last = windows.last else { return nil }

    let firstRMS = first.rms
    let lastRMS = last.rms
    let endpointRMSDeltaPercent = firstRMS == 0 ? 0 : ((lastRMS - firstRMS) / firstRMS) * 100.0
    let slopePerWindow = linearSlopePerWindow(windows)
    let bucketSize = max(1, Int(Foundation.ceil(Double(windows.count) / 4.0)))
    let buckets = makeBuckets(windows, bucketSize: bucketSize)
    let headWindows = Array(windows.prefix(bucketSize))
    let tailWindows = Array(windows.suffix(bucketSize))
    let headRMS = average(headWindows.map(\.rms))
    let tailRMS = average(tailWindows.map(\.rms))
    let lastWindowAverageCount = min(3, windows.count)
    let lastWindowAverageRMS = average(windows.suffix(lastWindowAverageCount).map(\.rms))

    return VolumeSummary(
        durationSeconds: durationSeconds,
        sampleCount: sampleCount,
        sampleRate: sampleRate,
        windowSeconds: windowSeconds,
        windowCount: windows.count,
        firstRMS: firstRMS,
        lastRMS: lastRMS,
        endpointRMSDeltaPercent: endpointRMSDeltaPercent,
        slopePerWindow: slopePerWindow,
        firstPeak: first.peak,
        lastPeak: last.peak,
        headRMS: headRMS,
        tailRMS: tailRMS,
        tailHeadRatio: headRMS == 0 ? 0 : tailRMS / headRMS,
        lastWindowAverageCount: lastWindowAverageCount,
        lastWindowAverageRMS: lastWindowAverageRMS,
        buckets: buckets,
    )
}

public func parseFloatWAV(_ data: Data) throws -> ParsedFloatWAV {
    func uint16(at offset: Int) -> UInt16 {
        data.withUnsafeBytes { rawBuffer in
            rawBuffer.load(fromByteOffset: offset, as: UInt16.self)
        }
        .littleEndian
    }

    func uint32(at offset: Int) -> UInt32 {
        data.withUnsafeBytes { rawBuffer in
            rawBuffer.load(fromByteOffset: offset, as: UInt32.self)
        }
        .littleEndian
    }

    guard data.count >= 12 else {
        throw VolumeProbeAnalysisError.invalidWAV("The generated file is too small to be a valid WAV container.")
    }
    guard String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
          String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else {
        throw VolumeProbeAnalysisError.invalidWAV("The generated file is not a RIFF/WAVE container.")
    }

    var formatTag: UInt16?
    var channelCount: UInt16?
    var sampleRate: UInt32?
    var bitsPerSample: UInt16?
    var audioPayload: Data?
    var offset = 12

    while offset + 8 <= data.count {
        let chunkID = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
        let chunkSize = Int(uint32(at: offset + 4))
        let chunkStart = offset + 8
        let chunkEnd = chunkStart + chunkSize
        guard chunkEnd <= data.count else {
            throw VolumeProbeAnalysisError.invalidWAV("A WAV chunk overruns the file boundary.")
        }

        if chunkID == "fmt " {
            guard chunkSize >= 16 else {
                throw VolumeProbeAnalysisError.invalidWAV("The WAV fmt chunk is too small.")
            }

            formatTag = uint16(at: chunkStart)
            channelCount = uint16(at: chunkStart + 2)
            sampleRate = uint32(at: chunkStart + 4)
            bitsPerSample = uint16(at: chunkStart + 14)
        } else if chunkID == "data" {
            audioPayload = data[chunkStart..<chunkEnd]
        }

        offset = chunkEnd + (chunkSize % 2)
    }

    guard formatTag == 3 else {
        throw VolumeProbeAnalysisError.invalidWAV("SpeakSwiftlyTesting expected 32-bit float WAV output, but found format tag \(formatTag ?? 0).")
    }
    guard bitsPerSample == 32 else {
        throw VolumeProbeAnalysisError.invalidWAV("SpeakSwiftlyTesting expected 32-bit float WAV output, but found \(bitsPerSample ?? 0) bits per sample.")
    }
    guard let resolvedChannelCount = channelCount, let resolvedSampleRate = sampleRate, let payload = audioPayload else {
        throw VolumeProbeAnalysisError.invalidWAV("The WAV file is missing required fmt or data chunks.")
    }
    guard payload.count % 4 == 0 else {
        throw VolumeProbeAnalysisError.invalidWAV("The WAV float payload is not aligned to 32-bit samples.")
    }

    let interleaved = payload.withUnsafeBytes { rawBuffer in
        Array(rawBuffer.bindMemory(to: Float.self))
    }

    if resolvedChannelCount == 1 {
        return ParsedFloatWAV(
            sampleRate: Int(resolvedSampleRate),
            channelCount: Int(resolvedChannelCount),
            samples: interleaved,
        )
    }

    var mono = [Float]()
    mono.reserveCapacity(interleaved.count / Int(resolvedChannelCount))
    var sampleIndex = 0
    while sampleIndex < interleaved.count {
        mono.append(interleaved[sampleIndex])
        sampleIndex += Int(resolvedChannelCount)
    }

    return ParsedFloatWAV(
        sampleRate: Int(resolvedSampleRate),
        channelCount: Int(resolvedChannelCount),
        samples: mono,
    )
}

private func linearSlopePerWindow(_ windows: [VolumeWindow]) -> Double {
    let xValues = windows.map { Double($0.index - 1) }
    let yValues = windows.map(\.rms)
    let xMean = xValues.reduce(0, +) / Double(xValues.count)
    let yMean = yValues.reduce(0, +) / Double(yValues.count)
    let numerator = zip(xValues, yValues).reduce(into: 0.0) { partialResult, pair in
        partialResult += (pair.0 - xMean) * (pair.1 - yMean)
    }
    let denominator = xValues.reduce(into: 0.0) { partialResult, x in
        let offset = x - xMean
        partialResult += offset * offset
    }
    return denominator == 0 ? 0 : numerator / denominator
}

private func makeBuckets(_ windows: [VolumeWindow], bucketSize: Int) -> [VolumeBucket] {
    var buckets = [VolumeBucket]()
    var start = 0
    var bucketIndex = 1
    while start < windows.count {
        let end = min(start + bucketSize, windows.count)
        let bucketWindows = Array(windows[start..<end])
        buckets.append(
            VolumeBucket(
                label: "bucket_\(bucketIndex)",
                startWindow: bucketWindows.first?.index ?? 0,
                endWindow: bucketWindows.last?.index ?? 0,
                averageRMS: average(bucketWindows.map(\.rms)),
                averagePeak: average(bucketWindows.map(\.peak)),
            ),
        )
        bucketIndex += 1
        start = end
    }
    return buckets
}

private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }

    return values.reduce(0, +) / Double(values.count)
}
