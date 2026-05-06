import Foundation

public extension SpeakSwiftly {
    /// A high-level request lifecycle event emitted by a request handle.
    enum RequestEvent: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(RequestAcknowledgement)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(RequestCompletion)
    }

    /// A point-in-time state for a submitted request.
    enum RequestState: Sendable, Equatable {
        case queued(QueuedEvent)
        case acknowledged(RequestAcknowledgement)
        case started(StartedEvent)
        case progress(ProgressEvent)
        case completed(RequestCompletion)
        case failed(Failure)
        case cancelled(Failure)
    }

    /// Summary metrics reported while a request is being synthesized.
    struct SynthesisEventInfo: Sendable, Equatable {
        public let promptTokenCount: Int
        public let generationTokenCount: Int
        public let prefillTime: TimeInterval
        public let generateTime: TimeInterval
        public let tokensPerSecond: Double
        public let peakMemoryUsage: Double
    }

    /// A request-scoped synthesis event emitted while speech is being produced.
    enum SynthesisEvent: Sendable, Equatable {
        case token(Int)
        case info(SynthesisEventInfo)
        case audioChunk(sampleCount: Int)
    }

    /// A sequenced request-state update produced by the runtime's observation stream.
    struct RequestUpdate: Sendable, Equatable {
        public let id: String
        public let sequence: Int
        public let date: Date
        public let state: RequestState
    }

    /// A sequenced synthesis event update produced by the runtime's observation stream.
    struct SynthesisUpdate: Sendable, Equatable {
        public let id: String
        public let sequence: Int
        public let date: Date
        public let event: SynthesisEvent
    }

    /// A retained snapshot of the most recent known state for one request.
    struct RequestSnapshot: Sendable, Equatable {
        public let id: String
        public let kind: RequestKind
        public let voiceProfile: String?
        public let requestContext: RequestContext?
        public let acceptedAt: Date
        public let lastUpdatedAt: Date
        public let sequence: Int
        public let state: RequestState
    }

    /// A lightweight acknowledgement that a submitted request was accepted by the runtime.
    struct RequestAcknowledgement: Sendable, Equatable {
        public let id: String
        public let kind: RequestKind
        public let generationJob: GenerationJob?
    }

    /// A typed handle for one submitted request and its live event streams.
    struct RequestHandle: Sendable {
        public let id: String
        public let kind: RequestKind
        public let voiceProfile: String?
        public let requestContext: RequestContext?
        /// A stream of lifecycle events such as queueing, start, progress, and completion.
        public let events: AsyncThrowingStream<RequestEvent, any Swift.Error>
        /// A stream of synthesis-specific updates such as token counts and audio chunks.
        public let synthesisUpdates: AsyncThrowingStream<SynthesisUpdate, any Swift.Error>

        init(
            id: String,
            kind: RequestKind,
            voiceProfile: String?,
            requestContext: RequestContext?,
            events: AsyncThrowingStream<RequestEvent, any Swift.Error>,
            synthesisUpdates: AsyncThrowingStream<SynthesisUpdate, any Swift.Error>,
        ) {
            self.id = id
            self.kind = kind
            self.voiceProfile = voiceProfile
            self.requestContext = requestContext
            self.events = events
            self.synthesisUpdates = synthesisUpdates
        }

        /// Waits until the request reaches a terminal completion and returns its typed payload.
        public func completion() async throws -> RequestCompletion {
            for try await event in events {
                if case let .completed(completion) = event {
                    return completion
                }
            }

            throw SpeakSwiftly.Error(
                code: .requestCancelled,
                message: "Request '\(id)' ended before SpeakSwiftly reported a terminal completion event.",
            )
        }
    }
}
