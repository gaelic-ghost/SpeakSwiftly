import Foundation

// MARK: - Worker Runtime Scheduling

extension SpeakSwiftly.Runtime {
    // MARK: - Processing

    func startNextGenerationIfPossible() async throws {
        guard !isShuttingDown else { return }

        let activeJobs = await generationController.activeJobsOrdered()
        let queuedJobs = await generationController.queuedJobsOrdered()
        let preparingJobTokens = await generationController.preparingJobTokens()
        let playbackAdmission = await playbackController.generationAdmissionSnapshot()
        let playbackTelemetry = await playbackController.coordinationTelemetrySnapshot()
        let decision = try evaluateGenerationSchedule(
            activeJobs: activeJobs,
            queuedJobs: queuedJobs,
            preparingJobTokens: preparingJobTokens,
            playbackAdmission: playbackAdmission,
        )

        await logMarvisSchedulerSnapshotIfNeeded(
            activeJobs: activeJobs,
            queuedJobs: queuedJobs,
            runnableJobs: decision.runnableJobs,
            parkReasons: decision.parkReasons,
            playbackTelemetry: playbackTelemetry,
        )
        await syncQueuedGenerationParkReasons(
            queuedJobs: queuedJobs,
            parkReasons: decision.parkReasons,
        )

        guard !decision.runnableJobs.isEmpty else { return }

        let jobs = await generationController.reserveQueuedJobs(tokens: decision.runnableJobs.map { $0.token })

        for job in jobs {
            lastQueuedGenerationParkReason.removeValue(forKey: job.request.id)
            try? markGenerationJobRunningIfNeeded(for: job.request)

            await emitStarted(for: job.request)
            yieldRequestEvent(.started(WorkerStartedEvent(id: job.request.id, op: job.request.opName)), for: job.request.id)

            var details = [String: LogValue]()
            if let marvisLane = try marvisGenerationLane(for: job.request) {
                details["marvis_lane"] = .string(marvisLane.rawValue)
            }
            await logRequestEvent(
                "request_started",
                requestID: job.request.id,
                op: job.request.opName,
                profileName: job.request.voiceProfile,
                queueDepth: generationQueueDepth(),
                details: details,
            )

            let task = Task {
                await self.processGeneration(job.request, token: job.token)
            }
            activeGenerations[job.token] = ActiveRequest(token: job.token, request: job.request, task: task)
            if case .queueSpeech(id: let id, text: _, profileName: _, textProfileID: _, jobType: .live, inputTextContext: _, requestContext: _, qwenPreModelTextChunking: _) = job.request {
                await playbackController.setGenerationTask(task, for: id)
            }
            await logMarvisGenerationLaneReservedIfNeeded(
                for: job.request,
                activeJobs: generationController.activeJobsOrdered(),
                playbackAdmission: playbackAdmission,
            )
        }
    }

    func evaluateGenerationSchedule(
        activeJobs: [SpeechGenerationController.Job],
        queuedJobs: [SpeechGenerationController.Job],
        preparingJobTokens: Set<UUID> = [],
        playbackAdmission: PlaybackController.GenerationAdmissionSnapshot,
    ) throws -> GenerationScheduleDecision {
        guard !queuedJobs.isEmpty else {
            return GenerationScheduleDecision(runnableJobs: [], parkReasons: [:])
        }

        var runnableJobs = [SpeechGenerationController.Job]()
        var parkReasons = [UUID: GenerationParkReason]()
        var sawParkedResidentDependentWork = false
        var selectedJobs = [SpeechGenerationController.Job]()

        for job in queuedJobs where !isBlockedByProfileCreation(job, activeJobs: activeJobs, queuedJobs: queuedJobs) {
            if preparingJobTokens.contains(job.token) {
                parkReasons[job.token] = .waitingForActiveRequest
                break
            }

            if sawParkedResidentDependentWork, !job.request.canBypassParkedResidentWork {
                break
            }

            let disposition = try generationDisposition(
                for: job,
                activeJobs: activeJobs + selectedJobs,
                playbackAdmission: playbackAdmission,
            )
            if job.request.formsOrderedControlBarrier, disposition != .run {
                break
            }

            switch disposition {
                case .run:
                    runnableJobs.append(job)
                    selectedJobs.append(job)
                case .skip:
                    continue
                case let .park(reason):
                    parkReasons[job.token] = reason
                    if job.request.requiresResidentModels {
                        sawParkedResidentDependentWork = true
                    }
            }
        }

        return GenerationScheduleDecision(runnableJobs: runnableJobs, parkReasons: parkReasons)
    }

    enum GenerationJobDisposition: Equatable {
        case run
        case skip
        case park(GenerationParkReason)
    }

    func generationDisposition(
        for job: SpeechGenerationController.Job,
        activeJobs: [SpeechGenerationController.Job],
        playbackAdmission: PlaybackController.GenerationAdmissionSnapshot,
    ) throws -> GenerationJobDisposition {
        let request = job.request

        switch residentState {
            case .warming:
                return .park(.waitingForResidentModel)
            case .unloaded:
                if request.requiresResidentModels {
                    return .park(.waitingForResidentModels)
                }
            case .failed:
                if request.mutatesResidentState {
                    return .run
                }
                if request.requiresResidentModels {
                    return .park(.waitingForResidentModels)
                }
            case .ready:
                break
        }

        if request.requiresPlaybackDrainBeforeStart, playbackAdmission.activeRequestID != nil {
            return .park(.waitingForActiveRequest)
        }

        if speechBackend == .marvis {
            if isLiveSpeechGenerationRequest(request),
               playbackAdmission.activeRequestID != nil,
               playbackAdmission.activeRequestTuningProfile == .firstDrainedLiveMarvis
               || !playbackAdmission.allowsConcurrentGeneration {
                return .park(.waitingForPlaybackStability)
            }
        }

        let maximumConcurrentGenerationJobs = maximumConcurrentGenerationJobs(for: speechBackend)
        if activeJobs.count >= maximumConcurrentGenerationJobs {
            return .park(.waitingForActiveRequest)
        }

        return .run
    }

    func maximumConcurrentGenerationJobs(
        for backend: SpeakSwiftly.SpeechBackend,
    ) -> Int {
        switch backend {
            case .marvis:
                1
            case .qwen3, .chatterboxTurbo:
                1
        }
    }

    func isLiveSpeechGenerationRequest(_ request: WorkerRequest) -> Bool {
        if case .queueSpeech(
            id: _,
            text: _,
            profileName: _,
            textProfileID: _,
            jobType: .live,
            inputTextContext: _,
            requestContext: _,
            qwenPreModelTextChunking: _,
        ) = request {
            return true
        }
        return false
    }

    func isBlockedByProfileCreation(
        _ job: SpeechGenerationController.Job,
        activeJobs: [SpeechGenerationController.Job],
        queuedJobs: [SpeechGenerationController.Job],
    ) -> Bool {
        guard case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileID: _, jobType: _, inputTextContext: _, requestContext: _, qwenPreModelTextChunking: _) = job.request else {
            return false
        }

        if activeJobs.contains(where: { activeRequestCreatesProfileNamed($0.request, profileName: profileName) }) {
            return true
        }

        for queuedJob in queuedJobs {
            if queuedJob.token == job.token {
                break
            }

            if activeRequestCreatesProfileNamed(queuedJob.request, profileName: profileName) {
                return true
            }
        }

        return false
    }

    func activeRequestCreatesProfileNamed(_ request: WorkerRequest, profileName: String) -> Bool {
        switch request {
            case let .createProfile(_, activeProfileName, _, _, _, _, _):
                activeProfileName == profileName
            case let .createClone(_, activeProfileName, _, _, _, _):
                activeProfileName == profileName
            case let .renameProfile(_, activeProfileName, _):
                activeProfileName == profileName
            case let .rerollProfile(_, activeProfileName):
                activeProfileName == profileName
            default:
                false
        }
    }

    func logMarvisSchedulerSnapshotIfNeeded(
        activeJobs: [SpeechGenerationController.Job],
        queuedJobs: [SpeechGenerationController.Job],
        runnableJobs: [SpeechGenerationController.Job],
        parkReasons: [UUID: GenerationParkReason],
        playbackTelemetry: PlaybackController.ConcurrencySnapshot,
    ) async {
        guard speechBackend == .marvis else { return }
        guard !activeJobs.isEmpty || !queuedJobs.isEmpty || playbackTelemetry.activeRequestID != nil else {
            lastLoggedMarvisSchedulerState = nil
            return
        }

        let stateDescription = [
            "active=\(activeJobs.map(\.request.id).joined(separator: ","))",
            "queued=\(queuedJobs.map(\.request.id).joined(separator: ","))",
            "runnable=\(runnableJobs.map(\.request.id).joined(separator: ","))",
            "playback=\(playbackTelemetry.activeRequestID ?? "none")",
            "stable=\(playbackTelemetry.isStableForConcurrentGeneration)",
            "rebuffering=\(playbackTelemetry.isRebuffering)",
        ]
        .joined(separator: "|")

        guard stateDescription != lastLoggedMarvisSchedulerState else { return }

        lastLoggedMarvisSchedulerState = stateDescription

        var parkedByRequest = [String: String]()
        for job in queuedJobs {
            if let reason = parkReasons[job.token] {
                parkedByRequest[job.request.id] = reason.rawValue
            }
        }

        var activeLaneAssignments = [String: String]()
        for job in activeJobs {
            if let lane = try? marvisGenerationLane(for: job.request) {
                activeLaneAssignments[job.request.id] = lane.rawValue
            }
        }

        await logEvent(
            "marvis_generation_scheduler_snapshot",
            details: [
                "active_generation_request_ids": .string(activeJobs.map(\.request.id).joined(separator: ",")),
                "queued_generation_request_ids": .string(queuedJobs.map(\.request.id).joined(separator: ",")),
                "runnable_generation_request_ids": .string(runnableJobs.map(\.request.id).joined(separator: ",")),
                "active_playback_request_id": .string(playbackTelemetry.activeRequestID ?? "none"),
                "playback_is_stable_for_concurrency": .bool(playbackTelemetry.isStableForConcurrentGeneration),
                "playback_is_rebuffering": .bool(playbackTelemetry.isRebuffering),
                "playback_stable_buffered_audio_ms": .int(playbackTelemetry.stableBufferedAudioMS ?? 0),
                "playback_stable_buffer_target_ms": .int(playbackTelemetry.stableBufferTargetMS ?? 0),
                "active_marvis_generation_lanes": .string(
                    activeLaneAssignments
                        .map { "\($0.key):\($0.value)" }
                        .sorted()
                        .joined(separator: ","),
                ),
                "parked_generation_reasons": .string(
                    parkedByRequest
                        .map { "\($0.key):\($0.value)" }
                        .sorted()
                        .joined(separator: ","),
                ),
            ]
            .merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
        )
    }

    func logMarvisGenerationLaneReservedIfNeeded(
        for request: WorkerRequest,
        activeJobs: [SpeechGenerationController.Job],
        playbackAdmission: PlaybackController.GenerationAdmissionSnapshot,
    ) async {
        guard let lane = try? marvisGenerationLane(for: request) else { return }

        await logRequestEvent(
            "marvis_generation_lane_reserved",
            requestID: request.id,
            op: request.opName,
            profileName: request.voiceProfile,
            details: [
                "marvis_lane": .string(lane.rawValue),
                "active_generation_count": .int(activeJobs.count),
                "active_generation_request_ids": .string(activeJobs.map(\.request.id).joined(separator: ",")),
                "playback_allows_concurrent_generation": .bool(playbackAdmission.allowsConcurrentGeneration),
                "active_playback_request_id": .string(playbackAdmission.activeRequestID ?? "none"),
            ]
            .merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
        )
    }

    func logMarvisGenerationLaneReleasedIfNeeded(
        for request: WorkerRequest,
        activeJobs: [SpeechGenerationController.Job],
        disposition: GenerationCompletionDisposition,
    ) async {
        guard let lane = try? marvisGenerationLane(for: request) else { return }

        let dispositionSummary = switch disposition {
            case .requestCompleted(.success):
                "completed"
            case let .requestCompleted(.failure(error)):
                "failed:\(error.code.rawValue)"
            case .requestStillPendingPlayback:
                "pending_playback"
        }
        await logRequestEvent(
            "marvis_generation_lane_released",
            requestID: request.id,
            op: request.opName,
            profileName: request.voiceProfile,
            details: [
                "marvis_lane": .string(lane.rawValue),
                "generation_disposition": .string(dispositionSummary),
                "remaining_active_generation_count": .int(activeJobs.count),
                "remaining_active_generation_request_ids": .string(activeJobs.map(\.request.id).joined(separator: ",")),
            ]
            .merging(memoryDetails(), uniquingKeysWith: { _, new in new }),
        )
    }

    func failQueuedRequests(with error: WorkerError) async {
        let queuedJobs = await generationController.clearQueued()

        for job in queuedJobs {
            if job.request.requiresPlayback {
                _ = await playbackController.discard(requestID: job.request.id)
            }
            markGenerationJobFailedIfNeeded(for: job.request, error: error)
            failRequestStream(for: job.request.id, error: error)
            await emitFailure(id: job.request.id, error: error)
        }
    }
}
