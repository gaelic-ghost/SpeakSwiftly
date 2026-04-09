import Foundation

// MARK: - Request Observation API

public extension SpeakSwiftly.Runtime {
    // MARK: Request Observation

    func request(id requestID: String) -> SpeakSwiftly.RequestSnapshot? {
        requestSnapshot(for: requestID)
    }

    func updates(
        for requestID: String
    ) -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error> {
        makeRequestUpdateStream(for: requestID)
    }
}
