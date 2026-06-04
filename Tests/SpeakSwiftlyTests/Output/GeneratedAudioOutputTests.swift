import AVFoundation
import Foundation
import SpeakSwiftlyCore
import SpeakSwiftlyFileAudioOutput
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

    for try await chunk in GeneratedAudioChunkStreams.chunks(
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

@Test func `chunk stream fanout broadcasts chunks to each branch`() async throws {
    let source = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-fanout",
            sequenceNumber: 0,
            sampleRate: 24000,
            channelCount: 1,
            samples: [0.1],
        ))
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-fanout",
            sequenceNumber: 1,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ))
        continuation.finish()
    }

    let branches = GeneratedAudioChunkStreams.fanOut(source, branchCount: 2)
    let first = try await collectChunks(from: branches[0])
    let second = try await collectChunks(from: branches[1])

    #expect(first.map(\.sequenceNumber) == [0, 1])
    #expect(second.map(\.sequenceNumber) == [0, 1])
    #expect(first.last?.isFinal == true)
    #expect(second.last?.isFinal == true)
}

@Test func `chunk stream fanout returns no streams for zero branches`() {
    let source = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.finish()
    }

    let branches = GeneratedAudioChunkStreams.fanOut(source, branchCount: 0)

    #expect(branches.isEmpty)
}

@Test func `chunk stream fanout propagates source failure to branches`() async {
    struct ExpectedFailure: Error {}

    let source = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.finish(throwing: ExpectedFailure())
    }
    let branches = GeneratedAudioChunkStreams.fanOut(source, branchCount: 2)

    await #expect(throws: ExpectedFailure.self) {
        _ = try await collectChunks(from: branches[0])
    }
    await #expect(throws: ExpectedFailure.self) {
        _ = try await collectChunks(from: branches[1])
    }
}

@Test func `chunk stream fanout lets a fast branch drain while slow branch keeps bounded newest chunks`() async throws {
    let source = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        for sequenceNumber in 0..<8 {
            continuation.yield(GeneratedAudioChunk(
                requestID: "req-fanout-bounded",
                sequenceNumber: sequenceNumber,
                sampleRate: 24000,
                channelCount: 1,
                samples: [Float(sequenceNumber)],
            ))
        }
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-fanout-bounded",
            sequenceNumber: 8,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ))
        continuation.finish()
    }
    let branches = GeneratedAudioChunkStreams.fanOut(
        source,
        bufferingPolicies: [
            .unbounded,
            .bufferingNewest(2),
        ],
    )

    async let fastChunks = collectChunks(from: branches[0])
    try await Task.sleep(for: .milliseconds(20))
    let slowChunks = try await collectChunks(from: branches[1])
    let drainedFastChunks = try await fastChunks

    #expect(drainedFastChunks.map(\.sequenceNumber) == Array(0...8))
    #expect(slowChunks.count <= 2)
    #expect(slowChunks.last?.isFinal == true)
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

private func collectChunks(from stream: GeneratedAudioChunkStream) async throws -> [GeneratedAudioChunk] {
    var chunks = [GeneratedAudioChunk]()
    for try await chunk in stream {
        chunks.append(chunk)
    }
    return chunks
}

@MainActor
@Test func `local generated audio player consumes chunk stream through sample sink`() async throws {
    let collector = GeneratedAudioChunkCollector()
    let player = LocalGeneratedAudioPlayer { chunk in
        await collector.append(chunk)
    }
    let source = AsyncThrowingStream<GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-play",
            sequenceNumber: 0,
            sampleRate: 24000,
            channelCount: 1,
            samples: [0.4, 0.5],
        ))
        continuation.yield(GeneratedAudioChunk(
            requestID: "req-play",
            sequenceNumber: 1,
            sampleRate: 24000,
            channelCount: 1,
            samples: [],
            isFinal: true,
        ))
        continuation.finish()
    }

    try await player.play(chunks: source)

    let received = await collector.chunks()
    #expect(received.map(\.sequenceNumber) == [0])
    #expect(received.first?.samples == [0.4, 0.5])
}

private actor GeneratedAudioChunkCollector {
    private var values = [GeneratedAudioChunk]()

    func append(_ chunk: GeneratedAudioChunk) {
        values.append(chunk)
    }

    func chunks() -> [GeneratedAudioChunk] {
        values
    }
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

@Test func `file audio output encodes wav and m4a data`() throws {
    let samples: [Float] = [0, 0.25, -0.25, 0]

    let wav = try GeneratedAudioFileEncoder.encodedAudioData(
        samples: samples,
        sampleRate: 24000,
        format: .wav,
    )
    #expect(wav.starts(with: Data("RIFF".utf8)))
    #expect(wav.count > 44)

    let m4a = try GeneratedAudioFileEncoder.encodedAudioData(
        samples: samples,
        sampleRate: 24000,
        format: .m4a,
    )
    #expect(!m4a.isEmpty)

    let url = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("speakswiftly-file-output-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    try m4a.write(to: url)

    let file = try AVAudioFile(forReading: url)
    #expect(Int(file.processingFormat.sampleRate.rounded()) == 24000)
}
