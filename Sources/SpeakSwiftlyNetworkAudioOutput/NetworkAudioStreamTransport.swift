import Foundation
import Network
import SpeakSwiftlyCore

public struct NetworkAudioInboundStream: Sendable {
    public let requestID: String
    public let remoteEndpointDescription: String
    public let handshake: NetworkAudioStreamHandshake
    public let chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>

    public init(
        requestID: String,
        remoteEndpointDescription: String,
        handshake: NetworkAudioStreamHandshake,
        chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
    ) {
        self.requestID = requestID
        self.remoteEndpointDescription = remoteEndpointDescription
        self.handshake = handshake
        self.chunks = chunks
    }
}

public enum NetworkAudioStreamState: Sendable, Equatable {
    case idle
    case starting
    case listening(port: UInt16?)
    case failed(message: String)
    case stopped
}

public actor NetworkAudioStreamListener {
    public private(set) var state: NetworkAudioStreamState = .idle

    private let advertisement: NetworkAudioServiceAdvertisement
    private let port: UInt16
    private let sharedToken: String
    private let maximumFrameByteCount: Int
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var continuations = [UUID: AsyncStream<NetworkAudioInboundStream>.Continuation]()
    private var connectionTasks = [ObjectIdentifier: Task<Void, Never>]()

    public init(
        advertisement: NetworkAudioServiceAdvertisement,
        port: UInt16,
        sharedToken: String,
        maximumFrameByteCount: Int = NetworkAudioLengthPrefixedFrameCodec.defaultMaximumFrameByteCount,
        queue: DispatchQueue = DispatchQueue(label: "SpeakSwiftly.NetworkAudioStreamListener"),
    ) {
        self.advertisement = advertisement
        self.port = port
        self.sharedToken = sharedToken
        self.maximumFrameByteCount = maximumFrameByteCount
        self.queue = queue
    }

    public func start() throws {
        guard listener == nil else {
            return
        }
        guard !sharedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: "unknown",
                message: "Network audio listener cannot start because its shared token is empty.",
            )
        }

        let listener = try NWListener(
            using: .tcp,
            on: NWEndpoint.Port(integerLiteral: port),
        )
        listener.service = advertisement.listenerService
        listener.newConnectionHandler = { connection in
            Task {
                await self.accept(connection)
            }
        }
        listener.stateUpdateHandler = { state in
            Task {
                await self.updateState(from: state)
            }
        }
        self.listener = listener
        state = .starting
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for task in connectionTasks.values {
            task.cancel()
        }
        connectionTasks.removeAll()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        state = .stopped
    }

    public func inboundStreams() -> AsyncStream<NetworkAudioInboundStream> {
        let id = UUID()
        let stream = AsyncStream<NetworkAudioInboundStream>.makeStream()
        continuations[id] = stream.continuation
        stream.continuation.onTermination = { _ in
            Task {
                await self.removeContinuation(id)
            }
        }
        return stream.stream
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        let task = Task {
            await runConnection(connection)
            removeConnectionTask(connectionID)
        }
        connectionTasks[connectionID] = task
    }

    private func runConnection(_ connection: NWConnection) async {
        connection.start(queue: queue)
        do {
            try await connection.waitUntilReady()
            let firstFrame = try await connection.receiveLengthPrefixedFrame(maximumFrameByteCount: maximumFrameByteCount)
            guard case let .handshake(handshake) = firstFrame else {
                throw GeneratedAudioOutputError.transportFailed(
                    requestID: "unknown",
                    message: "Network audio connection from '\(connection.endpoint)' did not start with a stream handshake.",
                )
            }

            try validate(handshake)

            let stream = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
                let receiveTask = Task {
                    do {
                        while !Task.isCancelled {
                            let frame = try await connection.receiveLengthPrefixedFrame(maximumFrameByteCount: maximumFrameByteCount)
                            guard case let .audio(audioFrame) = frame else {
                                throw GeneratedAudioOutputError.transportFailed(
                                    requestID: handshake.requestID,
                                    message: "Network audio connection from '\(connection.endpoint)' sent a second handshake after audio streaming had started.",
                                )
                            }

                            continuation.yield(audioFrame.chunk)
                            if audioFrame.chunk.isFinal {
                                continuation.finish()
                                connection.cancel()
                                return
                            }
                        }
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: error)
                        connection.cancel()
                    }
                }
                continuation.onTermination = { _ in
                    receiveTask.cancel()
                    connection.cancel()
                }
            }

            let inbound = NetworkAudioInboundStream(
                requestID: handshake.requestID,
                remoteEndpointDescription: "\(connection.endpoint)",
                handshake: handshake,
                chunks: stream,
            )
            for continuation in continuations.values {
                continuation.yield(inbound)
            }
        } catch {
            connection.cancel()
        }
    }

    private func validate(_ handshake: NetworkAudioStreamHandshake) throws {
        guard handshake.protocolVersion == NetworkAudioBonjour.protocolVersion else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: handshake.requestID,
                message: "Network audio stream '\(handshake.requestID)' used protocol version \(handshake.protocolVersion), but this listener supports version \(NetworkAudioBonjour.protocolVersion).",
            )
        }
        guard handshake.sharedToken == sharedToken else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: handshake.requestID,
                message: "Network audio stream '\(handshake.requestID)' was rejected because its shared token did not match this listener.",
            )
        }
    }

    private func updateState(from listenerState: NWListener.State) {
        switch listenerState {
            case .setup:
                state = .idle
            case .ready:
                state = .listening(port: listener?.port?.rawValue)
            case .cancelled:
                state = .stopped
            case let .waiting(error):
                state = .failed(message: "Network audio listener is waiting for the network to become available: \(error)")
            case let .failed(error):
                state = .failed(message: "Network audio listener failed: \(error)")
            @unknown default:
                state = .failed(message: "Network audio listener entered an unknown Network.framework listener state.")
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func removeConnectionTask(_ id: ObjectIdentifier) {
        connectionTasks.removeValue(forKey: id)
    }
}

public struct NetworkAudioStreamSender: Sendable {
    private let endpoint: NetworkAudioEndpoint
    private let handshake: NetworkAudioStreamHandshake
    private let maximumFrameByteCount: Int
    private let queue: DispatchQueue

    public init(
        endpoint: NetworkAudioEndpoint,
        handshake: NetworkAudioStreamHandshake,
        maximumFrameByteCount: Int = NetworkAudioLengthPrefixedFrameCodec.defaultMaximumFrameByteCount,
        queue: DispatchQueue = DispatchQueue(label: "SpeakSwiftly.NetworkAudioStreamSender"),
    ) {
        self.endpoint = endpoint
        self.handshake = handshake
        self.maximumFrameByteCount = maximumFrameByteCount
        self.queue = queue
    }

    public func send(
        chunks: AsyncThrowingStream<GeneratedAudioChunk, any Error>,
    ) async throws {
        let connection = NWConnection(to: endpoint.nwEndpoint, using: .tcp)
        connection.start(queue: queue)
        do {
            try await connection.waitUntilReady()
            try await connection.sendFrame(.handshake(handshake), maximumFrameByteCount: maximumFrameByteCount)
            for try await chunk in chunks {
                try Task.checkCancellation()
                try await connection.sendFrame(
                    .audio(NetworkGeneratedAudioFrame(chunk: chunk)),
                    maximumFrameByteCount: maximumFrameByteCount,
                )
                if chunk.isFinal {
                    break
                }
            }
            connection.cancel()
        } catch {
            connection.cancel()
            throw error
        }
    }
}

private extension NWConnection {
    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ReadyContinuationBox()
            stateUpdateHandler = { state in
                switch state {
                    case .ready:
                        box.resume(continuation)
                    case let .failed(error):
                        box.resume(continuation, throwing: GeneratedAudioOutputError.transportFailed(
                            requestID: "unknown",
                            message: "Network audio connection failed before it became ready: \(error)",
                        ))
                    case .cancelled:
                        box.resume(continuation, throwing: GeneratedAudioOutputError.transportFailed(
                            requestID: "unknown",
                            message: "Network audio connection was cancelled before it became ready.",
                        ))
                    default:
                        break
                }
            }
        }
    }

    func sendFrame(
        _ frame: NetworkAudioStreamFrame,
        maximumFrameByteCount: Int,
    ) async throws {
        let data = try NetworkAudioLengthPrefixedFrameCodec.encode(
            frame,
            maximumFrameByteCount: maximumFrameByteCount,
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: GeneratedAudioOutputError.transportFailed(
                        requestID: frame.requestID,
                        message: "Network audio frame for request '\(frame.requestID)' could not be sent: \(error)",
                    ))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receiveLengthPrefixedFrame(maximumFrameByteCount: Int) async throws -> NetworkAudioStreamFrame {
        let prefix = try await receiveExactly(NetworkAudioLengthPrefixedFrameCodec.prefixByteCount)
        let frameLength = Int(prefix.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        })
        guard frameLength <= maximumFrameByteCount else {
            throw GeneratedAudioOutputError.transportFailed(
                requestID: "unknown",
                message: "Network audio frame declared \(frameLength) bytes, which exceeds the configured maximum of \(maximumFrameByteCount) bytes.",
            )
        }

        let payload = try await receiveExactly(frameLength)
        return try NetworkAudioLengthPrefixedFrameCodec.decodePayload(payload)
    }

    func receiveExactly(_ byteCount: Int) async throws -> Data {
        var buffer = Data()
        while buffer.count < byteCount {
            let remaining = byteCount - buffer.count
            let chunk = try await receiveChunk(maximumLength: remaining)
            guard !chunk.isEmpty else {
                throw GeneratedAudioOutputError.transportFailed(
                    requestID: "unknown",
                    message: "Network audio connection closed before \(byteCount) bytes could be read.",
                )
            }

            buffer.append(chunk)
        }
        return buffer
    }

    func receiveChunk(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: GeneratedAudioOutputError.transportFailed(
                        requestID: "unknown",
                        message: "Network audio receive failed: \(error)",
                    ))
                } else if let data {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(throwing: GeneratedAudioOutputError.transportFailed(
                        requestID: "unknown",
                        message: "Network audio receive returned no data before the connection completed.",
                    ))
                }
            }
        }
    }
}

private extension NetworkAudioStreamFrame {
    var requestID: String {
        switch self {
            case let .handshake(handshake):
                handshake.requestID
            case let .audio(frame):
                frame.chunk.requestID
        }
    }
}

private final class ReadyContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<Void, any Error>,
    ) {
        guard markResumed() else { return }

        continuation.resume()
    }

    func resume(
        _ continuation: CheckedContinuation<Void, any Error>,
        throwing error: any Error,
    ) {
        guard markResumed() else { return }

        continuation.resume(throwing: error)
    }

    private func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else {
            return false
        }

        didResume = true
        return true
    }
}
