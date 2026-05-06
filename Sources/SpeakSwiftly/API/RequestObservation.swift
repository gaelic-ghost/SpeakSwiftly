import Foundation

// MARK: - Request Observation API

public extension SpeakSwiftly.Runtime {
    // MARK: Request Observation

    /// Returns the most recent retained snapshot for a request, if one is available.
    func request(id requestID: String) -> SpeakSwiftly.RequestSnapshot? {
        requestSnapshot(for: requestID)
    }

    /// Subscribes to sequenced state updates for one request.
    func updates(
        for requestID: String,
    ) -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error> {
        makeRequestUpdateStream(for: requestID)
    }

    /// Subscribes to sequenced synthesis updates for one request.
    func synthesisUpdates(
        for requestID: String,
    ) -> AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error> {
        makeSynthesisUpdateStream(for: requestID)
    }
}
