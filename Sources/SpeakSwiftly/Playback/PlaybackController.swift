import Foundation

struct PlaybackHooks {
    let handleEvent: @Sendable (PlaybackEvent, LiveSpeechRequestState) async -> Void
    let handleEnvironmentEvent: @Sendable (PlaybackEnvironmentEvent, ActiveWorkerRequestSummary?) async -> Void
    let logEngineReady: @Sendable (LiveSpeechRequestState, Double) async -> Void
    let logFinished: @Sendable (LiveSpeechRequestState, PlaybackSummary, Double) async -> Void
    let completeJob: @Sendable (LiveSpeechRequestState, Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>) async -> Void
    let resumeQueue: @Sendable () async -> Void
}

actor PlaybackController {
    struct ConcurrencyAdmissionThresholds {
        let startupBufferTargetMS: Int
        let concurrentGenerationTargetMS: Int
    }

    struct FragileOverlapWindowConfiguration: Equatable {
        let holdBufferTargetMS: Int
        let requiredStableBufferEventCount: Int
    }

    struct FragileOverlapWindowProgress: Equatable {
        let configuration: FragileOverlapWindowConfiguration
        var stableBufferEventCount: Int
        var hasSatisfiedHold: Bool
    }

    struct ConcurrencyAdmissionResolution: Equatable {
        let allowsConcurrentGeneration: Bool
        let effectiveTargetMS: Int
        let fragileOverlapWindowProgress: FragileOverlapWindowProgress?
    }

    struct ActivePlayback {
        let requestID: String
        let task: Task<Void, Never>
    }

    struct ConcurrencySnapshot: Equatable {
        let activeRequestID: String?
        let isStableForConcurrentGeneration: Bool
        let stableBufferedAudioMS: Int?
        let stableBufferTargetMS: Int?
        let isRebuffering: Bool
    }

    struct GenerationAdmissionSnapshot: Equatable {
        let activeRequestID: String?
        let allowsConcurrentGeneration: Bool
    }

    private let driver: AnyPlaybackController
    private var hooks: PlaybackHooks?
    private var activePlayback: ActivePlayback?
    private var activePlaybackIsStableForConcurrentGeneration = false
    private var activePlaybackStableBufferedAudioMS: Int?
    private var activePlaybackStableBufferTargetMS: Int?
    private var activePlaybackConcurrentGenerationTargetMS: Int?
    private var activePlaybackFragileOverlapWindowProgress: FragileOverlapWindowProgress?
    private var activePlaybackIsRebuffering = false
    private var jobs = [String: LiveSpeechPlaybackState]()
    private var queue = [String]()

    init(driver: AnyPlaybackController) {
        self.driver = driver
    }

    static func concurrencyAdmissionThresholds(
        tuningProfile: PlaybackTuningProfile,
        startupBufferTargetMS: Int,
        lowWaterTargetMS: Int,
    ) -> ConcurrencyAdmissionThresholds {
        guard tuningProfile == .firstDrainedLiveMarvis else {
            return ConcurrencyAdmissionThresholds(
                startupBufferTargetMS: startupBufferTargetMS,
                concurrentGenerationTargetMS: startupBufferTargetMS,
            )
        }

        let additionalReserveMS = min(960, max(720, lowWaterTargetMS / 2))
        return ConcurrencyAdmissionThresholds(
            startupBufferTargetMS: startupBufferTargetMS,
            concurrentGenerationTargetMS: startupBufferTargetMS + additionalReserveMS,
        )
    }

    static func allowsConcurrentGeneration(
        bufferedAudioMS: Int,
        targetMS: Int,
    ) -> Bool {
        bufferedAudioMS >= targetMS
    }

    static func fragileOverlapWindowConfiguration(
        tuningProfile: PlaybackTuningProfile,
        concurrentGenerationTargetMS: Int,
        lowWaterTargetMS: Int,
    ) -> FragileOverlapWindowConfiguration? {
        guard tuningProfile == .firstDrainedLiveMarvis else { return nil }

        let additionalHoldReserveMS = min(640, max(480, lowWaterTargetMS / 2))
        return FragileOverlapWindowConfiguration(
            holdBufferTargetMS: concurrentGenerationTargetMS + additionalHoldReserveMS,
            requiredStableBufferEventCount: 2,
        )
    }

    static func resolveConcurrentGenerationAdmission(
        bufferedAudioMS: Int,
        concurrentGenerationTargetMS: Int,
        fragileOverlapWindowProgress: FragileOverlapWindowProgress?,
    ) -> ConcurrencyAdmissionResolution {
        guard var fragileOverlapWindowProgress else {
            return ConcurrencyAdmissionResolution(
                allowsConcurrentGeneration: allowsConcurrentGeneration(
                    bufferedAudioMS: bufferedAudioMS,
                    targetMS: concurrentGenerationTargetMS,
                ),
                effectiveTargetMS: concurrentGenerationTargetMS,
                fragileOverlapWindowProgress: nil,
            )
        }

        let fragileTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS

        if fragileOverlapWindowProgress.hasSatisfiedHold {
            if bufferedAudioMS < fragileTargetMS {
                fragileOverlapWindowProgress.hasSatisfiedHold = false
                fragileOverlapWindowProgress.stableBufferEventCount = 0
                return ConcurrencyAdmissionResolution(
                    allowsConcurrentGeneration: false,
                    effectiveTargetMS: fragileTargetMS,
                    fragileOverlapWindowProgress: fragileOverlapWindowProgress,
                )
            }

            return ConcurrencyAdmissionResolution(
                allowsConcurrentGeneration: true,
                effectiveTargetMS: concurrentGenerationTargetMS,
                fragileOverlapWindowProgress: fragileOverlapWindowProgress,
            )
        }

        if bufferedAudioMS >= fragileTargetMS {
            fragileOverlapWindowProgress.stableBufferEventCount += 1
        } else {
            fragileOverlapWindowProgress.stableBufferEventCount = 0
        }

        if fragileOverlapWindowProgress.stableBufferEventCount >= fragileOverlapWindowProgress.configuration.requiredStableBufferEventCount {
            fragileOverlapWindowProgress.hasSatisfiedHold = true
            return ConcurrencyAdmissionResolution(
                allowsConcurrentGeneration: true,
                effectiveTargetMS: concurrentGenerationTargetMS,
                fragileOverlapWindowProgress: fragileOverlapWindowProgress,
            )
        }

        return ConcurrencyAdmissionResolution(
            allowsConcurrentGeneration: false,
            effectiveTargetMS: fragileTargetMS,
            fragileOverlapWindowProgress: fragileOverlapWindowProgress,
        )
    }

    // MARK: - Binding

    func bind(_ hooks: PlaybackHooks) {
        self.hooks = hooks
        Task {
            await driver.bindEnvironmentEvents { [weak self] (event: PlaybackEnvironmentEvent) in
                guard let self else { return }

                let activeRequest = await activeRequestSummary()
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

    func enqueue(_ request: LiveSpeechRequestState) {
        let playbackState = LiveSpeechPlaybackState(
            request: request,
            execution: .make(requestID: request.id),
        )
        jobs[playbackState.id] = playbackState
        queue.append(playbackState.id)
    }

    func setGenerationTask(_ task: Task<Void, Never>?, for requestID: String) {
        jobs[requestID]?.execution.generationTask = task
    }

    func playbackState(for requestID: String) -> LiveSpeechPlaybackState? {
        jobs[requestID]
    }

    func jobCount() -> Int {
        jobs.count
    }

    func activeRequestSummary() -> ActiveWorkerRequestSummary? {
        guard let requestID = activePlayback?.requestID, let playbackState = jobs[requestID] else { return nil }

        return ActiveWorkerRequestSummary(
            id: requestID,
            op: playbackState.request.op,
            profileName: playbackState.request.profileName,
        )
    }

    func coordinationTelemetrySnapshot() -> ConcurrencySnapshot {
        ConcurrencySnapshot(
            activeRequestID: activePlayback?.requestID,
            isStableForConcurrentGeneration: activePlaybackIsStableForConcurrentGeneration,
            stableBufferedAudioMS: activePlaybackStableBufferedAudioMS,
            stableBufferTargetMS: activePlaybackStableBufferTargetMS,
            isRebuffering: activePlaybackIsRebuffering,
        )
    }

    func generationAdmissionSnapshot() -> GenerationAdmissionSnapshot {
        GenerationAdmissionSnapshot(
            activeRequestID: activePlayback?.requestID,
            allowsConcurrentGeneration: activePlayback == nil || activePlaybackIsStableForConcurrentGeneration,
        )
    }

    func hasActivePlayback() -> Bool {
        activePlayback != nil
    }

    func queuedRequestSummaries() -> [QueuedWorkerRequestSummary] {
        let waitingQueue = queue.filter { $0 != activePlayback?.requestID }
        return waitingQueue.enumerated().compactMap { offset, requestID in
            guard let playbackState = jobs[requestID] else { return nil }

            return QueuedWorkerRequestSummary(
                id: requestID,
                op: playbackState.request.op,
                profileName: playbackState.request.profileName,
                queuePosition: offset + 1,
            )
        }
    }

    func stateSnapshot() async -> SpeakSwiftly.PlaybackStateSnapshot {
        let activeRequest = activeRequestSummary()
        let telemetry = coordinationTelemetrySnapshot()
        let driverState = await driver.state()
        return SpeakSwiftly.PlaybackStateSnapshot(
            state: resolvedPlaybackState(driverState: driverState, activeRequest: activeRequest),
            activeRequest: activeRequest,
            isStableForConcurrentGeneration: telemetry.isStableForConcurrentGeneration,
            isRebuffering: telemetry.isRebuffering,
            stableBufferedAudioMS: telemetry.stableBufferedAudioMS,
            stableBufferTargetMS: telemetry.stableBufferTargetMS,
        )
    }

    func clearQueued(excluding protectedRequestIDs: Set<String>) -> [LiveSpeechPlaybackState] {
        let waitingRequestIDs = queue.filter { !protectedRequestIDs.contains($0) }
        return waitingRequestIDs.compactMap { requestID in
            let playbackState = jobs.removeValue(forKey: requestID)
            queue.removeAll { $0 == requestID }
            return playbackState
        }
    }

    func cancel(requestID: String) async -> LiveSpeechPlaybackState? {
        guard let playbackState = jobs[requestID] else { return nil }

        playbackState.execution.generationTask?.cancel()
        playbackState.execution.playbackTask?.cancel()
        queue.removeAll { $0 == requestID }
        jobs.removeValue(forKey: requestID)

        if activePlayback?.requestID == requestID {
            activePlayback = nil
            await driver.stop()
        }

        return playbackState
    }

    func discard(requestID: String) -> LiveSpeechPlaybackState? {
        queue.removeAll { $0 == requestID }
        return jobs.removeValue(forKey: requestID)
    }

    func shutdown() async -> [LiveSpeechPlaybackState] {
        let activeTask = activePlayback?.task
        activePlayback = nil
        activeTask?.cancel()

        for playbackState in jobs.values {
            playbackState.execution.generationTask?.cancel()
            playbackState.execution.playbackTask?.cancel()
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
        guard let requestID = queue.first, let playbackState = jobs[requestID] else { return }
        guard let sampleRate = playbackState.execution.sampleRate else { return }
        guard let hooks else { return }

        let task = Task {
            await self.runPlayback(for: playbackState, sampleRate: sampleRate, hooks: hooks)
        }
        activePlayback = ActivePlayback(requestID: requestID, task: task)
        activePlaybackIsStableForConcurrentGeneration = false
        activePlaybackStableBufferedAudioMS = nil
        activePlaybackStableBufferTargetMS = nil
        activePlaybackConcurrentGenerationTargetMS = nil
        activePlaybackFragileOverlapWindowProgress = nil
        activePlaybackIsRebuffering = false
        playbackState.execution.playbackTask = task
    }

    private func resolvedPlaybackState(
        driverState: PlaybackState,
        activeRequest: ActiveWorkerRequestSummary? = nil,
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

    private func runPlayback(
        for playbackState: LiveSpeechPlaybackState,
        sampleRate: Double,
        hooks: PlaybackHooks,
    ) async {
        let result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>

        do {
            let playbackEngineWasPrepared = try await driver.prepare(sampleRate: sampleRate)
            if playbackEngineWasPrepared {
                await hooks.logEngineReady(playbackState.request, sampleRate)
            }
            let playbackSummary = try await driver.play(
                sampleRate: sampleRate,
                text: playbackState.request.normalizedText,
                tuningProfile: playbackState.request.playbackTuningProfile,
                stream: playbackState.execution.stream,
            ) { event in
                await self.recordConcurrencyEvent(event, for: playbackState.id)
                await hooks.handleEvent(event, playbackState.request)
            }
            await hooks.logFinished(playbackState.request, playbackSummary, sampleRate)
            result = .success(SpeakSwiftly.Runtime.WorkerSuccessPayload(id: playbackState.id))
        } catch is CancellationError {
            result = .failure(
                WorkerError(
                    code: .requestCancelled,
                    message: "Request '\(playbackState.id)' was cancelled before it could complete.",
                ),
            )
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .audioPlaybackFailed,
                    message: "Live playback failed for request '\(playbackState.id)' due to an unexpected internal error. \(error.localizedDescription)",
                ),
            )
        }

        await finishPlayback(requestID: playbackState.id, result: result, hooks: hooks)
    }

    private func finishPlayback(
        requestID: String,
        result: Result<SpeakSwiftly.Runtime.WorkerSuccessPayload, WorkerError>,
        hooks: PlaybackHooks,
    ) async {
        guard activePlayback?.requestID == requestID else { return }

        activePlayback = nil
        activePlaybackIsStableForConcurrentGeneration = false
        activePlaybackStableBufferedAudioMS = nil
        activePlaybackStableBufferTargetMS = nil
        activePlaybackConcurrentGenerationTargetMS = nil
        activePlaybackFragileOverlapWindowProgress = nil
        activePlaybackIsRebuffering = false
        queue.removeAll { $0 == requestID }

        guard let playbackState = jobs.removeValue(forKey: requestID) else {
            await startNextIfPossible()
            return
        }

        playbackState.execution.generationTask = nil
        playbackState.execution.playbackTask = nil
        await hooks.completeJob(playbackState.request, result)
        await hooks.resumeQueue()
    }

    private func recordConcurrencyEvent(_ event: PlaybackEvent, for requestID: String) {
        guard activePlayback?.requestID == requestID else { return }

        switch event {
            case let .prerollReady(startupBufferedAudioMS, thresholds):
                let requestTuningProfile = jobs[requestID]?.request.playbackTuningProfile ?? .standard
                let admissionThresholds = Self.concurrencyAdmissionThresholds(
                    tuningProfile: requestTuningProfile,
                    startupBufferTargetMS: thresholds.startupBufferTargetMS,
                    lowWaterTargetMS: thresholds.lowWaterTargetMS,
                )
                activePlaybackConcurrentGenerationTargetMS = admissionThresholds.concurrentGenerationTargetMS
                if let fragileOverlapWindowConfiguration = Self.fragileOverlapWindowConfiguration(
                    tuningProfile: requestTuningProfile,
                    concurrentGenerationTargetMS: admissionThresholds.concurrentGenerationTargetMS,
                    lowWaterTargetMS: thresholds.lowWaterTargetMS,
                ) {
                    activePlaybackFragileOverlapWindowProgress = FragileOverlapWindowProgress(
                        configuration: fragileOverlapWindowConfiguration,
                        stableBufferEventCount: 0,
                        hasSatisfiedHold: false,
                    )
                } else {
                    activePlaybackFragileOverlapWindowProgress = nil
                }
                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: startupBufferedAudioMS,
                    concurrentGenerationTargetMS: admissionThresholds.concurrentGenerationTargetMS,
                )
                activePlaybackIsRebuffering = false
            case .rebufferStarted:
                activePlaybackIsStableForConcurrentGeneration = false
                if var fragileOverlapWindowProgress = activePlaybackFragileOverlapWindowProgress {
                    fragileOverlapWindowProgress.hasSatisfiedHold = false
                    fragileOverlapWindowProgress.stableBufferEventCount = 0
                    activePlaybackFragileOverlapWindowProgress = fragileOverlapWindowProgress
                    activePlaybackStableBufferTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS
                }
                activePlaybackIsRebuffering = true
            case let .rebufferResumed(bufferedAudioMS, thresholds):
                activePlaybackConcurrentGenerationTargetMS = thresholds.resumeBufferTargetMS
                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: bufferedAudioMS,
                    concurrentGenerationTargetMS: thresholds.resumeBufferTargetMS,
                )
                activePlaybackIsRebuffering = false
            case .starved:
                activePlaybackIsStableForConcurrentGeneration = false
                if var fragileOverlapWindowProgress = activePlaybackFragileOverlapWindowProgress {
                    fragileOverlapWindowProgress.hasSatisfiedHold = false
                    fragileOverlapWindowProgress.stableBufferEventCount = 0
                    activePlaybackFragileOverlapWindowProgress = fragileOverlapWindowProgress
                    activePlaybackStableBufferTargetMS = fragileOverlapWindowProgress.configuration.holdBufferTargetMS
                }
                activePlaybackIsRebuffering = true
            case let .trace(trace):
                guard
                    trace.name == "buffer_scheduled",
                    !activePlaybackIsStableForConcurrentGeneration,
                    !activePlaybackIsRebuffering,
                    let queuedAudioAfterMS = trace.queuedAudioAfterMS,
                    let concurrentGenerationTargetMS = activePlaybackConcurrentGenerationTargetMS
                else {
                    if
                        trace.name == "buffer_scheduled",
                        !activePlaybackIsRebuffering,
                        let queuedAudioAfterMS = trace.queuedAudioAfterMS,
                        let concurrentGenerationTargetMS = activePlaybackConcurrentGenerationTargetMS {
                        applyConcurrentGenerationAdmission(
                            bufferedAudioMS: queuedAudioAfterMS,
                            concurrentGenerationTargetMS: concurrentGenerationTargetMS,
                        )
                    }
                    break
                }

                applyConcurrentGenerationAdmission(
                    bufferedAudioMS: queuedAudioAfterMS,
                    concurrentGenerationTargetMS: concurrentGenerationTargetMS,
                )
            case .firstChunk,
                 .queueDepthLow,
                 .chunkGapWarning,
                 .scheduleGapWarning,
                 .rebufferThrashWarning,
                 .outputDeviceChanged,
                 .engineConfigurationChanged,
                 .bufferShapeSummary:
                break
        }
    }

    private func applyConcurrentGenerationAdmission(
        bufferedAudioMS: Int,
        concurrentGenerationTargetMS: Int,
    ) {
        let resolution = Self.resolveConcurrentGenerationAdmission(
            bufferedAudioMS: bufferedAudioMS,
            concurrentGenerationTargetMS: concurrentGenerationTargetMS,
            fragileOverlapWindowProgress: activePlaybackFragileOverlapWindowProgress,
        )
        activePlaybackStableBufferedAudioMS = bufferedAudioMS
        activePlaybackStableBufferTargetMS = resolution.effectiveTargetMS
        activePlaybackIsStableForConcurrentGeneration = resolution.allowsConcurrentGeneration
        activePlaybackFragileOverlapWindowProgress = resolution.fragileOverlapWindowProgress
    }
}
