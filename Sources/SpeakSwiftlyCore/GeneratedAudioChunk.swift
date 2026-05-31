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
