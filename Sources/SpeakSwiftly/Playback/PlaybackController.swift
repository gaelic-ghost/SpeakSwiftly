import Foundation
import TextForSpeech

// MARK: - Playback Jobs

final class PlaybackJob: @unchecked Sendable {
    let requestID: String
    let op: String
    let text: String
    let normalizedText: String
    let profileName: String
    let textProfileName: String?
    let textContext: TextForSpeech.Context?
    let sourceFormat: TextForSpeech.SourceFormat?
    let textFeatures: SpeechTextForensicFeatures
    let textSections: [SpeechTextForensicSection]
    let stream: AsyncThrowingStream<[Float], any Swift.Error>
    let continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation
    var sampleRate: Double?
    var generationTask: Task<Void, Never>?
    var playbackTask: Task<Void, Never>?

    init(
        requestID: String,
        op: String,
        text: String,
        normalizedText: String,
        profileName: String,
        textProfileName: String?,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?,
        textFeatures: SpeechTextForensicFeatures,
        textSections: [SpeechTextForensicSection],
        stream: AsyncThrowingStream<[Float], any Swift.Error>,
        continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation
    ) {
        self.requestID = requestID
        self.op = op
        self.text = text
        self.normalizedText = normalizedText
        self.profileName = profileName
        self.textProfileName = textProfileName
        self.textContext = textContext
        self.sourceFormat = sourceFormat
        self.textFeatures = textFeatures
        self.textSections = textSections
        self.stream = stream
        self.continuation = continuation
    }
}

struct PlaybackHooks: Sendable {
    let handleEvent: @Sendable (PlaybackEvent, PlaybackJob) async -> Void
    let handleEnvironmentEvent: @Sendable (PlaybackEnvironmentEvent, ActiveWorkerRequestSummary?) async -> Void
    let logFinished: @Sendable (PlaybackJob, PlaybackSummary, Double) async -> Void
    let completeJob: @Sendable (PlaybackJob, Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>) async -> Void
    let resumeQueue: @Sendable () async -> Void
}

actor PlaybackController {
    struct ActivePlayback: Sendable {
        let requestID: String
        let task: Task<Void, Never>
    }

    struct ConcurrencySnapshot: Sendable, Equatable {
        let activeRequestID: String?
        let isStableForConcurrentGeneration: Bool
        let stableBufferedAudioMS: Int?
        let stableBufferTargetMS: Int?
        let isRebuffering: Bool
    }

    private let driver: AnyPlaybackController
    private var hooks: PlaybackHooks?
    private var activePlayback: ActivePlayback?
    private var activePlaybackIsStableForConcurrentGeneration = false
    private var activePlaybackStableBufferedAudioMS: Int?
    private var activePlaybackStableBufferTargetMS: Int?
    private var activePlaybackIsRebuffering = false
    private var jobs = [String: PlaybackJob]()
    private var queue = [String]()

    init(driver: AnyPlaybackController) {
        self.driver = driver
    }

    // MARK: - Binding

    func bind(_ hooks: PlaybackHooks) {
        self.hooks = hooks
        Task {
            await driver.bindEnvironmentEvents { [weak self] (event: PlaybackEnvironmentEvent) in
                guard let self else { return }
                let activeRequest = await self.activeRequestSummary()
                await hooks.handleEnvironmentEvent(event, activeRequest)
            }
        }
    }

    // MARK: - Driver Control

    func prepare(sampleRate: Double) async throws -> Bool {
        try await driver.prepare(sampleRate: sampleRate)
    }

    func handle(_ action: PlaybackAction) async -> PlaybackState {
        switch action {
        case .pause:
            let driverState = await driver.pause()
            return resolvedPlaybackState(driverState: driverState)
        case .resume:
            let driverState = await driver.resume()
            return resolvedPlaybackState(driverState: driverState)
        case .state:
            let driverState = await driver.state()
            return resolvedPlaybackState(driverState: driverState)
        }
    }

    // MARK: - Queue Ownership

    func enqueue(_ job: PlaybackJob) {
        jobs[job.requestID] = job
        queue.append(job.requestID)
    }

    func setGenerationTask(_ task: Task<Void, Never>?, for requestID: String) {
        jobs[requestID]?.generationTask = task
    }

    func job(for requestID: String) -> PlaybackJob? {
        jobs[requestID]
    }

    func jobCount() -> Int {
        jobs.count
    }

    func activeRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let requestID = activePlayback?.requestID, let job = jobs[requestID] else { return nil }
        return ActiveWorkerRequestSummary(id: requestID, op: job.op, profileName: job.profileName)
    }

    func concurrencySnapshot() -> ConcurrencySnapshot {
        ConcurrencySnapshot(
            activeRequestID: activePlayback?.requestID,
            isStableForConcurrentGeneration: activePlaybackIsStableForConcurrentGeneration,
            stableBufferedAudioMS: activePlaybackStableBufferedAudioMS,
            stableBufferTargetMS: activePlaybackStableBufferTargetMS,
            isRebuffering: activePlaybackIsRebuffering
        )
    }

    func hasActivePlayback() -> Bool {
        activePlayback != nil
    }

    func queuedRequestSummaries() -> [QueuedWorkerRequestSummary] {
        let waitingQueue = queue.filter { $0 != activePlayback?.requestID }
        return waitingQueue.enumerated().compactMap { offset, requestID in
            guard let job = jobs[requestID] else { return nil }
            return QueuedWorkerRequestSummary(
                id: requestID,
                op: job.op,
                profileName: job.profileName,
                queuePosition: offset + 1
            )
        }
    }

    func stateSnapshot() async -> SpeakSwiftly.PlaybackStateSnapshot {
        let activeRequest = activeRequestSummary()
        let concurrency = concurrencySnapshot()
        let driverState = await driver.state()
        return SpeakSwiftly.PlaybackStateSnapshot(
            state: resolvedPlaybackState(driverState: driverState, activeRequest: activeRequest),
            activeRequest: activeRequest,
            isStableForConcurrentGeneration: concurrency.isStableForConcurrentGeneration,
            isRebuffering: concurrency.isRebuffering,
            stableBufferedAudioMS: concurrency.stableBufferedAudioMS,
            stableBufferTargetMS: concurrency.stableBufferTargetMS
        )
    }

    private func resolvedPlaybackState(
        driverState: PlaybackState,
        activeRequest: ActiveWorkerRequestSummary? = nil
    ) -> PlaybackState {
        let resolvedActiveRequest = activeRequest ?? activeRequestSummary()
        guard resolvedActiveRequest != nil else {
            return .idle
        }

        if driverState == .paused {
            return .paused
        }

        return .playing
    }

    func clearQueued(excluding protectedRequestIDs: Set<String>) -> [PlaybackJob] {
        let waitingRequestIDs = queue.filter { !protectedRequestIDs.contains($0) }
        let removedJobs = waitingRequestIDs.compactMap { requestID in
            let job = jobs.removeValue(forKey: requestID)
            queue.removeAll { $0 == requestID }
            return job
        }
        return removedJobs
    }

    func cancel(requestID: String) async -> PlaybackJob? {
        guard let job = jobs[requestID] else { return nil }

        job.generationTask?.cancel()
        job.playbackTask?.cancel()
        queue.removeAll { $0 == requestID }
        jobs.removeValue(forKey: requestID)

        if activePlayback?.requestID == requestID {
            activePlayback = nil
            await driver.stop()
        }

        return job
    }

    func discard(requestID: String) -> PlaybackJob? {
        queue.removeAll { $0 == requestID }
        return jobs.removeValue(forKey: requestID)
    }

    func shutdown() async -> [PlaybackJob] {
        let activeTask = activePlayback?.task
        activePlayback = nil
        activeTask?.cancel()

        for job in jobs.values {
            job.generationTask?.cancel()
            job.playbackTask?.cancel()
        }

        let cancelledJobs = Array(jobs.values)
        jobs.removeAll()
        queue.removeAll()
        await driver.stop()
        return cancelledJobs
    }

    // MARK: - Playback Execution

    func startNextIfPossible() async {
        guard activePlayback == nil else { return }
        guard let requestID = queue.first, let job = jobs[requestID] else { return }
        guard let sampleRate = job.sampleRate else { return }
        guard let hooks else { return }

        let task = Task {
            await self.runPlayback(for: job, sampleRate: sampleRate, hooks: hooks)
        }
        activePlayback = ActivePlayback(requestID: requestID, task: task)
        activePlaybackIsStableForConcurrentGeneration = false
        activePlaybackStableBufferedAudioMS = nil
        activePlaybackStableBufferTargetMS = nil
        activePlaybackIsRebuffering = false
        job.playbackTask = task
    }

    private func runPlayback(
        for job: PlaybackJob,
        sampleRate: Double,
        hooks: PlaybackHooks
    ) async {
        let result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>

        do {
            let playbackSummary = try await driver.play(
                sampleRate: sampleRate,
                text: job.normalizedText,
                stream: job.stream
            ) { event in
                await self.recordConcurrencyEvent(event, for: job.requestID)
                await hooks.handleEvent(event, job)
            }
            await hooks.logFinished(job, playbackSummary, sampleRate)
            result = .success(SpeakSwiftly.Runtime.WorkerSuccessPayload(id: job.requestID))
        } catch is CancellationError {
            result = .failure(
                WorkerError(
                    code: .requestCancelled,
                    message: "Request '\(job.requestID)' was cancelled before it could complete."
                )
            )
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Live playback failed for request '\(job.requestID)' due to an unexpected internal error. \(error.localizedDescription)"
                )
            )
        }

        await finishPlayback(requestID: job.requestID, result: result, hooks: hooks)
    }

    private func finishPlayback(
        requestID: String,
        result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>,
        hooks: PlaybackHooks
    ) async {
        guard activePlayback?.requestID == requestID else { return }

        activePlayback = nil
        activePlaybackIsStableForConcurrentGeneration = false
        activePlaybackStableBufferedAudioMS = nil
        activePlaybackStableBufferTargetMS = nil
        activePlaybackIsRebuffering = false
        queue.removeAll { $0 == requestID }

        guard let job = jobs.removeValue(forKey: requestID) else {
            await startNextIfPossible()
            return
        }

        job.generationTask = nil
        job.playbackTask = nil
        await hooks.completeJob(job, result)
        await hooks.resumeQueue()
    }

    private func recordConcurrencyEvent(_ event: PlaybackEvent, for requestID: String) {
        guard activePlayback?.requestID == requestID else { return }

        switch event {
        case .prerollReady(let startupBufferedAudioMS, let thresholds):
            activePlaybackIsStableForConcurrentGeneration = true
            activePlaybackStableBufferedAudioMS = startupBufferedAudioMS
            activePlaybackStableBufferTargetMS = thresholds.startupBufferTargetMS
            activePlaybackIsRebuffering = false
        case .rebufferStarted:
            activePlaybackIsStableForConcurrentGeneration = false
            activePlaybackIsRebuffering = true
        case .rebufferResumed(let bufferedAudioMS, let thresholds):
            activePlaybackIsStableForConcurrentGeneration = true
            activePlaybackStableBufferedAudioMS = bufferedAudioMS
            activePlaybackStableBufferTargetMS = thresholds.resumeBufferTargetMS
            activePlaybackIsRebuffering = false
        case .starved:
            activePlaybackIsStableForConcurrentGeneration = false
            activePlaybackIsRebuffering = true
        case .firstChunk,
             .queueDepthLow,
             .chunkGapWarning,
             .scheduleGapWarning,
             .rebufferThrashWarning,
             .outputDeviceChanged,
             .engineConfigurationChanged,
             .bufferShapeSummary,
             .trace:
            break
        }
    }
}
