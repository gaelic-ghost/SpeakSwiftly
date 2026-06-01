import Foundation

// MARK: - Worker Runtime Generation Scheduling

extension SpeakSwiftly.Runtime {
    func startNextGenerationIfPossible() async throws {
        guard !isShuttingDown else { return }

        let activeJobs = await generationQueue.activeJobsOrdered()
        let queuedJobs = await generationQueue.queuedJobsOrdered()
        let preparingJobTokens = await generationQueue.preparingJobTokens()
        let playbackAdmission = await playbackQueue.generationAdmissionSnapshot()
        let decision = try evaluateGenerationSchedule(
            activeJobs: activeJobs,
            queuedJobs: queuedJobs,
            preparingJobTokens: preparingJobTokens,
            playbackAdmission: playbackAdmission,
        )

        await syncQueuedGenerationParkReasons(
            queuedJobs: queuedJobs,
            parkReasons: decision.parkReasons,
        )

        guard !decision.runnableJobs.isEmpty else { return }

        let jobs = await generationQueue.reserveQueuedJobs(tokens: decision.runnableJobs.map { $0.token })

        for job in jobs {
            lastQueuedGenerationParkReason.removeValue(forKey: job.request.id)
            try? markGenerationJobRunningIfNeeded(for: job.request)

            await emitStarted(for: job.request)
            await yieldRequestEvent(
                .started(WorkerStartedEvent(id: job.request.id, kind: job.request.requestKind)),
                for: job.request.id,
            )

            await logRequestEvent(
                "request_started",
                requestID: job.request.id,
                op: job.request.opName,
                profileName: job.request.voiceProfile,
                queueDepth: generationQueueDepth(),
            )

            let task = Task {
                await self.processGeneration(job.request, token: job.token)
            }
            activeGenerations[job.token] = ActiveRequest(token: job.token, request: job.request, task: task)
            if case .queueSpeech(id: let id, text: _, profileName: _, textProfileID: _, jobType: .live, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _) = job.request {
                await playbackQueue.setGenerationTask(task, for: id)
            }
        }

        await publishGenerateUpdate()
    }

    func evaluateGenerationSchedule(
        activeJobs: [GenerationQueue.Job],
        queuedJobs: [GenerationQueue.Job],
        preparingJobTokens: Set<UUID> = [],
        playbackAdmission: PlaybackQueue.GenerationAdmissionSnapshot,
    ) throws -> GenerationScheduleDecision {
        guard !queuedJobs.isEmpty else {
            return GenerationScheduleDecision(runnableJobs: [], parkReasons: [:])
        }

        var runnableJobs = [GenerationQueue.Job]()
        var parkReasons = [UUID: GenerationParkReason]()
        var sawParkedResidentDependentWork = false
        var selectedJobs = [GenerationQueue.Job]()

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
        for job: GenerationQueue.Job,
        activeJobs: [GenerationQueue.Job],
        playbackAdmission: PlaybackQueue.GenerationAdmissionSnapshot,
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
            case .qwen3_smol,
                 .qwen3_smol_4bit,
                 .qwen3_smol_5bit,
                 .qwen3_smol_6bit,
                 .qwen3_smol_8bit,
                 .qwen3_smol_bf16,
                 .qwen3_BIG,
                 .qwen3_BIG_4bit,
                 .qwen3_BIG_5bit,
                 .qwen3_BIG_6bit,
                 .qwen3_BIG_8bit,
                 .qwen3_BIG_bf16:
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
            audioFormat: _,
            requestContext: _,
            qwenPreModelTextChunking: _,
        ) = request {
            return true
        }
        return false
    }

    func isBlockedByProfileCreation(
        _ job: GenerationQueue.Job,
        activeJobs: [GenerationQueue.Job],
        queuedJobs: [GenerationQueue.Job],
    ) -> Bool {
        guard case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileID: _, jobType: _, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _) = job.request else {
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
            case let .createProfile(_, activeProfileName, _, _, _, _, _, _, _):
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

    func failQueuedRequests(with error: WorkerError) async {
        let queuedJobs = await generationQueue.clearQueued()

        for job in queuedJobs {
            if job.request.requiresPlayback {
                _ = await playbackQueue.discard(requestID: job.request.id)
            }
            markGenerationJobFailedIfNeeded(for: job.request, error: error)
            await failRequestStream(for: job.request.id, error: error)
            await emitFailure(id: job.request.id, error: error)
        }
    }
}
