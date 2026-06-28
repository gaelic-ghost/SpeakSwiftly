import Foundation
import Testing

@Test func `qwen3 tts calibration inventory names current graph scope`() throws {
    let fixture = try Qwen3TTSCalibrationDatasetInventoryFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.mode == "coreml_calibration_dataset_inventory")
    #expect(fixture.calibrationScope.currentGraph == "12 Hz speech-tokenizer decoder only")
    #expect(fixture.calibrationScope.currentInput == "audio_codes shaped batch x code_steps x 16 codebooks")
    #expect(fixture.calibrationScope.notYetCovered.contains("main Qwen3-TTS autoregressive talker"))
    #expect(fixture.calibrationScope.notYetCovered.contains("code predictor"))
}

@Test func `qwen3 tts calibration inventory keeps libritts r as primary decoder candidate`() throws {
    let fixture = try Qwen3TTSCalibrationDatasetInventoryFixture.load()
    let primary = try #require(fixture.candidate("mythicinfinity/libritts_r"))

    #expect(primary.role == "primary_decoder_calibration")
    #expect(primary.available == true)
    #expect(primary.config == "clean")
    #expect(primary.split == "train.clean.100")
    #expect(primary.audioSamplingRates == [24000])
    #expect(primary.stringColumns?.contains("text_normalized") == true)
    #expect(primary.stringColumns?.contains("speaker_id") == true)
    #expect(primary.hubUrl == "https://hf.co/datasets/mythicinfinity/libritts_r")
}

@Test func `qwen3 tts calibration inventory records diversity and control datasets`() throws {
    let fixture = try Qwen3TTSCalibrationDatasetInventoryFixture.load()
    let librispeech = try #require(fixture.candidate("openslr/librispeech_asr"))
    let commonVoice = try #require(fixture.candidate("fixie-ai/common_voice_17_0"))

    #expect(librispeech.role == "broad_read_speech_control")
    #expect(librispeech.audioSamplingRates == [16000])
    #expect(commonVoice.role == "accent_and_speaker_diversity_control")
    #expect(commonVoice.audioSamplingRates == [48000])
    #expect(commonVoice.stringColumns?.contains("accent") == true)
    #expect(commonVoice.stringColumns?.contains("gender") == true)
}

private struct Qwen3TTSCalibrationDatasetInventoryFixture: Decodable {
    struct CalibrationScope: Decodable {
        let currentGraph: String
        let currentInput: String
        let notYetCovered: [String]
    }

    struct Candidate: Decodable {
        let dataset: String
        let config: String
        let split: String
        let role: String
        let hubUrl: String
        let available: Bool
        let audioSamplingRates: [Int]?
        let stringColumns: [String]?
    }

    let schemaVersion: Int
    let mode: String
    let calibrationScope: CalibrationScope
    let candidates: [Candidate]

    func candidate(_ dataset: String) -> Candidate? {
        candidates.first { $0.dataset == dataset }
    }

    static func load() throws -> Self {
        let fixtureURL = try qwen3TTSFixtureURL(
            "docs/research/speech-pipelines/lanes/qwen3-tts-coreml-coreai/archive/coreml-qwen3tts/calibration-dataset-inventory-2026-05-31.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}
