import Foundation

// MARK: - Generation Queue

actor SpeechGenerationController {
    enum QueueReadiness: Equatable {
        case preparing
        case ready
    }

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
    private var preparingTokens = Set<UUID>()

    func enqueue(_ request: WorkerRequest, readiness: QueueReadiness = .ready) -> Job {
        let job = Job(request: request)
        queue.append(job)
        if readiness == .preparing {
            preparingTokens.insert(job.token)
        }
        return job
    }

    func markReady(token: UUID) -> Job? {
        guard let job = queue.first(where: { $0.token == token }) else { return nil }

        preparingTokens.remove(token)
        return job
    }

    func isPreparing(token: UUID) -> Bool {
        preparingTokens.contains(token)
    }

    func preparingJobTokens() -> Set<UUID> {
        preparingTokens
    }

    func reserveQueuedJobs(tokens: [UUID]) -> [Job] {
        let tokenSet = Set(tokens)
        let reserved = queue.filter { tokenSet.contains($0.token) }
        queue.removeAll { tokenSet.contains($0.token) }
        preparingTokens.subtract(tokenSet)
        for job in reserved {
            activeJobs[job.token] = job
        }
        return reserved
    }

    func finishActive(token: UUID) {
        activeJobs.removeValue(forKey: token)
    }

    func cancel(requestID: String, removeActive: Bool = true) -> CancellationTarget? {
        if let active = activeJobs.values.first(where: { $0.request.id == requestID }) {
            if removeActive {
                activeJobs.removeValue(forKey: active.token)
            }
            return .active(active)
        }

        if let index = queue.firstIndex(where: { $0.request.id == requestID }) {
            let job = queue.remove(at: index)
            preparingTokens.remove(job.token)
            return .queued(job)
        }

        return nil
    }

    func clearQueued() -> [Job] {
        let queued = queue
        queue.removeAll()
        preparingTokens.removeAll()
        return queued
    }

    func activeJobsOrdered() -> [Job] {
        activeJobs.values.sorted { $0.request.id < $1.request.id }
    }

    func readyQueuedJobsOrdered() -> [Job] {
        orderedWaitingQueue(in: queue.filter { !preparingTokens.contains($0.token) })
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
