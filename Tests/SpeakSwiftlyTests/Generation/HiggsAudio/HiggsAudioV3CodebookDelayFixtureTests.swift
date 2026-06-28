import Foundation
import Testing

@Test func `higgs audio v3 codebook delay fixture pins constants`() throws {
    let fixture = try HiggsAudioV3CodebookDelayFixture.load()

    #expect(fixture.schemaVersion == 1)
    #expect(fixture.createdAtUtc == "2026-06-26T00:00:00Z")
    #expect(fixture.source.noModelWeightsDownloaded)
    #expect(fixture.constants.numCodebooks == 8)
    #expect(fixture.constants.numRealCodes == 1024)
    #expect(fixture.constants.codebookVocabSize == 1026)
    #expect(fixture.constants.bocID == 1024)
    #expect(fixture.constants.eocID == 1025)
    #expect(fixture.constants.delayPattern == [0, 1, 2, 3, 4, 5, 6, 7])
}

@Test func `higgs audio v3 synthetic delay pattern round trips raw code rows`() throws {
    let fixture = try HiggsAudioV3CodebookDelayFixture.load()

    #expect(fixture.rawCodes.shape == [3, 8])
    #expect(fixture.delayedCodes.shape == [10, 8])
    #expect(fixture.reversedCodes.shape == [3, 8])
    #expect(fixture.reversedCodes.matchesRawCodes)
    #expect(fixture.reversedCodes.rows == fixture.rawCodes.rows)
}

@Test func `higgs audio v3 delayed rows preserve ramp in and wind down markers`() throws {
    let fixture = try HiggsAudioV3CodebookDelayFixture.load()
    let rows = fixture.delayedCodes.rows

    #expect(rows[0] == [10, 1024, 1024, 1024, 1024, 1024, 1024, 1024])
    #expect(rows[1] == [20, 11, 1024, 1024, 1024, 1024, 1024, 1024])
    #expect(rows[2] == [30, 21, 12, 1024, 1024, 1024, 1024, 1024])
    #expect(rows[3] == [1025, 31, 22, 13, 1024, 1024, 1024, 1024])
    #expect(rows[7] == [1025, 1025, 1025, 1025, 1025, 35, 26, 17])
    #expect(rows[9] == [1025, 1025, 1025, 1025, 1025, 1025, 1025, 37])
}

private struct HiggsAudioV3CodebookDelayFixture: Decodable {
    struct Source: Decodable {
        let noModelWeightsDownloaded: Bool
    }

    struct Constants: Decodable {
        let numCodebooks: Int
        let numRealCodes: Int
        let codebookVocabSize: Int
        let bocID: Int
        let eocID: Int
        let delayPattern: [Int]

        enum CodingKeys: String, CodingKey {
            case numCodebooks
            case numRealCodes
            case codebookVocabSize
            case bocID = "bocId"
            case eocID = "eocId"
            case delayPattern
        }
    }

    struct Matrix: Decodable {
        let shape: [Int]
        let rows: [[Int]]
    }

    struct ReversedCodes: Decodable {
        let shape: [Int]
        let rows: [[Int]]
        let matchesRawCodes: Bool
    }

    let schemaVersion: Int
    let createdAtUtc: String
    let source: Source
    let constants: Constants
    let rawCodes: Matrix
    let delayedCodes: Matrix
    let reversedCodes: ReversedCodes

    static func load() throws -> Self {
        let fixtureURL = try higgsAudioV3DelayFixtureURL(
            "docs/research/speech-pipelines/lanes/higgs-audio-v3/codebook-delay-fixture-2026-06-26.json",
        )
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Self.self, from: data)
    }
}

private func higgsAudioV3DelayFixtureURL(_ relativePath: String) throws -> URL {
    try higgsAudioV3DelayPackageRootURL()
        .appendingPathComponent(relativePath)
}

private func higgsAudioV3DelayPackageRootURL() throws -> URL {
    let fileManager = FileManager.default
    var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    while true {
        let manifestURL = candidateURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return candidateURL
        }

        let parentURL = candidateURL.deletingLastPathComponent()
        guard parentURL != candidateURL else {
            throw HiggsAudioV3DelayFixtureError(
                "The Higgs Audio v3 delay fixture tests could not find Package.swift while walking upward from '\(#filePath)'.",
            )
        }

        candidateURL = parentURL
    }
}

private struct HiggsAudioV3DelayFixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
