import Foundation

// MARK: - Request Observation

extension SpeakSwiftly.Runtime {
    func makeRequestHandle(for request: WorkerRequest) -> WorkerRequestHandle {
        WorkerRequestHandle(
            id: request.id,
            kind: request.requestKind,
            voiceProfile: request.voiceProfile,
            requestContext: request.requestContext,
            events: makeLegacyRequestEventStream(for: request.id),
            synthesisUpdates: makeSynthesisUpdateStream(for: request.id),
        )
    }

    func ensureRequestBroker(for request: WorkerRequest) {
        if requestBrokers[request.id]?.isTerminal == true {
            terminalRequestBrokerOrder.removeAll { $0 == request.id }
            requestBrokers.removeValue(forKey: request.id)
        }
        guard requestBrokers[request.id] == nil else { return }

        let acceptedAt = dependencies.now()
        requestBrokers[request.id] = RequestBroker(
            id: request.id,
            kind: request.requestKind,
            voiceProfile: request.voiceProfile,
            requestContext: request.requestContext,
            acceptedAt: acceptedAt,
            lastUpdatedAt: acceptedAt,
        )
    }

    func requestSnapshot(for requestID: String) -> SpeakSwiftly.RequestSnapshot? {
        requestBrokers[requestID]?.snapshot()
    }

    func makeRequestUpdateStream(
        for requestID: String,
        replayBuffered: Bool = true,
    ) -> AsyncThrowingStream<SpeakSwiftly.RequestUpdate, any Swift.Error> {
        guard let broker = requestBrokers[requestID] else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        let subscriberID = UUID()
        let replayUpdates = replayBuffered ? broker.replayUpdates : []
        let isTerminal = broker.isTerminal

        return AsyncThrowingStream { continuation in
            replayUpdates.forEach { continuation.yield($0) }

            guard !isTerminal, requestBrokers[requestID] != nil else {
                continuation.finish()
                return
            }

            requestBrokers[requestID]?.subscriberContinuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeRequestUpdateSubscriber(subscriberID, for: requestID)
                }
            }
        }
    }

    func makeSynthesisUpdateStream(
        for requestID: String,
        replayBuffered: Bool = true,
    ) -> AsyncThrowingStream<SpeakSwiftly.SynthesisUpdate, any Swift.Error> {
        guard let broker = requestBrokers[requestID] else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        let subscriberID = UUID()
        let replayEvents = replayBuffered ? broker.replaySynthesisUpdates : []
        let isTerminal = broker.isTerminal

        return AsyncThrowingStream { continuation in
            replayEvents.forEach { continuation.yield($0) }

            guard !isTerminal, requestBrokers[requestID] != nil else {
                continuation.finish()
                return
            }

            requestBrokers[requestID]?.synthesisContinuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeSynthesisUpdateSubscriber(subscriberID, for: requestID)
                }
            }
        }
    }

    func makeLegacyRequestEventStream(
        for requestID: String,
    ) -> AsyncThrowingStream<WorkerRequestStreamEvent, any Swift.Error> {
        let updates = makeRequestUpdateStream(for: requestID, replayBuffered: false)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in updates {
                        switch update.state {
                            case let .queued(event):
                                continuation.yield(.queued(event))
                            case let .acknowledged(success):
                                continuation.yield(.acknowledged(success))
                            case let .started(event):
                                continuation.yield(.started(event))
                            case let .progress(event):
                                continuation.yield(.progress(event))
                            case let .completed(completion):
                                continuation.yield(.completed(completion))
                            case let .failed(failure), let .cancelled(failure):
                                continuation.finish(
                                    throwing: WorkerError(code: failure.code, message: failure.message),
                                )
                                return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func yieldRequestEvent(_ event: WorkerRequestStreamEvent, for requestID: String) async {
        let state: SpeakSwiftly.RequestState = switch event {
            case let .queued(queuedEvent):
                .queued(queuedEvent)
            case let .acknowledged(success):
                .acknowledged(success)
            case let .started(startedEvent):
                .started(startedEvent)
            case let .progress(progressEvent):
                .progress(progressEvent)
            case let .completed(completion):
                .completed(completion)
        }

        await recordRequestState(
            state,
            for: requestID,
            terminal: {
                if case .completed = state { return true }
                return false
            }(),
        )
    }

    func recordSynthesisEvent(
        _ event: SpeakSwiftly.SynthesisEvent,
        for requestID: String,
    ) {
        guard var broker = requestBrokers[requestID] else { return }

        let update = broker.recordSynthesisEvent(
            event,
            date: dependencies.now(),
            maxReplayUpdates: RequestObservationConfiguration.maxReplayUpdates,
        )
        let continuations = Array(broker.synthesisContinuations.values)
        requestBrokers[requestID] = broker

        continuations.forEach { continuation in
            continuation.yield(update)
        }
    }

    func failRequestStream(for requestID: String, error: WorkerError) async {
        let failure = WorkerFailureResponse(
            id: requestID,
            code: error.code,
            message: error.message,
        )
        let state: SpeakSwiftly.RequestState =
            error.code == .requestCancelled ? .cancelled(failure) : .failed(failure)
        await recordRequestState(state, for: requestID, terminal: true)
    }

    func recordRequestState(
        _ state: SpeakSwiftly.RequestState,
        for requestID: String,
        terminal: Bool,
    ) async {
        guard var broker = requestBrokers[requestID] else { return }

        let update = broker.recordState(
            state: state,
            date: dependencies.now(),
            maxReplayUpdates: RequestObservationConfiguration.maxReplayUpdates,
        )
        let continuations = Array(broker.subscriberContinuations.values)
        let synthesisContinuations = Array(broker.synthesisContinuations.values)

        if terminal {
            broker.isTerminal = true
            broker.subscriberContinuations.removeAll()
            broker.synthesisContinuations.removeAll()
        }

        requestBrokers[requestID] = broker

        continuations.forEach { continuation in
            continuation.yield(update)
            if terminal {
                continuation.finish()
            }
        }

        if terminal {
            synthesisContinuations.forEach { continuation in
                continuation.finish()
            }
        }

        if terminal {
            retainTerminalRequestBrokerIfNeeded(for: requestID)
        }
    }

    func retainTerminalRequestBrokerIfNeeded(for requestID: String) {
        guard requestBrokers[requestID]?.isTerminal == true else { return }

        terminalRequestBrokerOrder.removeAll { $0 == requestID }
        terminalRequestBrokerOrder.append(requestID)

        while terminalRequestBrokerOrder.count > RequestObservationConfiguration.maxRetainedTerminalRequests {
            let evictedRequestID = terminalRequestBrokerOrder.removeFirst()
            requestBrokers.removeValue(forKey: evictedRequestID)
        }
    }

    func removeRequestUpdateSubscriber(_ subscriberID: UUID, for requestID: String) {
        requestBrokers[requestID]?.subscriberContinuations.removeValue(forKey: subscriberID)
    }

    func removeSynthesisUpdateSubscriber(_ subscriberID: UUID, for requestID: String) {
        requestBrokers[requestID]?.synthesisContinuations.removeValue(forKey: subscriberID)
    }

    func generateUpdates() async -> AsyncStream<SpeakSwiftly.GenerateUpdate> {
        let subscriptionID = UUID()
        let snapshot = await generateSnapshot()
        let latestUpdate = if let latestGenerateUpdate = generateObservationBroker.latestUpdate {
            latestGenerateUpdate
        } else {
            makeGenerateUpdate(state: snapshot.state, advanceSequence: false)
        }

        return AsyncStream { continuation in
            generateObservationBroker.subscribe(id: subscriptionID, continuation: continuation)
            continuation.yield(latestUpdate)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeGenerateUpdateContinuation(subscriptionID)
                }
            }
        }
    }

    func playbackUpdates() async -> AsyncStream<SpeakSwiftly.PlaybackUpdate> {
        let subscriptionID = UUID()
        let snapshot = await playbackSnapshot()
        let latestUpdate = if let latestPlaybackUpdate = playbackObservationBroker.latestUpdate {
            latestPlaybackUpdate
        } else {
            makePlaybackUpdate(state: snapshot.state, advanceSequence: false)
        }

        return AsyncStream { continuation in
            playbackObservationBroker.subscribe(id: subscriptionID, continuation: continuation)
            continuation.yield(latestUpdate)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removePlaybackUpdateContinuation(subscriptionID)
                }
            }
        }
    }

    func publishGenerateUpdate() async {
        let update = await makeGenerateUpdate(state: generateSnapshot().state)
        generateObservationBroker.broadcast(update)
    }

    func publishPlaybackUpdate() async {
        let update = await makePlaybackUpdate(state: playbackSnapshot().state)
        playbackObservationBroker.broadcast(update)
    }

    func makeGenerateUpdate(
        state: SpeakSwiftly.GenerateState,
        advanceSequence: Bool = true,
    ) -> SpeakSwiftly.GenerateUpdate {
        generateObservationBroker.makeUpdate(advanceSequence: advanceSequence) { sequence in
            SpeakSwiftly.GenerateUpdate(
                sequence: sequence,
                date: dependencies.now(),
                state: state,
                event: .stateChanged(state),
            )
        }
    }

    func makePlaybackUpdate(
        state: SpeakSwiftly.PlaybackState,
        advanceSequence: Bool = true,
    ) -> SpeakSwiftly.PlaybackUpdate {
        playbackObservationBroker.makeUpdate(advanceSequence: advanceSequence) { sequence in
            SpeakSwiftly.PlaybackUpdate(
                sequence: sequence,
                date: dependencies.now(),
                state: state,
                event: .stateChanged(state),
            )
        }
    }

    func removeGenerateUpdateContinuation(_ id: UUID) {
        generateObservationBroker.removeSubscriber(id: id)
    }

    func removePlaybackUpdateContinuation(_ id: UUID) {
        playbackObservationBroker.removeSubscriber(id: id)
    }

    func broadcastRuntimeUpdate(_ update: SpeakSwiftly.RuntimeUpdate) {
        runtimeObservationBroker.broadcast(update)
    }

    func currentStatusSnapshot() -> WorkerStatusEvent? {
        switch residentState {
            case .warming:
                guard preloadTask != nil else { return nil }

                return WorkerStatusEvent(
                    stage: .warmingResidentModel,
                    residentState: residentStateSummary,
                    speechBackend: speechBackend,
                )
            case .ready:
                return WorkerStatusEvent(
                    stage: .residentModelReady,
                    residentState: residentStateSummary,
                    speechBackend: speechBackend,
                )
            case .unloaded:
                return WorkerStatusEvent(
                    stage: .residentModelsUnloaded,
                    residentState: residentStateSummary,
                    speechBackend: speechBackend,
                )
            case .failed:
                return WorkerStatusEvent(
                    stage: .residentModelFailed,
                    residentState: residentStateSummary,
                    speechBackend: speechBackend,
                )
        }
    }

    var residentStateSummary: SpeakSwiftly.ResidentModelState {
        switch residentState {
            case .warming:
                .warming
            case .ready:
                .ready
            case .unloaded:
                .unloaded
            case .failed:
                .failed
        }
    }

    func removeStatusContinuation(_ id: UUID) {
        runtimeObservationBroker.removeSubscriber(id: id)
    }
}
