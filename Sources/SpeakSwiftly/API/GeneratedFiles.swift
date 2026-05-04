import Foundation

public extension SpeakSwiftly {
    /// Accesses retained generated-audio artifacts.
    ///
    /// Use this handle to list the retained artifacts known to the runtime.
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

    // MARK: Artifact Queries

    /// Retrieves one retained generated-audio artifact by identifier.
    ///
    /// - Parameter artifactID: The identifier of the generated audio artifact to fetch.
    /// - Returns: A request handle whose terminal success payload includes one generated artifact.
    func artifact(id artifactID: String) async -> SpeakSwiftly.RequestHandle {
        await submit(.generatedFile(id: UUID().uuidString, artifactID: artifactID))
    }
}

public extension SpeakSwiftly.Artifacts {
    // MARK: Artifact Queries

    /// Lists the retained generated-audio artifacts known to the runtime.
    ///
    /// - Returns: A request handle whose terminal success payload includes retained artifacts.
    func callAsFunction() async -> SpeakSwiftly.RequestHandle {
        await list()
    }

    /// Lists the retained generated-audio artifacts known to the runtime.
    ///
    /// - Returns: A request handle whose terminal success payload includes retained artifacts.
    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFiles(id: UUID().uuidString))
    }
}
