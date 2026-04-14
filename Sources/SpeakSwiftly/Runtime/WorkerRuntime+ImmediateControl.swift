import Foundation

// MARK: - Immediate Control

extension SpeakSwiftly.Runtime {
    func processImmediateControlRequest(_ request: WorkerRequest) async {
        let result: Result<WorkerSuccessPayload, WorkerError>
        let textProfilePath = await normalizerRef.persistence.url()?.path
        let textProfileStyle = await normalizerRef.profiles.builtInStyle()

        do {
            switch request {
                case let .generatedFile(id, artifactID):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generatedFile: generatedFileStore.loadGeneratedFile(id: artifactID).summary,
                        ),
                    )

                case let .generatedFiles(id):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generatedFiles: generatedFileStore.listGeneratedFiles(),
                        ),
                    )

                case let .generatedBatch(id, batchID):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generatedBatch: loadGeneratedBatch(id: batchID),
                        ),
                    )

                case let .generatedBatches(id):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generatedBatches: listGeneratedBatches(),
                        ),
                    )

                case let .expireGenerationJob(id, jobID):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generationJob: expireGenerationJob(id: jobID),
                        ),
                    )

                case let .generationJob(id, jobID):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generationJob: generationJobStore.loadGenerationJob(id: jobID),
                        ),
                    )

                case let .generationJobs(id):
                    result = try .success(
                        WorkerSuccessPayload(
                            id: id,
                            generationJobs: generationJobStore.listGenerationJobs(),
                        ),
                    )

                case let .textProfileActive(id):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: normalizerRef.profiles.active(),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfile(id, name):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: normalizerRef.profiles.stored(id: name),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfiles(id):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfiles: normalizerRef.profiles.list(),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfileStyle(id):
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfileEffective(id, name):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: normalizerRef.profiles.effective(id: name),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfilePersistence(id):
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .loadTextProfiles(id):
                    try await normalizerRef.persistence.load()
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: normalizerRef.profiles.active(),
                            textProfiles: normalizerRef.profiles.list(),
                            textProfileStyle: normalizerRef.profiles.builtInStyle(),
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .saveTextProfiles(id):
                    try await normalizerRef.persistence.save()
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .setTextProfileStyle(id, style):
                    try await normalizerRef.profiles.setBuiltInStyle(style)
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: normalizerRef.profiles.builtInStyle(),
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .createTextProfile(id, profileID, profileName, replacements):
                    let profile = try await normalizerRef.profiles.create(
                        id: profileID,
                        name: profileName,
                        replacements: replacements,
                    )
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .storeTextProfile(id, profile):
                    try await normalizerRef.profiles.store(profile)
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .useTextProfile(id, profile):
                    try await normalizerRef.profiles.use(profile)
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .removeTextProfile(id, profileName):
                    try await normalizerRef.profiles.delete(id: profileName)
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .resetTextProfile(id):
                    try await normalizerRef.profiles.reset()
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: normalizerRef.profiles.active(),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textReplacements(id, profileName):
                    let profile = if let profileName {
                        await normalizerRef.profiles.stored(id: profileName)
                    } else {
                        await normalizerRef.profiles.active()
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            replacements: profile?.replacements ?? [],
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .addTextReplacement(id, replacement, profileName):
                    let profile = if let profileName {
                        try await normalizerRef.profiles.add(
                            replacement,
                            toStoredProfileID: profileName,
                        )
                    } else {
                        try await normalizerRef.profiles.add(replacement)
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .replaceTextReplacement(id, replacement, profileName):
                    let profile = if let profileName {
                        try await normalizerRef.profiles.replace(
                            replacement,
                            inStoredProfileID: profileName,
                        )
                    } else {
                        try await normalizerRef.profiles.replace(replacement)
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .removeTextReplacement(id, replacementID, profileName):
                    let profile = if let profileName {
                        try await normalizerRef.profiles.removeReplacement(
                            id: replacementID,
                            fromStoredProfileID: profileName,
                        )
                    } else {
                        try await normalizerRef.profiles.removeReplacement(id: replacementID)
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .clearTextReplacements(id, profileName):
                    let profile = if let profileName {
                        try await normalizerRef.profiles.clearReplacements(
                            fromStoredProfileID: profileName,
                        )
                    } else {
                        try await normalizerRef.profiles.clearReplacements()
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: profile,
                            replacements: profile.replacements,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .listQueue(id, queueType):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            activeRequest: queueSummaryActiveRequest(for: queueType),
                            activeRequests: queueSummaryActiveRequests(for: queueType),
                            queue: queuedRequestSummaries(for: queueType),
                        ),
                    )

                case let .status(id):
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            status: currentStatusSnapshot(),
                            speechBackend: speechBackend,
                        ),
                    )

                case let .overview(id):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            runtimeOverview: runtimeOverviewSnapshot(),
                        ),
                    )

                case let .playback(id, action):
                    _ = await playbackController.handle(action)
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            playbackState: playbackController.stateSnapshot(),
                        ),
                    )

                case let .clearQueue(id):
                    let clearedCount = await clearQueuedRequests(
                        cancelledByRequestID: id,
                        reason: "queued work was cleared from the SpeakSwiftly queue",
                    )
                    result = .success(WorkerSuccessPayload(id: id, clearedCount: clearedCount))

                case let .cancelRequest(id, targetRequestID):
                    let cancelledRequestID = try await cancelRequestNow(
                        targetRequestID,
                        cancelledByRequestID: id,
                    )
                    result = .success(WorkerSuccessPayload(id: id, cancelledRequestID: cancelledRequestID))

                case .queueSpeech,
                     .queueBatch,
                     .switchSpeechBackend,
                     .reloadModels,
                     .unloadModels,
                     .createProfile,
                     .createClone,
                     .listProfiles,
                     .renameProfile,
                     .rerollProfile,
                     .removeProfile:
                    result = .failure(
                        WorkerError(
                            code: .internalError,
                            message: "Non-control request '\(request.id)' was routed through the immediate control path unexpectedly. This indicates a runtime bug in SpeakSwiftly.",
                        ),
                    )
            }
        } catch is CancellationError {
            result = .failure(cancellationError(for: request.id))
        } catch let workerError as WorkerError {
            result = .failure(workerError)
        } catch {
            result = .failure(
                WorkerError(
                    code: .internalError,
                    message: "Control request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)",
                ),
            )
        }

        await finishImmediateRequest(request: request, result: result)
    }

    private func finishImmediateRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        await completeRequest(request: request, result: result)
    }
}
