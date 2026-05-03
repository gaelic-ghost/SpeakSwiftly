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
            generationEvents: makeGenerationEventStream(for: request.id),
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

    func makeGenerationEventStream(
        for requestID: String,
        replayBuffered: Bool = true,
    ) -> AsyncThrowingStream<SpeakSwiftly.GenerationEventUpdate, any Swift.Error> {
        guard let broker = requestBrokers[requestID] else {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        let subscriberID = UUID()
        let replayEvents = replayBuffered ? broker.replayGenerationEvents : []
        let isTerminal = broker.isTerminal

        return AsyncThrowingStream { continuation in
            replayEvents.forEach { continuation.yield($0) }

            guard !isTerminal, requestBrokers[requestID] != nil else {
                continuation.finish()
                return
            }

            requestBrokers[requestID]?.generationContinuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeGenerationEventSubscriber(subscriberID, for: requestID)
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

    func yieldRequestEvent(_ event: WorkerRequestStreamEvent, for requestID: String) {
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

        recordRequestState(
            state,
            for: requestID,
            terminal: {
                if case .completed = state { return true }
                return false
            }(),
        )
    }

    func recordGenerationEvent(
        _ event: SpeakSwiftly.GenerationEvent,
        for requestID: String,
    ) {
        guard var broker = requestBrokers[requestID] else { return }

        let update = broker.recordGenerationEvent(
            event,
            date: dependencies.now(),
            maxReplayUpdates: RequestObservationConfiguration.maxReplayUpdates,
        )
        let continuations = Array(broker.generationContinuations.values)
        requestBrokers[requestID] = broker

        continuations.forEach { continuation in
            continuation.yield(update)
        }
    }

    func failRequestStream(for requestID: String, error: WorkerError) {
        let failure = WorkerFailureResponse(
            id: requestID,
            code: error.code,
            message: error.message,
        )
        let state: SpeakSwiftly.RequestState =
            error.code == .requestCancelled ? .cancelled(failure) : .failed(failure)
        recordRequestState(state, for: requestID, terminal: true)
    }

    func recordRequestState(
        _ state: SpeakSwiftly.RequestState,
        for requestID: String,
        terminal: Bool,
    ) {
        guard var broker = requestBrokers[requestID] else { return }

        let update = broker.recordState(
            state: state,
            date: dependencies.now(),
            maxReplayUpdates: RequestObservationConfiguration.maxReplayUpdates,
        )
        let continuations = Array(broker.subscriberContinuations.values)
        let generationContinuations = Array(broker.generationContinuations.values)

        if terminal {
            broker.isTerminal = true
            broker.subscriberContinuations.removeAll()
            broker.generationContinuations.removeAll()
        }

        requestBrokers[requestID] = broker

        continuations.forEach { continuation in
            continuation.yield(update)
            if terminal {
                continuation.finish()
            }
        }

        if terminal {
            generationContinuations.forEach { continuation in
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

    func removeGenerationEventSubscriber(_ subscriberID: UUID, for requestID: String) {
        requestBrokers[requestID]?.generationContinuations.removeValue(forKey: subscriberID)
    }

    func broadcastStatus(_ status: WorkerStatusEvent) {
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
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
        statusContinuations.removeValue(forKey: id)
    }
}
