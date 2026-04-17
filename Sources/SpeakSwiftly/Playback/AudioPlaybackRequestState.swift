@preconcurrency import AVFoundation
import Foundation

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
