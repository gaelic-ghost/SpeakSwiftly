@preconcurrency import AVFoundation
import Foundation

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
    var currentChunkFinished = false
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

    init(requestID: UInt64, text: String, tuningProfile: PlaybackTuningProfile) {
        self.requestID = requestID
        thresholdsController = PlaybackThresholdController(text: text, tuningProfile: tuningProfile)
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

    func recordScheduledBuffer(sampleRate: Double) {
        scheduleCallbackCount += 1
        recordQueuedAudioDepth(sampleRate: sampleRate)
    }

    func recordPlayedBackBuffer(sampleRate: Double) {
        playedBackCallbackCount += 1
        recordQueuedAudioDepth(sampleRate: sampleRate)
    }

    func recordPreparedBufferShape(
        firstSample: Float,
        lastSample: Float,
        fadeInApplied: Bool,
    ) {
        let leadingAbs = Double(abs(firstSample))
        let trailingAbs = Double(abs(lastSample))
        maxLeadingAbsAmplitude = max(maxLeadingAbsAmplitude ?? leadingAbs, leadingAbs)
        maxTrailingAbsAmplitude = max(maxTrailingAbsAmplitude ?? trailingAbs, trailingAbs)
        if fadeInApplied {
            fadeInChunkCount += 1
        }
        if let lastTrailingSample {
            let jump = Double(abs(firstSample - lastTrailingSample))
            maxBoundaryDiscontinuity = max(maxBoundaryDiscontinuity ?? jump, jump)
        }
        lastTrailingSample = lastSample
    }

    @discardableResult
    func beginRebuffer(now: Date = Date()) -> Bool {
        guard !isRebuffering else { return false }

        isRebuffering = true
        rebufferEventCount += 1
        thresholdsController.recordRebuffer()
        rebufferStartedAt = now
        recentRebufferStartTimes.append(now)
        recentRebufferStartTimes.removeAll {
            now.timeIntervalSince($0) * 1000 > Double(PlaybackMetricsConfiguration.rebufferThrashWindowMS)
        }
        return true
    }

    @discardableResult
    func finishRebuffer(now: Date = Date()) -> Int? {
        guard isRebuffering else { return nil }

        isRebuffering = false
        guard let rebufferStartedAt else { return nil }

        let durationMS = Int((now.timeIntervalSince(rebufferStartedAt) * 1000).rounded())
        rebufferTotalDurationMS += durationMS
        longestRebufferDurationMS = max(longestRebufferDurationMS, durationMS)
        self.rebufferStartedAt = nil
        return durationMS
    }

    func shouldEmitRebufferThrashWarning() -> Bool {
        guard !emittedRebufferThrashWarning else { return false }
        guard recentRebufferStartTimes.count >= PlaybackMetricsConfiguration.rebufferThrashWarningCount else { return false }

        emittedRebufferThrashWarning = true
        return true
    }

    func installDrainContinuation(
        _ continuation: CheckedContinuation<Void, Error>,
        sampleRate: Double,
    ) {
        drainContinuation = continuation
        if queuedAudioMS(sampleRate: sampleRate) == 0 {
            resumeDrainContinuation()
        }
    }

    func resumeDrainContinuation() {
        guard let drainContinuation else { return }

        self.drainContinuation = nil
        drainContinuation.resume()
    }

    func resumeDrainContinuation(throwing error: any Error) {
        guard let drainContinuation else { return }

        self.drainContinuation = nil
        drainContinuation.resume(throwing: error)
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
