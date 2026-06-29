import Foundation
import Testing

@Test func `higgs audio v3 serving comparison fixture pins source scope`() throws {
    let fixture = try HiggsAudioV3OfficialServingComparisonFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-06-29T00:00:00Z")
    #expect(fixture.source.noModelWeightsDownloaded)
    #expect(fixture.source.noServingRequestExecuted)
    #expect(fixture.source.officialSources.outputContainer.contains("vLLM deploy YAML and OpenAI adapter"))
    #expect(fixture.source.officialSources.waveformPostProcessing.contains("SGLang vocoder scheduler"))
}

@Test func `higgs audio v3 serving comparison fixture uses plain prompt case`() throws {
    let fixture = try HiggsAudioV3OfficialServingComparisonFixture.load()
    let prompt = fixture.promptCase

    #expect(prompt.name == "plain-english-tts")
    #expect(prompt.kind == "plain_tts")
    #expect(prompt.rawText == "Welcome to SpeakSwiftly. This is the first official Higgs Audio v3 parity fixture.")
    #expect(prompt.promptShape == "<|tts|> <|text|> target text tokens <|audio|>")
    #expect(prompt.promptLength == 22)
}

@Test func `higgs audio v3 serving comparison fixture preserves official output signals`() throws {
    let fixture = try HiggsAudioV3OfficialServingComparisonFixture.load()
    let signals = fixture.officialServingSignals.map(\.signal)

    #expect(signals.contains("Talker text-to-eight-codebook rows feed Code2Wav codec-to-24-kHz-PCM output."))
    #expect(signals.contains("async_chunk streams PCM bytes back to the client as Stage 1 emits each chunk."))
    #expect(
        signals.contains(
            "Some docs mention streaming WAV chunks, while current serving docs emphasize raw PCM for streaming.",
        ),
    )
    #expect(fixture.streamingOutputContract.containerKnown)
    #expect(fixture.streamingOutputContract.container == "raw_pcm_bytes")
    #expect(fixture.streamingOutputContract.base64WavSignalStillUnresolved)
    #expect(fixture.streamingOutputContract.requiresExecutedOfficialServingRequest)
}

@Test func `higgs audio v3 serving comparison fixture keeps waveform metadata gated`() throws {
    let fixture = try HiggsAudioV3OfficialServingComparisonFixture.load()
    let metadata = fixture.waveformMetadata

    #expect(metadata.sampleRateHz == 24000)
    #expect(metadata.sampleRateConfirmedBySourceMap)
    #expect(metadata.decodedSampleCountKnown == false)
    #expect(metadata.decodedDtypeKnown == false)
    #expect(metadata.decodedChannelCountKnown == false)
    #expect(metadata.observedDecodedSampleCount == nil)
    #expect(metadata.observedDecodedDtype == nil)
    #expect(metadata.observedDecodedChannelCount == nil)
    #expect(metadata.requiresExecutedOfficialServingRequest)
}

@Test func `higgs audio v3 serving comparison fixture pins streaming chunk expectations`() throws {
    let fixture = try HiggsAudioV3OfficialServingComparisonFixture.load()
    let chunks = fixture.streamingChunkExpectations

    #expect(chunks.codecChunkFrames == 25)
    #expect(chunks.codecLeftContextFrames == 25)
    #expect(chunks.codecRightHoldbackFrames == 4)
    #expect(chunks.initialCodecChunkFrames == 1)
    #expect(chunks.nominalSecondsPerCodecChunk == 1.0)
    #expect(chunks.nominalCodecFrameRateHz == 25)
}

@Test func `higgs audio v3 serving comparison fixture blocks runtime promotion`() throws {
    let fixture = try HiggsAudioV3OfficialServingComparisonFixture.load()

    #expect(fixture.nonStreamingOutputContract.containerKnown == false)
    #expect(fixture.nonStreamingOutputContract.container == nil)
    #expect(fixture.nonStreamingOutputContract.requiresExecutedOfficialServingRequest)
    #expect(fixture.promotionGate.runtimeIntegrationAllowed == false)
    #expect(fixture.promotionGate.officialServingComparisonStarted)
    #expect(fixture.promotionGate.officialServingRequestExecuted == false)
    #expect(fixture.promotionGate.codecFixtureRuntimePromotionAllowed == false)
    #expect(fixture.promotionGate.remainingBlockers.contains("capture decoded sample count"))
    #expect(fixture.promotionGate.remainingBlockers.contains("capture decoded dtype"))
    #expect(fixture.promotionGate.remainingBlockers.contains("capture decoded channel count"))
}

private struct HiggsAudioV3OfficialServingComparisonFixture: Decodable {
    struct Source: Decodable {
        struct OfficialSources: Decodable {
            let waveformPostProcessing: [String]
            let outputContainer: [String]
        }

        let officialSources: OfficialSources
        let noModelWeightsDownloaded: Bool
        let noServingRequestExecuted: Bool
    }

    struct PromptCase: Decodable {
        let name: String
        let kind: String
        let rawText: String
        let promptShape: String
        let promptLength: Int
    }

    struct OfficialServingSignal: Decodable {
        let source: String
        let signal: String
        let capturedFrom: String
    }

    struct OutputContract: Decodable {
        let containerKnown: Bool
        let container: String?
        let requiresExecutedOfficialServingRequest: Bool
    }

    struct StreamingOutputContract: Decodable {
        let containerKnown: Bool
        let container: String
        let base64WavSignalStillUnresolved: Bool
        let requiresExecutedOfficialServingRequest: Bool
    }

    struct WaveformMetadata: Decodable {
        let sampleRateHz: Int
        let sampleRateConfirmedBySourceMap: Bool
        let decodedSampleCountKnown: Bool
        let decodedDtypeKnown: Bool
        let decodedChannelCountKnown: Bool
        let observedDecodedSampleCount: Int?
        let observedDecodedDtype: String?
        let observedDecodedChannelCount: Int?
        let requiresExecutedOfficialServingRequest: Bool
    }

    struct StreamingChunkExpectations: Decodable {
        let codecChunkFrames: Int
        let codecLeftContextFrames: Int
        let codecRightHoldbackFrames: Int
        let initialCodecChunkFrames: Int
        let nominalSecondsPerCodecChunk: Double
        let nominalCodecFrameRateHz: Int
    }

    struct PromotionGate: Decodable {
        let runtimeIntegrationAllowed: Bool
        let officialServingComparisonStarted: Bool
        let officialServingRequestExecuted: Bool
        let remainingBlockers: [String]
        let codecFixtureRuntimePromotionAllowed: Bool
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let promptCase: PromptCase
    let officialServingSignals: [OfficialServingSignal]
    let nonStreamingOutputContract: OutputContract
    let streamingOutputContract: StreamingOutputContract
    let waveformMetadata: WaveformMetadata
    let streamingChunkExpectations: StreamingChunkExpectations
    let promotionGate: PromotionGate

    static func load() throws -> Self {
        let fixtureURL = try higgsAudioV3OfficialServingFixtureURL(
            "docs/research/speech-pipelines/lanes/higgs-audio-v3/official-serving-comparison-fixture-2026-06-29.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private func higgsAudioV3OfficialServingFixtureURL(_ relativePath: String) throws -> URL {
    try higgsAudioV3OfficialServingPackageRootURL()
        .appendingPathComponent(relativePath)
}

private func higgsAudioV3OfficialServingPackageRootURL() throws -> URL {
    let fileManager = FileManager.default
    var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    while true {
        let manifestURL = candidateURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return candidateURL
        }

        let parentURL = candidateURL.deletingLastPathComponent()
        guard parentURL != candidateURL else {
            throw HiggsAudioV3OfficialServingFixtureError(
                "The Higgs Audio v3 official serving fixture tests could not find Package.swift while walking upward from '\(#filePath)'.",
            )
        }

        candidateURL = parentURL
    }
}

private struct HiggsAudioV3OfficialServingFixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
