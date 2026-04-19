import Foundation

public extension SpeakSwiftly {
    /// Accesses retained generated-audio artifacts.
    ///
    /// Use this handle to look up one generated file or list the retained files
    /// known to the runtime.
    struct Artifacts: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the generated-artifact query surface for this runtime.
    nonisolated var artifacts: SpeakSwiftly.Artifacts {
        SpeakSwiftly.Artifacts(runtime: self)
    }
}

public extension SpeakSwiftly.Artifacts {
    // MARK: File Queries

    /// Retrieves one retained generated file by artifact identifier.
    ///
    /// - Parameter artifactID: The identifier of the generated audio artifact to fetch.
    /// - Returns: A request handle whose terminal success payload includes one generated file.
    func file(id artifactID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFile(id: UUID().uuidString, artifactID: artifactID))
    }

    /// Lists the retained generated files known to the runtime.
    ///
    /// - Returns: A request handle whose terminal success payload includes retained files.
    func files() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFiles(id: UUID().uuidString))
    }
}
