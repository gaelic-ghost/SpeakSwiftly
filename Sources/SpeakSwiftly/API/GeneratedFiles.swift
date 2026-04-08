import Foundation

// MARK: - Generated File API

public extension SpeakSwiftly {
    struct Artifacts: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    nonisolated var artifacts: SpeakSwiftly.Artifacts {
        SpeakSwiftly.Artifacts(runtime: self)
    }
}

public extension SpeakSwiftly.Artifacts {
    func file(id artifactID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFile(id: UUID().uuidString, artifactID: artifactID))
    }

    func files() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFiles(id: UUID().uuidString))
    }
}
