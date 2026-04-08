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
    func file(
        id artifactID: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFile(id: requestID, artifactID: artifactID))
    }

    func files(
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFiles(id: requestID))
    }
}
