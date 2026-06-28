import Foundation
import Testing

@Test func `higgs audio v3 tokenizer parity fixture source is pinned`() throws {
    let fixture = try HiggsAudioV3TokenizerParityFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-06-26T00:00:00Z")
    #expect(fixture.source.modelId == "bosonai/higgs-audio-v3-tts-4b")
    #expect(fixture.source.resolvedRevision == "a7f70853f163c4cccbdd27ce9a80dd97961fc581")
    #expect(fixture.source.noModelWeightsDownloaded)
    #expect(fixture.source.filesDownloaded == [
        "tokenizer.json",
        "tokenizer_config.json",
        "chat_template.jinja",
    ])
}

@Test func `higgs audio v3 runtime constants stay aligned with official fixture`() throws {
    let fixture = try HiggsAudioV3TokenizerParityFixture.load()
    let constants = fixture.officialRuntimeConstants

    #expect(constants.modelType == "higgs_multimodal_qwen3")
    #expect(constants.textHiddenSize == 2560)
    #expect(constants.textVocabSize == 151_936)
    #expect(constants.textLayers == 36)
    #expect(constants.attentionHeads == 32)
    #expect(constants.kvHeads == 8)
    #expect(constants.audioPlaceholderID == -100)
    #expect(constants.numCodebooks == 8)
    #expect(constants.codebookVocabSize == 1026)
    #expect(constants.melPerSample == 8)
    #expect(constants.usesDelayPattern)
    #expect(constants.sampleRateHz == 24000)
    #expect(constants.bocID == 1024)
    #expect(constants.eocID == 1025)
    #expect(constants.codecCheckpointPrefix == "tied.embedding.modality_embeddings.0.model.")
    #expect(constants.ropeParameters["rope_theta"]?.value as? Int == 1_000_000)
    #expect(constants.ropeParameters["rope_type"]?.value as? String == "default")
}

@Test func `higgs audio v3 tokenizer special tokens stay stable`() throws {
    let fixture = try HiggsAudioV3TokenizerParityFixture.load()

    #expect(fixture.tokenizer.tokenizerConfigClass == "Qwen2Tokenizer")
    #expect(fixture.tokenizer.tokenizerModelType == "BPE")
    #expect(fixture.tokenizer.modelMaxLength == 131_072)
    #expect(fixture.tokenizer.addedTokenCount == 84)
    #expect(fixture.tokenizer.chatTemplateAvailable)
    #expect(!fixture.tokenizer.chatTemplateParticipatesInTtsPrompt)
    #expect(fixture.tokenizer.specialTokens["<|tts|>"] == 151_667)
    #expect(fixture.tokenizer.specialTokens["<|audio|>"] == 151_670)
    #expect(fixture.tokenizer.specialTokens["<|audio_end|>"] == 151_671)
    #expect(fixture.tokenizer.specialTokens["<|text|>"] == 151_672)
    #expect(fixture.tokenizer.specialTokens["<|ref_audio|>"] == 151_679)
    #expect(fixture.tokenizer.specialTokens["<|ref_text|>"] == 151_680)
    #expect(fixture.tokenizer.specialTokens["<|emotion:elation|>"] == 151_681)
    #expect(fixture.tokenizer.specialTokens["<|prosody:pause|>"] == 151_722)
}

@Test func `higgs audio v3 plain tts prompt ids match official builder shape`() throws {
    let fixture = try HiggsAudioV3TokenizerParityFixture.load()
    let casesByName = Dictionary(uniqueKeysWithValues: fixture.cases.map { ($0.name, $0) })

    let plain = try #require(casesByName["plain-english-tts"])
    #expect(plain.kind == "plain_tts")
    #expect(plain.promptLength == 22)
    #expect(plain.promptIDs == [
        151_667, 151_672, 13936, 311, 67201, 55336, 398, 13, 1096, 374, 279, 1156,
        3946, 472, 61147, 12352, 348, 18, 49615, 12507, 13, 151_670,
    ])
    #expect(plain.promptTokens.first == "<|tts|>")
    #expect(plain.promptTokens[1] == "<|text|>")
    #expect(plain.promptTokens.last == "<|audio|>")
    #expect(plain.sectionRanges["tts_marker"] == [0, 1])
    #expect(plain.sectionRanges["text_marker"] == [1, 2])
    #expect(plain.sectionRanges["target_text"] == [2, 21])
    #expect(plain.sectionRanges["audio_marker"] == [21, 22])
}

@Test func `higgs audio v3 control tag prompt ids preserve inline tag tokenization`() throws {
    let fixture = try HiggsAudioV3TokenizerParityFixture.load()
    let casesByName = Dictionary(uniqueKeysWithValues: fixture.cases.map { ($0.name, $0) })

    let control = try #require(casesByName["control-tags-tts"])
    #expect(control.promptLength == 16)
    #expect(control.promptIDs == [
        151_667, 151_672, 151_681, 13936, 36506, 13, 21927, 1052, 220, 151_722,
        323, 9339, 369, 14289, 13, 151_670,
    ])
    #expect(control.promptTokens[2] == "<|emotion:elation|>")
    #expect(control.promptTokens[8] == "Ġ")
    #expect(control.promptTokens[9] == "<|prosody:pause|>")
    #expect(control.sectionRanges["target_text"] == [2, 15])
}

private struct HiggsAudioV3TokenizerParityFixture: Decodable {
    struct Source: Decodable {
        let modelId: String
        let resolvedRevision: String
        let filesDownloaded: [String]
        let noModelWeightsDownloaded: Bool
    }

    struct OfficialRuntimeConstants: Decodable {
        let modelType: String
        let textHiddenSize: Int
        let textVocabSize: Int
        let textLayers: Int
        let attentionHeads: Int
        let kvHeads: Int
        let ropeParameters: [String: JSONValue]
        let audioPlaceholderID: Int
        let numCodebooks: Int
        let codebookVocabSize: Int
        let melPerSample: Int
        let usesDelayPattern: Bool
        let codecCheckpointPrefix: String
        let sampleRateHz: Int
        let bocID: Int
        let eocID: Int

        enum CodingKeys: String, CodingKey {
            case modelType
            case textHiddenSize
            case textVocabSize
            case textLayers
            case attentionHeads
            case kvHeads
            case ropeParameters
            case audioPlaceholderID = "audioPlaceholderId"
            case numCodebooks
            case codebookVocabSize
            case melPerSample
            case usesDelayPattern
            case codecCheckpointPrefix
            case sampleRateHz
            case bocID = "bocId"
            case eocID = "eocId"
        }
    }

    struct TokenizerMetadata: Decodable {
        let tokenizerConfigClass: String
        let tokenizerModelType: String
        let modelMaxLength: Int
        let addedTokenCount: Int
        let specialTokens: [String: Int]
        let chatTemplateAvailable: Bool
        let chatTemplateParticipatesInTtsPrompt: Bool
    }

    struct PromptCase: Decodable {
        let name: String
        let kind: String
        let promptLength: Int
        let promptIDs: [Int]
        let promptTokens: [String]
        let sectionRanges: [String: [Int]]

        enum CodingKeys: String, CodingKey {
            case name
            case kind
            case promptLength
            case promptIDs = "promptIds"
            case promptTokens
            case sectionRanges
        }
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let officialRuntimeConstants: OfficialRuntimeConstants
    let tokenizer: TokenizerMetadata
    let cases: [PromptCase]

    static func load() throws -> Self {
        let fixtureURL = try higgsAudioV3FixtureURL(
            "docs/research/speech-pipelines/lanes/higgs-audio-v3/tokenizer-parity-fixture-2026-06-26.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private enum JSONValue: Decodable {
    case value(AnyHashable)

    var value: AnyHashable {
        switch self {
            case let .value(value):
                value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .value(value)
        } else if let value = try? container.decode(Int.self) {
            self = .value(value)
        } else if let value = try? container.decode(Double.self) {
            self = .value(value)
        } else if let value = try? container.decode(String.self) {
            self = .value(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value."),
            )
        }
    }
}

private func higgsAudioV3FixtureURL(_ relativePath: String) throws -> URL {
    try higgsAudioV3PackageRootURL()
        .appendingPathComponent(relativePath)
}

private func higgsAudioV3PackageRootURL() throws -> URL {
    let fileManager = FileManager.default
    var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    while true {
        let manifestURL = candidateURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return candidateURL
        }

        let parentURL = candidateURL.deletingLastPathComponent()
        guard parentURL != candidateURL else {
            throw HiggsAudioV3FixtureError(
                "The Higgs Audio v3 fixture tests could not find Package.swift while walking upward from '\(#filePath)'.",
            )
        }

        candidateURL = parentURL
    }
}

private struct HiggsAudioV3FixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
