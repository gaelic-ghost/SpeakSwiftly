import Foundation

// MARK: - Generated File API

public extension SpeakSwiftly.Runtime {
    func generatedFile(
        id artifactID: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.generatedFile(id: requestID, artifactID: artifactID))
    }

    func generatedFiles(
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.generatedFiles(id: requestID))
    }
}
