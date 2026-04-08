import Foundation

// MARK: - Generation Queue

actor GenerationController {
    enum RunDisposition: Sendable, Equatable {
        case run
        case skip
        case park
    }

    struct Job: Sendable, Equatable {
        let token: UUID
        let request: WorkerRequest

        init(token: UUID = UUID(), request: WorkerRequest) {
            self.token = token
            self.request = request
        }
    }

    enum CancellationTarget: Sendable, Equatable {
        case active(Job)
        case queued(Job)
    }

    private var queue = [Job]()
    private var active: Job?

    func enqueue(_ request: WorkerRequest) -> Job {
        let job = Job(request: request)
        queue.append(job)
        return job
    }

    func beginNextIfPossible(
        _ disposition: @escaping (Job) -> RunDisposition
    ) -> Job? {
        guard active == nil else { return nil }
        guard let index = nextQueueIndex(disposition) else { return nil }
        let job = queue.remove(at: index)
        active = job
        return job
    }

    func nextQueuedJob(
        _ disposition: @escaping (Job) -> RunDisposition
    ) -> Job? {
        guard active == nil else { return nil }
        guard let index = nextQueueIndex(disposition) else { return nil }
        return queue[index]
    }

    func finishActive(token: UUID) {
        guard active?.token == token else { return }
        active = nil
    }

    func cancel(requestID: String) -> CancellationTarget? {
        if let active, active.request.id == requestID {
            self.active = nil
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

    func activeJob() -> Job? {
        active
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

    private func nextQueueIndex(_ disposition: @escaping (Job) -> RunDisposition) -> Int? {
        let prioritizedJobs = orderedWaitingQueue()
        var sawParkedResidentDependentWork = false

        for job in prioritizedJobs where !isBlockedByProfileCreation(job) {
            if sawParkedResidentDependentWork && !job.request.canBypassParkedResidentWork {
                return nil
            }

            let runDisposition = disposition(job)
            if job.request.formsOrderedControlBarrier && runDisposition != .run {
                return nil
            }

            switch runDisposition {
            case .run:
                break
            case .skip:
                continue
            case .park:
                if job.request.requiresResidentModels {
                    sawParkedResidentDependentWork = true
                }
                continue
            }

            if let index = queue.firstIndex(where: { $0.token == job.token }) {
                return index
            }
        }

        return nil
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

    private func isBlockedByProfileCreation(_ job: Job) -> Bool {
        guard case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileName: _, jobType: _, textContext: _, sourceFormat: _) = job.request else {
            return false
        }

        if let active, activeRequestCreatesProfileNamed(active.request, profileName: profileName) {
            return true
        }

        for queuedJob in queue {
            if queuedJob.token == job.token {
                break
            }

            if activeRequestCreatesProfileNamed(queuedJob.request, profileName: profileName) {
                return true
            }
        }

        return false
    }

    private func activeRequestCreatesProfileNamed(_ request: WorkerRequest, profileName: String) -> Bool {
        switch request {
        case .createProfile(_, let activeProfileName, _, _, _, _, _):
            return activeProfileName == profileName
        case .createClone(_, let activeProfileName, _, _, _, _):
            return activeProfileName == profileName
        default:
            return false
        }
    }
}
