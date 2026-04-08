import Foundation

// MARK: - Generated File API

public extension SpeakSwiftly {
    // MARK: Artifacts Handle

    struct Artifacts: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    nonisolated var artifacts: SpeakSwiftly.Artifacts {
        SpeakSwiftly.Artifacts(runtime: self)
    }
}

public extension SpeakSwiftly.Artifacts {
    // MARK: File Queries

    func file(id artifactID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFile(id: UUID().uuidString, artifactID: artifactID))
    }

    func files() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFiles(id: UUID().uuidString))
    }
}
