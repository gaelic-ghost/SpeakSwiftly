import Foundation

// MARK: - Immediate Control

extension SpeakSwiftly.Runtime {
    func processImmediateControlRequest(_ request: WorkerRequest) async {
        let result: Result<WorkerSuccessPayload, WorkerError>
        let textProfilePath = await normalizerRef.persistence.url()?.path
        let textProfileStyle = await normalizerRef.style.getActive()

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
                            textProfile: SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.getActive(),
                            ),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfile(id, profileID):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: try? SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.get(id: profileID),
                            ),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfiles(id):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfiles: normalizerRef.profiles.list().map(SpeakSwiftly.TextProfileSummary.init),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .activeTextProfileStyle(id):
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfileStyleOptions(id):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyleOptions: normalizerRef.style.list().map(SpeakSwiftly.TextProfileStyleOption.init),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .textProfileEffective(id):
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.getEffective(),
                            ),
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
                            textProfile: SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.getActive(),
                            ),
                            textProfiles: normalizerRef.profiles.list().map(SpeakSwiftly.TextProfileSummary.init),
                            textProfileStyle: normalizerRef.style.getActive(),
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

                case let .setActiveTextProfileStyle(id, style):
                    try await normalizerRef.style.setActive(to: style)
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: normalizerRef.style.getActive(),
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .createTextProfile(id, profileName):
                    let profile = try await normalizerRef.profiles.create(name: profileName)
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(profile),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .renameTextProfile(id, profileID, profileName):
                    let profile = try await normalizerRef.profiles.rename(
                        profile: profileID,
                        to: profileName,
                    )
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(profile),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .setActiveTextProfile(id, profileID):
                    try await normalizerRef.profiles.setActive(id: profileID)
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.getActive(),
                            ),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .deleteTextProfile(id, profileID):
                    try await normalizerRef.profiles.delete(id: profileID)
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .factoryResetTextProfiles(id):
                    try await normalizerRef.profiles.factoryReset()
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.getActive(),
                            ),
                            textProfiles: normalizerRef.profiles.list().map(SpeakSwiftly.TextProfileSummary.init),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .resetTextProfile(id, profileID):
                    try await normalizerRef.profiles.reset(id: profileID)
                    result = await .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: try? SpeakSwiftly.TextProfileDetails(
                                normalizerRef.profiles.get(id: profileID),
                            ),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .addTextReplacement(id, replacement, profileID):
                    let profile = if let profileID {
                        try await normalizerRef.profiles.addReplacement(
                            replacement,
                            toProfile: profileID,
                        )
                    } else {
                        try await normalizerRef.profiles.addReplacement(replacement)
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(profile),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .replaceTextReplacement(id, replacement, profileID):
                    let profile = if let profileID {
                        try await normalizerRef.profiles.patchReplacement(
                            replacement,
                            inProfile: profileID,
                        )
                    } else {
                        try await normalizerRef.profiles.patchReplacement(replacement)
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(profile),
                            textProfileStyle: textProfileStyle,
                            textProfilePath: textProfilePath,
                        ),
                    )

                case let .removeTextReplacement(id, replacementID, profileID):
                    let profile = if let profileID {
                        try await normalizerRef.profiles.removeReplacement(
                            id: replacementID,
                            fromProfile: profileID,
                        )
                    } else {
                        try await normalizerRef.profiles.removeReplacement(id: replacementID)
                    }
                    result = .success(
                        WorkerSuccessPayload(
                            id: id,
                            textProfile: SpeakSwiftly.TextProfileDetails(profile),
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

                case let .clearQueue(id, queueType):
                    let clearedCount = await clearQueuedRequests(
                        queueType: queueType,
                        cancelledByRequestID: id,
                        reason: "queued work was cleared from the SpeakSwiftly queue",
                    )
                    result = .success(WorkerSuccessPayload(id: id, clearedCount: clearedCount))

                case let .cancelRequest(id, targetRequestID, queueType):
                    let cancelledRequestID = try await cancelRequestNow(
                        targetRequestID,
                        queueType: queueType,
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
