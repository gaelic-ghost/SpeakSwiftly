import Foundation
@testable import SpeakSwiftly
import SpeakSwiftlyCore
import SpeakSwiftlyHTTPAudioOutput
import SpeakSwiftlyNetworkAudioOutput
import SpeakSwiftlyPlayback
import Testing

@Test func `canonical generated audio chunk carries metadata and final marker`() {
    let chunk = GeneratedAudioChunk(
        requestID: "req-audio",
        sequenceNumber: 2,
        sampleRate: 24000,
        channelCount: 1,
        samples: [0.1, -0.2],
        isFinal: true,
    )

    #expect(chunk.requestID == "req-audio")
    #expect(chunk.sequenceNumber == 2)
    #expect(chunk.sampleRate == 24000)
    #expect(chunk.channelCount == 1)
    #expect(chunk.sampleFormat == .float32PCM)
    #expect(chunk.samples == [0.1, -0.2])
    #expect(chunk.isFinal)
}

@Test func `chunk stream wraps float samples as canonical chunks`() async throws {
    let source = AsyncThrowingStream<[Float], any Error> { continuation in
        continuation.yield([0.1, 0.2])
        continuation.yield([0.3])
        continuation.finish()
    }
    var chunks = [GeneratedAudioChunk]()

    for try await chunk in GeneratedAudioChunkStream.chunks(
        requestID: "req-qwen",
        sampleRate: 24000,
        samples: source,
    ) {
        chunks.append(chunk)
    }

    #expect(chunks.map(\.sequenceNumber) == [0, 1, 2])
    #expect(chunks.map(\.samples) == [[0.1, 0.2], [0.3], []])
    #expect(chunks.last?.isFinal == true)
}

@Test func `local playback output consumes sample chunks and ignores final marker`() async throws {
    let source = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(
            GeneratedAudioChunk(
                requestID: "req-playback",
                sequenceNumber: 0,
                sampleRate: 24000,
                channelCount: 1,
                samples: [0.4, 0.5],
            ),
        )
        continuation.yield(
            GeneratedAudioChunk(
                requestID: "req-playback",
                sequenceNumber: 1,
                sampleRate: 24000,
                channelCount: 1,
                samples: [],
                isFinal: true,
            ),
        )
        continuation.finish()
    }
    var sampleChunks = [[Float]]()

    for try await samples in LocalPlaybackAudioOutput.sampleChunks(from: source) {
        sampleChunks.append(samples)
    }

    #expect(sampleChunks == [[0.4, 0.5]])
}

@Test func `http audio frames preserve chunk metadata and pcm payload`() {
    let chunk = GeneratedAudioChunk(
        requestID: "req-http",
        sequenceNumber: 7,
        sampleRate: 48000,
        channelCount: 2,
        samples: [0.25, -0.5],
        isFinal: true,
    )

    let frame = HTTPGeneratedAudioFrame(chunk: chunk)

    #expect(frame.header.requestID == "req-http")
    #expect(frame.header.sequenceNumber == 7)
    #expect(frame.header.sampleRate == 48000)
    #expect(frame.header.channelCount == 2)
    #expect(frame.header.sampleFormat == .float32PCM)
    #expect(frame.header.isFinal)
    #expect(frame.contentType == "application/octet-stream")
    #expect(frame.metadataHeaders.contains { $0.name == "X-SpeakSwiftly-Final" && $0.value == "true" })
    #expect(frame.decodedSamples() == [0.25, -0.5])
}

@Test func `network audio frames round trip without a live peer`() throws {
    let frame = NetworkGeneratedAudioFrame(
        chunk: GeneratedAudioChunk(
            requestID: "req-lan",
            sequenceNumber: 1,
            sampleRate: 24000,
            channelCount: 1,
            samples: [0.125],
        ),
    )

    let encoded = try NetworkGeneratedAudioFrameCodec.encode(frame)
    let decoded = try NetworkGeneratedAudioFrameCodec.decode(encoded)

    #expect(decoded == frame)
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

@Test func `configuration carries output destination`() throws {
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
