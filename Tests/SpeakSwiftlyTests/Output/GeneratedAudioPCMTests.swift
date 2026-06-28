import AVFoundation
import SpeakSwiftlyAudioSupport
import SpeakSwiftlyCore
import Testing

@Test func `generated audio pcm creates mono float32 buffer`() throws {
    let format = try GeneratedAudioPCM.float32Format(
        sampleRate: 24000,
        channelCount: 1,
        context: "unit test mono buffer",
    )

    let buffer = try GeneratedAudioPCM.buffer(
        from: [0.25, -0.5],
        format: format,
        sourceChannelCount: 1,
        context: "unit test mono buffer",
    )

    #expect(buffer.format.commonFormat == .pcmFormatFloat32)
    #expect(buffer.format.channelCount == 1)
    #expect(Int(buffer.format.sampleRate.rounded()) == 24000)
    #expect(buffer.frameLength == 2)
    #expect(buffer.floatChannelData?[0][0] == 0.25)
    #expect(buffer.floatChannelData?[0][1] == -0.5)
}

@Test func `generated audio pcm deinterleaves stereo samples`() throws {
    let format = try GeneratedAudioPCM.float32Format(
        sampleRate: 48000,
        channelCount: 2,
        context: "unit test stereo buffer",
    )

    let buffer = try GeneratedAudioPCM.buffer(
        from: [0.1, 0.2, 0.3, 0.4],
        format: format,
        sourceChannelCount: 2,
        context: "unit test stereo buffer",
    )

    #expect(buffer.format.channelCount == 2)
    #expect(buffer.frameLength == 2)
    #expect(buffer.floatChannelData?[0][0] == 0.1)
    #expect(buffer.floatChannelData?[1][0] == 0.2)
    #expect(buffer.floatChannelData?[0][1] == 0.3)
    #expect(buffer.floatChannelData?[1][1] == 0.4)
}

@Test func `generated audio pcm rejects mismatched channel sample counts`() throws {
    let format = try GeneratedAudioPCM.float32Format(
        sampleRate: 48000,
        channelCount: 2,
        context: "unit test invalid stereo buffer",
    )

    #expect(throws: GeneratedAudioPCMError.self) {
        _ = try GeneratedAudioPCM.buffer(
            from: [0.1, 0.2, 0.3],
            format: format,
            sourceChannelCount: 2,
            context: "unit test invalid stereo buffer",
        )
    }
}

@Test func `generated audio pcm validates chunk format before creating buffer`() throws {
    let chunk = GeneratedAudioChunk(
        requestID: "req-pcm",
        sequenceNumber: 0,
        sampleRate: 24000,
        channelCount: 1,
        samples: [0.25],
    )
    let format = try GeneratedAudioPCM.float32Format(
        sampleRate: Double(chunk.sampleRate),
        channelCount: chunk.channelCount,
        context: "unit test chunk buffer",
    )

    let buffer = try GeneratedAudioPCM.buffer(
        from: chunk,
        format: format,
        context: "unit test chunk buffer",
    )

    #expect(buffer.frameLength == 1)
    #expect(buffer.floatChannelData?[0][0] == 0.25)
}
