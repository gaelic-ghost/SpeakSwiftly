import Foundation

public enum GeneratedAudioSampleFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case float32PCM = "float32_pcm"
}

public struct GeneratedAudioChunk: Codable, Sendable, Equatable {
    public let requestID: String
    public let sequenceNumber: Int
    public let sampleRate: Int
    public let channelCount: Int
    public let sampleFormat: GeneratedAudioSampleFormat
    public let samples: [Float]
    public let isFinal: Bool

    public init(
        requestID: String,
        sequenceNumber: Int,
        sampleRate: Int,
        channelCount: Int,
        sampleFormat: GeneratedAudioSampleFormat = .float32PCM,
        samples: [Float],
        isFinal: Bool = false,
    ) {
        self.requestID = requestID
        self.sequenceNumber = sequenceNumber
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.sampleFormat = sampleFormat
        self.samples = samples
        self.isFinal = isFinal
    }
}

public enum GeneratedAudioOutputError: Error, Codable, Sendable, Equatable {
    case invalidChunk(requestID: String, message: String)
    case cancelled(requestID: String)
    case transportFailed(requestID: String, message: String)
}

extension GeneratedAudioOutputError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case let .invalidChunk(requestID, message):
                "Generated audio chunk for request '\(requestID)' is invalid. \(message)"
            case let .cancelled(requestID):
                "Generated audio output for request '\(requestID)' was cancelled."
            case let .transportFailed(requestID, message):
                "Generated audio transport for request '\(requestID)' failed. \(message)"
        }
    }
}

public typealias GeneratedAudioChunkStream = AsyncThrowingStream<GeneratedAudioChunk, any Error>

public enum GeneratedAudioChunkStreams {
    public static func chunks(
        requestID: String,
        sampleRate: Int,
        channelCount: Int = 1,
        samples: some AsyncSequence<[Float], any Error> & Sendable,
    ) -> GeneratedAudioChunkStream {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sequenceNumber = 0
                do {
                    for try await sampleChunk in samples {
                        continuation.yield(
                            GeneratedAudioChunk(
                                requestID: requestID,
                                sequenceNumber: sequenceNumber,
                                sampleRate: sampleRate,
                                channelCount: channelCount,
                                samples: sampleChunk,
                            ),
                        )
                        sequenceNumber += 1
                    }
                    continuation.yield(
                        GeneratedAudioChunk(
                            requestID: requestID,
                            sequenceNumber: sequenceNumber,
                            sampleRate: sampleRate,
                            channelCount: channelCount,
                            samples: [],
                            isFinal: true,
                        ),
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func fanOut(
        _ source: GeneratedAudioChunkStream,
        branchCount: Int,
        bufferingPolicy: GeneratedAudioChunkStream.Continuation.BufferingPolicy = .bufferingNewest(16),
    ) -> [GeneratedAudioChunkStream] {
        fanOut(
            source,
            bufferingPolicies: Array(repeating: bufferingPolicy, count: max(0, branchCount)),
        )
    }

    public static func fanOut(
        _ source: GeneratedAudioChunkStream,
        bufferingPolicies: [GeneratedAudioChunkStream.Continuation.BufferingPolicy],
    ) -> [GeneratedAudioChunkStream] {
        guard !bufferingPolicies.isEmpty else {
            return []
        }

        let hub = GeneratedAudioChunkFanoutHub(expectedBranchCount: bufferingPolicies.count)
        let streams = bufferingPolicies.enumerated().map { index, bufferingPolicy in
            GeneratedAudioChunkStream(bufferingPolicy: bufferingPolicy) { continuation in
                Task {
                    await hub.register(continuation, at: index)
                }
                continuation.onTermination = { _ in
                    Task {
                        await hub.unregister(index)
                    }
                }
            }
        }

        Task {
            await hub.waitUntilReady()
            do {
                for try await chunk in source {
                    await hub.yield(chunk)
                }
                await hub.finish()
            } catch {
                await hub.finish(throwing: error)
            }
        }

        return streams
    }
}

private actor GeneratedAudioChunkFanoutHub {
    typealias Continuation = GeneratedAudioChunkStream.Continuation

    private let expectedBranchCount: Int
    private var continuations = [Int: Continuation]()
    private var readinessWaiters = [CheckedContinuation<Void, Never>]()

    init(expectedBranchCount: Int) {
        self.expectedBranchCount = expectedBranchCount
    }

    func register(_ continuation: Continuation, at index: Int) {
        continuations[index] = continuation
        guard continuations.count >= expectedBranchCount else {
            return
        }

        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func unregister(_ index: Int) {
        continuations.removeValue(forKey: index)
    }

    func waitUntilReady() async {
        guard continuations.count < expectedBranchCount else {
            return
        }

        await withCheckedContinuation { continuation in
            if continuations.count >= expectedBranchCount {
                continuation.resume()
            } else {
                readinessWaiters.append(continuation)
            }
        }
    }

    func yield(_ chunk: GeneratedAudioChunk) {
        for continuation in continuations.values {
            continuation.yield(chunk)
        }
    }

    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        resumeReadinessWaiters()
    }

    func finish(throwing error: any Error) {
        for continuation in continuations.values {
            continuation.finish(throwing: error)
        }
        continuations.removeAll()
        resumeReadinessWaiters()
    }

    private func resumeReadinessWaiters() {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
