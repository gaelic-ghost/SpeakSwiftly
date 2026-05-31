import Foundation
@testable import SpeakSwiftly
import SpeakSwiftlyCore
import SpeakSwiftlyNetworkAudioOutput
import Testing

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
