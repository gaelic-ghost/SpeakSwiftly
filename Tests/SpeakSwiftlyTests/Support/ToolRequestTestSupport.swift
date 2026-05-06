@testable import SpeakSwiftly
@testable import SpeakSwiftlyTool

extension SpeakSwiftly.Runtime {
    func accept(line: String) async {
        do {
            let request = try ToolRequest.decode(from: line)
            await request.submit(to: self)
        } catch {
            let requestID = bestEffortID(from: line)
            let workerError = error as? WorkerError ?? WorkerError(
                code: .internalError,
                message: "The test JSONL request could not be decoded due to an unexpected internal error. \(error.localizedDescription)",
            )
            await failRequestStream(for: requestID, error: workerError)
            await emitFailure(id: requestID, error: workerError)
        }
    }
}
