import Foundation

func qwen3TTSFixtureURL(_ relativePath: String) throws -> URL {
    try qwen3TTSPackageRootURL()
        .appendingPathComponent(relativePath)
}

private func qwen3TTSPackageRootURL() throws -> URL {
    let fileManager = FileManager.default
    var candidateURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    while true {
        let manifestURL = candidateURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return candidateURL
        }

        let parentURL = candidateURL.deletingLastPathComponent()
        guard parentURL != candidateURL else {
            throw Qwen3TTSFixtureError(
                "The Qwen3-TTS fixture tests could not find Package.swift while walking upward from '\(#filePath)'.",
            )
        }

        candidateURL = parentURL
    }
}

private struct Qwen3TTSFixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
