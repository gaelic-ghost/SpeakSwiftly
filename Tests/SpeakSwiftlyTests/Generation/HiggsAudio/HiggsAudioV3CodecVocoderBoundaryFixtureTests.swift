import Foundation
import Testing

@Test func `higgs audio v3 codec vocoder fixture pins source boundaries`() throws {
    let fixture = try HiggsAudioV3CodecVocoderBoundaryFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-06-28T00:00:00Z")
    #expect(fixture.source.noModelWeightsDownloaded)
    #expect(fixture.source.officialSources.codecVocoder.contains("model.safetensors.index.json bundled codec prefix"))
    #expect(fixture.source.officialSources.outputContainer.contains("Boson create-speech API"))
}

@Test func `higgs audio v3 codec vocoder fixture pins bundled codec weight prefix`() throws {
    let fixture = try HiggsAudioV3CodecVocoderBoundaryFixture.load()
    let boundary = fixture.codecVocoderWeightBoundary

    #expect(boundary.codecCheckpointPrefix == "tied.embedding.modality_embeddings.0.model.")
    #expect(boundary.codecWeightEntryCount == 528)
    #expect(boundary.totalWeightEntryCount == 927)
    #expect(boundary.totalWeightSizeBytes == 8_489_763_794)
    #expect(boundary.textBodyPrefix == "body.layers.")
    #expect(boundary.textBodyWeightEntryCount == 396)
    #expect(boundary.audioEmbeddingPrefix == "tied.embedding.modality_embeddings.0.embedding")
    #expect(boundary.audioEmbeddingWeightEntryCount == 1)
    #expect(boundary.separateTiedHeadWeightEntryCount == 0)
    #expect(boundary.usefulBackendRequiresCodecVocoder)
    #expect(boundary.codecWeightExamples.first == "tied.embedding.modality_embeddings.0.model.acoustic_decoder.block.0.conv_t1.bias")
}

@Test func `higgs audio v3 codec vocoder fixture pins decode boundary constants`() throws {
    let fixture = try HiggsAudioV3CodecVocoderBoundaryFixture.load()
    let boundary = fixture.codebookDecodeBoundary

    #expect(boundary.rawCodesShape == [3, 8])
    #expect(boundary.delayedCodesShape == [10, 8])
    #expect(boundary.reversedCodesShape == [3, 8])
    #expect(boundary.codebookAxisOrder == "frame_major_rows_codebook_columns")
    #expect(boundary.bocId == 1024)
    #expect(boundary.eocId == 1025)
    #expect(boundary.filteringRule == "reverse_delay_pattern_then_remove_boc_eoc_markers_before_codec_decode")
    #expect(boundary.sampleRateHz == 24000)
    #expect(boundary.outputSampleCountKnown == false)
    #expect(boundary.outputDtypeKnown == false)
    #expect(boundary.outputChannelCountKnown == false)
}

@Test func `higgs audio v3 codec vocoder fixture blocks runtime promotion`() throws {
    let fixture = try HiggsAudioV3CodecVocoderBoundaryFixture.load()

    #expect(fixture.outputContainerBoundary.nonStreamingContainerKnown == false)
    #expect(fixture.outputContainerBoundary.streamingPcmIsCurrentServingSignal)
    #expect(fixture.outputContainerBoundary.requiresFutureOfficialServingComparison)
    #expect(fixture.streamingChunkDefaults.codecChunkFrames == 25)
    #expect(fixture.streamingChunkDefaults.codecLeftContextFrames == 25)
    #expect(fixture.streamingChunkDefaults.codecRightHoldbackFrames == 4)
    #expect(fixture.streamingChunkDefaults.initialCodecChunkFrames == 1)
    #expect(fixture.promotionGate.graphOnlyTextToCodebookIsNotSufficient)
    #expect(fixture.promotionGate.runtimeIntegrationAllowed == false)
    #expect(fixture.promotionGate.nextRequiredEvidence.contains("waveform metadata capture"))
}

private struct HiggsAudioV3CodecVocoderBoundaryFixture: Decodable {
    struct Source: Decodable {
        struct OfficialSources: Decodable {
            let codecVocoder: [String]
            let outputContainer: [String]
        }

        let officialSources: OfficialSources
        let noModelWeightsDownloaded: Bool
    }

    struct CodecVocoderWeightBoundary: Decodable {
        let codecCheckpointPrefix: String
        let codecWeightEntryCount: Int
        let codecWeightExamples: [String]
        let totalWeightEntryCount: Int
        let totalWeightSizeBytes: Int
        let textBodyPrefix: String
        let textBodyWeightEntryCount: Int
        let audioEmbeddingPrefix: String
        let audioEmbeddingWeightEntryCount: Int
        let separateTiedHeadWeightEntryCount: Int
        let usefulBackendRequiresCodecVocoder: Bool
    }

    struct CodebookDecodeBoundary: Decodable {
        let rawCodesShape: [Int]
        let delayedCodesShape: [Int]
        let reversedCodesShape: [Int]
        let codebookAxisOrder: String
        let bocId: Int
        let eocId: Int
        let filteringRule: String
        let sampleRateHz: Int
        let outputSampleCountKnown: Bool
        let outputDtypeKnown: Bool
        let outputChannelCountKnown: Bool
    }

    struct OutputContainerBoundary: Decodable {
        let nonStreamingContainerKnown: Bool
        let streamingPcmIsCurrentServingSignal: Bool
        let requiresFutureOfficialServingComparison: Bool
    }

    struct StreamingChunkDefaults: Decodable {
        let codecChunkFrames: Int
        let codecLeftContextFrames: Int
        let codecRightHoldbackFrames: Int
        let initialCodecChunkFrames: Int
    }

    struct PromotionGate: Decodable {
        let graphOnlyTextToCodebookIsNotSufficient: Bool
        let runtimeIntegrationAllowed: Bool
        let nextRequiredEvidence: [String]
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let codecVocoderWeightBoundary: CodecVocoderWeightBoundary
    let codebookDecodeBoundary: CodebookDecodeBoundary
    let outputContainerBoundary: OutputContainerBoundary
    let streamingChunkDefaults: StreamingChunkDefaults
    let promotionGate: PromotionGate

    static func load() throws -> Self {
        let fixtureURL = try higgsAudioV3CodecVocoderFixtureURL(
            "docs/research/speech-pipelines/lanes/higgs-audio-v3/codec-vocoder-boundary-fixture-2026-06-28.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private func higgsAudioV3CodecVocoderFixtureURL(_ relativePath: String) throws -> URL {
    try higgsAudioV3CodecVocoderPackageRootURL()
        .appendingPathComponent(relativePath)
}

private func higgsAudioV3CodecVocoderPackageRootURL() throws -> URL {
    let fileManager = FileManager.default
    var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    while true {
        let manifestURL = candidateURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return candidateURL
        }

        let parentURL = candidateURL.deletingLastPathComponent()
        guard parentURL != candidateURL else {
            throw HiggsAudioV3CodecVocoderFixtureError(
                "The Higgs Audio v3 codec/vocoder fixture tests could not find Package.swift while walking upward from '\(#filePath)'.",
            )
        }

        candidateURL = parentURL
    }
}

private struct HiggsAudioV3CodecVocoderFixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
