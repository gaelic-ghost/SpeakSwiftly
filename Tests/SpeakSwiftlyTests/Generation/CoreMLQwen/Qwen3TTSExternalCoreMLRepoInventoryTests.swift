import Foundation
import Testing

@Test func `qwen3 tts external coreml inventory tracks source revisions`() throws {
    let fixture = try Qwen3TTSExternalCoreMLRepoInventory.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-06-04T00:00:00Z")
    #expect(fixture.source.noLargeArtifactsDownloaded)
    #expect(fixture.repositories.map(\.repoId) == [
        "FluidInference/qwen3-tts-coreml",
        "aufklarer/Qwen3-TTS-CoreML",
    ])
    #expect(fixture.repository(id: "FluidInference/qwen3-tts-coreml")?.resolvedRevision == "7bb6c4e5c425ddecc0aa2339f125398623d2da36")
    #expect(fixture.repository(id: "aufklarer/Qwen3-TTS-CoreML")?.resolvedRevision == "66ca03b95a684d45e020b1d2d5c3ab34a48356f9")
}

@Test func `qwen3 tts external coreml inventory compares artifact shape`() throws {
    let fixture = try Qwen3TTSExternalCoreMLRepoInventory.load()
    let fluid = try #require(fixture.repository(id: "FluidInference/qwen3-tts-coreml"))
    let aufklarer = try #require(fixture.repository(id: "aufklarer/Qwen3-TTS-CoreML"))

    #expect(fixture.comparison.sharedCompiledModels == [
        "CodeDecoder.mlmodelc",
        "CodeEmbedder.mlmodelc",
        "MultiCodeDecoder.mlmodelc",
        "MultiCodeEmbedder.mlmodelc",
        "SpeechDecoder.mlmodelc",
        "TextProjector.mlmodelc",
    ])
    #expect(fluid.artifactInventory.sourcePackageNames.count == 6)
    #expect(aufklarer.artifactInventory.sourcePackageNames.isEmpty)
    #expect(!fluid.artifactInventory.hasVocabJson)
    #expect(!fluid.artifactInventory.hasMergesTxt)
    #expect(aufklarer.artifactInventory.hasVocabJson)
    #expect(aufklarer.artifactInventory.hasMergesTxt)
    #expect(fluid.artifactInventory.hasCpEmbeddings)
    #expect(!aufklarer.artifactInventory.hasCpEmbeddings)
}

@Test func `qwen3 tts external coreml inventory adds aufklarer as metadata probe only`() throws {
    let fixture = try Qwen3TTSExternalCoreMLRepoInventory.load()
    let aufklarer = try #require(fixture.repository(id: "aufklarer/Qwen3-TTS-CoreML"))

    #expect(aufklarer.config.modelType == "qwen3_tts_coreml")
    #expect(aufklarer.config.architecture == "6-model-ane")
    #expect(aufklarer.config.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(aufklarer.config.quantization == "W8A16")
    #expect(aufklarer.config.models == [
        "TextProjector",
        "CodeEmbedder",
        "MultiCodeEmbedder",
        "CodeDecoder",
        "MultiCodeDecoder",
        "SpeechDecoder",
    ])
    #expect(fixture.decision.matrixStatus == "add_metadata_probe_only")
    #expect(fixture.decision.reason.contains("worth tracking"))
    #expect(fixture.decision.nextProbe.contains("talker/code-generator"))
    #expect(fixture.decision.doNotDoYet.contains("Do not add a public SpeechBackend."))
}

private struct Qwen3TTSExternalCoreMLRepoInventory: Decodable {
    struct Source: Decodable {
        let noLargeArtifactsDownloaded: Bool
    }

    struct Repository: Decodable {
        struct Config: Decodable {
            let modelType: String?
            let architecture: String?
            let modelId: String?
            let models: [String]
            let quantization: String?
        }

        struct ArtifactInventory: Decodable {
            let sourcePackageNames: [String]
            let hasVocabJson: Bool
            let hasMergesTxt: Bool
            let hasCpEmbeddings: Bool
        }

        let repoId: String
        let resolvedRevision: String
        let config: Config
        let artifactInventory: ArtifactInventory
    }

    struct Comparison: Decodable {
        let sharedCompiledModels: [String]
    }

    struct Decision: Decodable {
        let matrixStatus: String
        let reason: String
        let nextProbe: String
        let doNotDoYet: [String]
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let repositories: [Repository]
    let comparison: Comparison
    let decision: Decision

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/external-coreml-qwen3tts-repo-inventory-2026-06-04.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }

    func repository(id: String) -> Repository? {
        repositories.first { $0.repoId == id }
    }
}
