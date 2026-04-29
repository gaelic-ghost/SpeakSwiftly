@testable import SpeakSwiftly
import Testing

@Test func `preparing jobs are visible but not runnable until marked ready`() async {
    let controller = SpeechGenerationController()
    let request = makeLiveSpeechRequest(id: "req-preparing")

    let job = await controller.enqueue(request, readiness: .preparing)

    #expect(await controller.queuedJobsOrdered() == [job])
    #expect(await controller.readyQueuedJobsOrdered().isEmpty)

    #expect(await controller.markReady(token: job.token) == job)
    #expect(await controller.readyQueuedJobsOrdered() == [job])
}

@Test func `preparing jobs remain cancellable before they are ready`() async {
    let controller = SpeechGenerationController()
    let request = makeLiveSpeechRequest(id: "req-cancellable-preparing")

    let job = await controller.enqueue(request, readiness: .preparing)
    let cancelled = await controller.cancel(requestID: request.id)

    #expect(cancelled == .queued(job))
    #expect(await controller.queuedJobsOrdered().isEmpty)
    #expect(await controller.readyQueuedJobsOrdered().isEmpty)
    #expect(await controller.markReady(token: job.token) == nil)
}

private func makeLiveSpeechRequest(id: String) -> WorkerRequest {
    .queueSpeech(
        id: id,
        text: "Hello from a live request that is still preparing playback.",
        profileName: "testing-profile",
        textProfileID: nil,
        jobType: .live,
        inputTextContext: nil,
        requestContext: nil,
        qwenPreModelTextChunking: nil,
    )
}
