import Foundation
@testable import SpeakSwiftly
import SpeakSwiftlyCore
import SpeakSwiftlyNetworkAudioOutput
import Testing

@Test func `network audio frames round trip without a live peer`() throws {
    let chunk = GeneratedAudioChunk(
        requestID: "req-lan",
        sequenceNumber: 1,
        sampleRate: 24000,
        channelCount: 1,
        samples: networkAudioTestSamples(),
    )

    let frame = try NetworkGeneratedAudioFrameCodec.frame(chunk: chunk)
    let encoded = try NetworkGeneratedAudioFrameCodec.encode(frame)
    let decoded = try NetworkGeneratedAudioFrameCodec.decode(encoded)

    #expect(decoded == frame)
    #expect(decoded.payloadFormat == .aac)
    #expect(!decoded.payload.isEmpty)
}

@Test func `network audio aac frames decode back to generated audio chunks`() throws {
    let chunk = GeneratedAudioChunk(
        requestID: "req-aac",
        sequenceNumber: 2,
        sampleRate: 24000,
        channelCount: 1,
        samples: networkAudioTestSamples(),
    )

    let frame = try NetworkGeneratedAudioFrameCodec.frame(chunk: chunk)
    let decoded = try NetworkGeneratedAudioFrameCodec.chunk(from: frame)

    #expect(decoded.requestID == chunk.requestID)
    #expect(decoded.sequenceNumber == chunk.sequenceNumber)
    #expect(decoded.sampleRate == chunk.sampleRate)
    #expect(decoded.channelCount == chunk.channelCount)
    #expect(decoded.sampleFormat == chunk.sampleFormat)
    #expect(decoded.isFinal == chunk.isFinal)
    #expect(!decoded.samples.isEmpty)
}

@Test func `network audio length prefixed frames decode after partial reads`() throws {
    let handshake = NetworkAudioStreamHandshake(
        requestID: "req-lan",
        senderName: "Mac mini",
        sharedToken: "secret",
    )
    let chunk = GeneratedAudioChunk(
        requestID: "req-lan",
        sequenceNumber: 0,
        sampleRate: 24000,
        channelCount: 1,
        samples: networkAudioTestSamples(),
    )
    let audioFrame = try NetworkGeneratedAudioFrameCodec.frame(chunk: chunk)
    let handshakeData = try NetworkAudioLengthPrefixedFrameCodec.encode(.handshake(handshake))
    let audioData = try NetworkAudioLengthPrefixedFrameCodec.encode(.audio(audioFrame))
    let combined = handshakeData + audioData

    var partialBuffer = Data(combined.prefix(2))
    #expect(try NetworkAudioLengthPrefixedFrameCodec.splitFrames(from: &partialBuffer).isEmpty)
    partialBuffer.append(combined.dropFirst(2).prefix(handshakeData.count - 2))
    #expect(try NetworkAudioLengthPrefixedFrameCodec.splitFrames(from: &partialBuffer) == [.handshake(handshake)])
    partialBuffer.append(combined.dropFirst(handshakeData.count))
    #expect(try NetworkAudioLengthPrefixedFrameCodec.splitFrames(from: &partialBuffer) == [.audio(audioFrame)])
    #expect(partialBuffer.isEmpty)
}

@Test func `network audio length prefixed frames reject oversized declarations`() throws {
    var declaredLength = UInt32(NetworkAudioLengthPrefixedFrameCodec.defaultMaximumFrameByteCount + 1).bigEndian
    var data = Data(bytes: &declaredLength, count: NetworkAudioLengthPrefixedFrameCodec.prefixByteCount)
    data.append(Data([0]))

    #expect(throws: GeneratedAudioOutputError.self) {
        _ = try NetworkAudioLengthPrefixedFrameCodec.splitFrames(from: &data)
    }
}

@Test func `network audio endpoint encodes manual and bonjour destinations`() throws {
    let endpoints: [NetworkAudioEndpoint] = [
        NetworkAudioEndpoint(host: "mac-mini.local", port: 17371),
        NetworkAudioEndpoint(serviceName: "Mac mini"),
    ]

    let encoded = try JSONEncoder().encode(endpoints)
    let decoded = try JSONDecoder().decode([NetworkAudioEndpoint].self, from: encoded)

    #expect(decoded == endpoints)
}

@Test func `network audio capabilities round trip through bonjour txt record`() {
    let capabilities = NetworkAudioCapabilities(
        protocolVersion: 1,
        sampleFormats: [.float32PCM],
        sampleRates: [24000, 48000],
        channelCounts: [1, 2],
    )

    let decoded = NetworkAudioCapabilities(txtRecord: capabilities.txtRecord)

    #expect(decoded == capabilities)
}

@Test func `network audio capabilities default missing txt fields`() {
    let decoded = NetworkAudioCapabilities(txtRecord: .init(["txtvers": "1"]))

    #expect(decoded.protocolVersion == NetworkAudioBonjour.protocolVersion)
    #expect(decoded.sampleFormats == [])
    #expect(decoded.sampleRates == [])
    #expect(decoded.channelCounts == [])
}

@Test func `network audio service advertisement uses audio receiver bonjour type`() {
    let advertisement = NetworkAudioServiceAdvertisement(name: "Mac mini")

    #expect(advertisement.type == NetworkAudioBonjour.serviceType)
    #expect(advertisement.domain == NetworkAudioBonjour.domain)
    #expect(NetworkAudioBonjour.serviceType == "_spswift-audio._tcp")
}

@Test func `network audio destination converts to output destination`() {
    let destination = NetworkAudioDestination(
        id: "Mac mini._spswift-audio._tcp.local",
        name: "Mac mini",
        endpoint: NetworkAudioEndpoint(serviceName: "Mac mini"),
        capabilities: NetworkAudioCapabilities(),
        lastSeen: Date(timeIntervalSince1970: 0),
    )

    let outputDestination = SpeakSwiftly.AudioOutputDestination(networkEndpoint: destination.endpoint)

    #expect(outputDestination == .networkService(name: "Mac mini"))
}

@Test func `network audio destination browser starts with empty in memory snapshot`() async {
    let browser = NetworkAudioDestinationBrowser()

    #expect(await browser.snapshot().isEmpty)
}

@Test func `network audio sender streams chunks to loopback listener`() async throws {
    let listener = NetworkAudioStreamListener(
        advertisement: uniqueLoopbackAdvertisement(),
        port: 0,
        sharedToken: "secret",
    )
    let inboundStreams = await listener.inboundStreams()
    try await listener.start()
    let port = try await waitForListeningPort(listener)

    let chunks = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-loopback",
            sequenceNumber: 0,
            sampleRate: 24000,
            channelCount: 1,
            samples: [0.25],
        ))
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-loopback",
            sequenceNumber: 1,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ))
        continuation.finish()
    }
    let sender = NetworkAudioStreamSender(
        endpoint: NetworkAudioEndpoint(host: "127.0.0.1", port: port),
        handshake: NetworkAudioStreamHandshake(
            requestID: "req-loopback",
            senderName: "test-sender",
            sharedToken: "secret",
        ),
    )
    async let sendResult: Void = sender.send(chunks: chunks)

    var iterator = inboundStreams.makeAsyncIterator()
    let inbound = try #require(await iterator.next())
    var receivedChunks = [GeneratedAudioChunk]()
    for try await chunk in inbound.chunks {
        receivedChunks.append(chunk)
    }
    try await sendResult
    await listener.stop()

    #expect(inbound.requestID == "req-loopback")
    #expect(inbound.handshake.senderName == "test-sender")
    #expect(receivedChunks.map(\.sequenceNumber) == [0, 1])
    #expect(receivedChunks.last?.isFinal == true)
}

@Test func `network audio sender readiness wait is bounded`() async throws {
    let chunks = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-timeout",
            sequenceNumber: 0,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ))
        continuation.finish()
    }
    let sender = NetworkAudioStreamSender(
        endpoint: NetworkAudioEndpoint(host: "203.0.113.1", port: 9),
        handshake: NetworkAudioStreamHandshake(
            requestID: "req-timeout",
            senderName: "test-sender",
            sharedToken: "secret",
        ),
        connectionReadinessTimeout: .milliseconds(50),
    )
    let started = ContinuousClock.now

    do {
        try await sender.send(chunks: chunks)
        Issue.record("Expected the network audio sender to fail instead of hanging on an unreachable receiver.")
    } catch let error as GeneratedAudioOutputError {
        guard case let .transportFailed(requestID, message) = error else {
            Issue.record("Expected a transport failure, got \(error).")
            return
        }

        #expect(requestID == "req-timeout")
        #expect(message.contains("req-timeout"))
        #expect(message.contains("203.0.113.1:9"))
        #expect(message.contains("Last observed Network.framework state:"))
    }

    #expect(started.duration(to: ContinuousClock.now) < .seconds(2))
}

@Test func `generated audio output errors have readable localized descriptions`() {
    let error = GeneratedAudioOutputError.transportFailed(
        requestID: "req-localized",
        message: "Network audio connection to '192.0.2.10:51011' did not become ready.",
    )

    #expect(error.localizedDescription.contains("req-localized"))
    #expect(error.localizedDescription.contains("192.0.2.10:51011"))
    #expect(!error.localizedDescription.contains("error 2"))
}

@Test func `network audio listener rejects wrong shared token`() async throws {
    let listener = NetworkAudioStreamListener(
        advertisement: uniqueLoopbackAdvertisement(),
        port: 0,
        sharedToken: "secret",
    )
    let inboundStreams = await listener.inboundStreams()
    try await listener.start()
    let port = try await waitForListeningPort(listener)
    let chunks = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-rejected",
            sequenceNumber: 0,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ))
        continuation.finish()
    }
    let sender = NetworkAudioStreamSender(
        endpoint: NetworkAudioEndpoint(host: "127.0.0.1", port: port),
        handshake: NetworkAudioStreamHandshake(
            requestID: "req-rejected",
            senderName: "test-sender",
            sharedToken: "wrong",
        ),
    )

    do {
        try await sender.send(chunks: chunks)
    } catch {
        // The peer may close before the sender observes success; either way the listener must
        // not publish an accepted inbound stream.
    }
    await listener.stop()

    var iterator = inboundStreams.makeAsyncIterator()
    #expect(await iterator.next() == nil)
}

@Test func `configuration carries manual network output destination`() throws {
    let configuration = SpeakSwiftly.Configuration(
        audioOutputDestination: .networkStream(host: "mac-mini.local", port: 17371),
    )
    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(SpeakSwiftly.Configuration.self, from: data)

    #expect(decoded.audioOutputDestination == .networkStream(host: "mac-mini.local", port: 17371))
}

@Test func `configuration carries bonjour network output destination`() throws {
    let configuration = SpeakSwiftly.Configuration(
        audioOutputDestination: .networkService(name: "Mac mini"),
    )
    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(SpeakSwiftly.Configuration.self, from: data)

    #expect(decoded.audioOutputDestination == .networkService(name: "Mac mini"))
}

private func waitForListeningPort(_ listener: NetworkAudioStreamListener) async throws -> UInt16 {
    var lastState = await listener.state
    for _ in 0..<1000 {
        lastState = await listener.state
        switch lastState {
            case let .listening(port?):
                return port
            case let .failed(message):
                Issue.record("Network audio listener failed before reporting a loopback port: \(message)")
                throw CancellationError()
            default:
                try await Task.sleep(for: .milliseconds(10))
        }
    }

    Issue.record("Network audio listener did not report a loopback port in time. Last observed state: \(lastState).")
    throw CancellationError()
}

private func uniqueLoopbackAdvertisement() -> NetworkAudioServiceAdvertisement {
    NetworkAudioServiceAdvertisement(name: "Loopback receiver \(UUID().uuidString)")
}

private func networkAudioTestSamples() -> [Float] {
    let sampleRate = 24000
    return (0..<sampleRate / 10).map { index in
        Float(sin(2.0 * Double.pi * 440.0 * Double(index) / Double(sampleRate)) * 0.2)
    }
}
