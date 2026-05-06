import SpeakSwiftlyTestSupport
import Testing

@Test func `volume analysis slices samples into fixed duration windows`() throws {
    let analysis = try analyzeVolume(
        samples: [1, -1, 1, -1, 2, -2, 3, -3, 4],
        sampleRate: 4,
        windowSeconds: 0.5,
    )

    #expect(analysis.sampleRate == 4)
    #expect(analysis.sampleCount == 9)
    #expect(analysis.analyzedSampleCount == 9)
    #expect(analysis.windows.count == 5)
    #expect(analysis.windows[0].durationSeconds == 0.5)
    #expect(analysis.windows[4].durationSeconds == 0.25)
    #expect(analysis.windows[0].rms == 1)
    #expect(analysis.windows[4].rms == 4)
}

@Test func `volume summary reports averaged head tail and last windows`() throws {
    let analysis = try analyzeVolume(
        samples: [
            1, 1,
            2, 2,
            3, 3,
            4, 4,
            5, 5,
            6, 6,
            7, 7,
            8, 8,
        ],
        sampleRate: 2,
        windowSeconds: 1,
    )

    let summary = try #require(analysis.summary)
    #expect(summary.windowCount == 8)
    #expect(summary.firstRMS == 1)
    #expect(summary.lastRMS == 8)
    #expect(summary.endpointRMSDeltaPercent == 700)
    #expect(summary.headRMS == 1.5)
    #expect(summary.tailRMS == 7.5)
    #expect(summary.tailHeadRatio == 5)
    #expect(summary.lastWindowAverageCount == 3)
    #expect(summary.lastWindowAverageRMS == 7)
    #expect(summary.buckets.count == 4)
    #expect(summary.buckets[0].startWindow == 1)
    #expect(summary.buckets[0].endWindow == 2)
    #expect(summary.buckets[3].averageRMS == 7.5)
}

@Test func `volume analysis can trim to a matched sample count`() throws {
    let analysis = try analyzeVolume(
        samples: [1, 1, 2, 2, 10, 10],
        sampleRate: 2,
        windowSeconds: 1,
        maxSampleCount: 4,
    )

    #expect(analysis.sampleCount == 6)
    #expect(analysis.analyzedSampleCount == 4)
    #expect(analysis.durationSeconds == 3)
    #expect(analysis.summary?.durationSeconds == 2)
    #expect(analysis.windows.map(\.rms) == [1, 2])
}

@Test func `volume analysis rejects invalid input before slicing`() {
    #expect(throws: VolumeProbeAnalysisError.invalidAnalysisInput("SpeakSwiftlyProbeTool could not analyze volume because sampleRate must be greater than zero.")) {
        try analyzeVolume(samples: [1], sampleRate: 0, windowSeconds: 1)
    }
    #expect(throws: VolumeProbeAnalysisError.invalidAnalysisInput("SpeakSwiftlyProbeTool could not analyze volume because windowSeconds must be greater than zero.")) {
        try analyzeVolume(samples: [1], sampleRate: 1, windowSeconds: 0)
    }
    #expect(throws: VolumeProbeAnalysisError.invalidAnalysisInput("SpeakSwiftlyProbeTool could not analyze volume because maxSampleCount must be zero or greater.")) {
        try analyzeVolume(samples: [1], sampleRate: 1, windowSeconds: 1, maxSampleCount: -1)
    }
}
