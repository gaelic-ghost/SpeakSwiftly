import Foundation

// MARK: - Generation Queue

actor SpeechGenerationController {
    struct Job: Equatable {
        let token: UUID
        let request: WorkerRequest

        init(token: UUID = UUID(), request: WorkerRequest) {
            self.token = token
            self.request = request
        }
    }

    enum CancellationTarget: Equatable {
        case active(Job)
        case queued(Job)
    }

    private var queue = [Job]()
    private var activeJobs = [UUID: Job]()

    func enqueue(_ request: WorkerRequest) -> Job {
        let job = Job(request: request)
        queue.append(job)
        return job
    }

    func reserveQueuedJobs(tokens: [UUID]) -> [Job] {
        let tokenSet = Set(tokens)
        let reserved = queue.filter { tokenSet.contains($0.token) }
        queue.removeAll { tokenSet.contains($0.token) }
        for job in reserved {
            activeJobs[job.token] = job
        }
        return reserved
    }

    func finishActive(token: UUID) {
        activeJobs.removeValue(forKey: token)
    }

    func cancel(requestID: String) -> CancellationTarget? {
        if let active = activeJobs.values.first(where: { $0.request.id == requestID }) {
            activeJobs.removeValue(forKey: active.token)
            return .active(active)
        }

        if let index = queue.firstIndex(where: { $0.request.id == requestID }) {
            return .queued(queue.remove(at: index))
        }

        return nil
    }

    func clearQueued() -> [Job] {
        let queued = queue
        queue.removeAll()
        return queued
    }

    func activeJobsOrdered() -> [Job] {
        activeJobs.values.sorted { $0.request.id < $1.request.id }
    }

    func queuedJobsOrdered() -> [Job] {
        orderedWaitingQueue()
    }

    func waitingPosition(for token: UUID, residentReady: Bool) -> Int? {
        guard residentReady || !queue.isEmpty else { return nil }
        guard let index = orderedWaitingQueue().firstIndex(where: { $0.token == token }) else {
            return nil
        }

        return index + 1
    }

    private func orderedWaitingQueue() -> [Job] {
        orderedWaitingQueue(in: queue)
    }

    private func orderedWaitingQueue(in jobs: [Job]) -> [Job] {
        guard let barrierIndex = jobs.firstIndex(where: { $0.request.requiresPlaybackDrainBeforeStart }) else {
            let speechJobs = jobs.filter(\.request.isSpeechRequest)
            let otherJobs = jobs.filter { !$0.request.isSpeechRequest }
            return speechJobs + otherJobs
        }

        let prefix = Array(jobs[..<barrierIndex])
        let barrier = jobs[barrierIndex]
        let suffix = Array(jobs[(barrierIndex + 1)...])
        return orderedWaitingQueue(in: prefix) + [barrier] + orderedWaitingQueue(in: suffix)
    }
}
