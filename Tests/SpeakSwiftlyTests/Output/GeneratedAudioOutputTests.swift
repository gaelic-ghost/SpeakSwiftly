import Foundation
import SpeakSwiftlyCore
import SpeakSwiftlyHTTPAudioOutput
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

@Test func `http audio frames preserve chunk metadata and pcm payload`() throws {
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
    #expect(try frame.decodedSamples() == [0.25, -0.5])
}

@Test func `http audio frame rejects truncated payloads`() throws {
    let json = """
    {
      "header" : {
        "requestID" : "req-http-corrupt",
        "sequenceNumber" : 1,
        "sampleRate" : 24000,
        "channelCount" : 1,
        "sampleFormat" : "float32_pcm",
        "isFinal" : false,
        "payloadByteCount" : 4
      },
      "payload" : "AQID"
    }
    """
    let frame = try JSONDecoder().decode(HTTPGeneratedAudioFrame.self, from: Data(json.utf8))

    #expect(throws: GeneratedAudioOutputError.self) {
        _ = try frame.decodedSamples()
    }
}
