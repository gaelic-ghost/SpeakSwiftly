import Foundation
import Testing

private enum Qwen3TTSPromptWrapping {
    static func target(_ text: String) -> String {
        "<|im_start|>assistant\n\(text)<|im_end|>\n<|im_start|>assistant\n"
    }

    static func reference(_ text: String) -> String {
        "<|im_start|>assistant\n\(text)<|im_end|>\n"
    }

    static func instruction(_ text: String) -> String {
        "<|im_start|>user\n\(text)<|im_end|>\n"
    }
}

@Test func `qwen3 tts text token fixture source is pinned`() throws {
    let fixture = try Qwen3TTSTextTokenFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-05-31T00:00:00Z")
    #expect(fixture.source.upstreamRepository == "https://github.com/QwenLM/Qwen3-TTS")
    #expect(fixture.source.upstreamCommit == "022e286b98fbec7e1e916cb940cdf532cd9f488e")
    #expect(fixture.source.modelId == "Qwen/Qwen3-TTS-12Hz-0.6B-Base")
    #expect(fixture.source.tokenizerClass == "Qwen2Tokenizer")
    #expect(fixture.source.vocabSize == 151_643)
    #expect(fixture.source.modelMaxLength == 131_072)
}

@Test func `swift qwen3 tts prompt wrappers match upstream text fixture`() throws {
    let fixture = try Qwen3TTSTextTokenFixture.load()

    #expect(
        fixture.upstreamPromptWrappers.target
            == "<|im_start|>assistant\\n{text}<|im_end|>\\n<|im_start|>assistant\\n",
    )
    #expect(fixture.upstreamPromptWrappers.reference == "<|im_start|>assistant\\n{text}<|im_end|>\\n")
    #expect(fixture.upstreamPromptWrappers.instruction == "<|im_start|>user\\n{instruct}<|im_end|>\\n")

    let promptsByKind = Dictionary(uniqueKeysWithValues: fixture.prompts.map { ($0.kind, $0) })
    let target = try #require(promptsByKind["target"])
    let reference = try #require(promptsByKind["reference"])
    let instruction = try #require(promptsByKind["instruction"])

    #expect(Qwen3TTSPromptWrapping.target(target.rawText) == target.wrappedText)
    #expect(Qwen3TTSPromptWrapping.reference(reference.rawText) == reference.wrappedText)
    #expect(Qwen3TTSPromptWrapping.instruction(instruction.rawText) == instruction.wrappedText)
}

@Test func `qwen3 tts checked in text token ids stay stable`() throws {
    let fixture = try Qwen3TTSTextTokenFixture.load()
    let promptsByKind = Dictionary(uniqueKeysWithValues: fixture.prompts.map { ($0.kind, $0) })

    let target = try #require(promptsByKind["target"])
    #expect(target.length == 23)
    #expect(target.inputIds == [
        151_644, 77091, 198, 9707, 11, 419, 374, 264, 2613, 1207, 16948, 18, 350, 9951,
        45958, 49615, 1273, 13, 151_645, 198, 151_644, 77091, 198,
    ])
    #expect(target.attentionMask == Array(repeating: 1, count: target.length))

    let reference = try #require(promptsByKind["reference"])
    #expect(reference.length == 12)
    #expect(reference.inputIds == [
        151_644, 77091, 198, 1986, 374, 264, 20628, 5785, 35715, 13, 151_645, 198,
    ])
    #expect(reference.attentionMask == Array(repeating: 1, count: reference.length))

    let instruction = try #require(promptsByKind["instruction"])
    #expect(instruction.length == 14)
    #expect(instruction.inputIds == [
        151_644, 872, 198, 95845, 9355, 448, 264, 19300, 11, 8205, 16232, 13, 151_645,
        198,
    ])
    #expect(instruction.attentionMask == Array(repeating: 1, count: instruction.length))
}

private struct Qwen3TTSTextTokenFixture: Decodable {
    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let upstreamPromptWrappers: UpstreamPromptWrappers
    let prompts: [Prompt]

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL("docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/text-token-fixture-0.6b-base.json")
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }

    struct Source: Decodable {
        let upstreamRepository: String
        let upstreamCommit: String
        let modelId: String
        let tokenizerClass: String
        let vocabSize: Int
        let modelMaxLength: Int
    }

    struct UpstreamPromptWrappers: Decodable {
        let target: String
        let reference: String
        let instruction: String
    }

    struct Prompt: Decodable {
        let kind: String
        let rawText: String
        let wrappedText: String
        let length: Int
        let inputIds: [Int]
        let attentionMask: [Int]
    }
}
