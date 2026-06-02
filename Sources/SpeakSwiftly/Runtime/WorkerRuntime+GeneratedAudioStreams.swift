import Foundation

extension SpeakSwiftly.Runtime {
    func submitGeneratedAudioStream(
        requestID: String,
        text: String,
        profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
    ) async -> SpeakSwiftly.GeneratedAudioStream {
        let stream = AsyncThrowingStream<SpeakSwiftly.GeneratedAudioChunk, any Swift.Error>.makeStream()
        generatedAudioStreamContinuations[requestID] = stream.continuation
        stream.continuation.onTermination = { _ in
            Task {
                await self.removeGeneratedAudioStreamContinuation(for: requestID)
            }
        }

        let handle = await submit(
            .queueSpeech(
                id: requestID,
                text: text,
                profileName: profileName,
                textProfileID: textProfileID,
                jobType: .stream,
                audioFormat: nil,
                requestContext: requestContext,
                qwenPreModelTextChunking: qwenPreModelTextChunking,
            ),
        )
        return SpeakSwiftly.GeneratedAudioStream(handle: handle, chunks: stream.stream)
    }

    func removeGeneratedAudioStreamContinuation(for requestID: String) {
        generatedAudioStreamContinuations.removeValue(forKey: requestID)
    }

    func yieldGeneratedAudioChunk(_ chunk: SpeakSwiftly.GeneratedAudioChunk, for requestID: String) throws {
        guard let continuation = generatedAudioStreamContinuations[requestID] else {
            throw WorkerError(
                code: .requestCancelled,
                message: "Request '\(requestID)' could not continue generated-audio streaming because the caller stopped consuming the chunk stream.",
            )
        }

        continuation.yield(chunk)
    }

    func finishGeneratedAudioStream(for requestID: String, throwing error: (any Swift.Error)? = nil) {
        guard let continuation = generatedAudioStreamContinuations.removeValue(forKey: requestID) else {
            return
        }

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
