import Foundation
import TextForSpeech

// MARK: - Worker Runtime Processing

extension SpeakSwiftly.Runtime {
    func processGeneration(_ request: WorkerRequest, token: UUID) async {
        let disposition: GenerationCompletionDisposition

        do {
            switch request {
                case .queueSpeech(id: let id, text: let text, profileName: let profileName, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
                    try await handleQueueSpeechLiveGeneration(id: id, op: request.opName, text: text, profileName: profileName)
                    disposition = .requestStillPendingPlayback

                case .queueSpeech(
                id: let id,
                text: let text,
                profileName: let profileName,
                textProfileName: let textProfileName,
                jobType: .file,
                textContext: let textContext,
                sourceFormat: let sourceFormat,
            ):
                    let generatedFile = try await handleQueueSpeechFileGeneration(
                        requestID: id,
                        op: request.opName,
                        artifactID: fileArtifactID(for: request),
                        text: text,
                        profileName: profileName,
                        textProfileName: textProfileName,
                        textContext: textContext,
                        sourceFormat: sourceFormat,
                    )
                    let completedJob = try generationJobStore.markCompleted(
                        id: id,
                        artifacts: [
                            SpeakSwiftly.GenerationArtifact(
                                artifactID: generatedFile.artifactID,
                                kind: .audioWAV,
                                createdAt: generatedFile.createdAt,
                                filePath: generatedFile.filePath,
                                sampleRate: generatedFile.sampleRate,
                                profileName: generatedFile.profileName,
                                textProfileName: generatedFile.textProfileName,
                            ),
                        ],
                        completedAt: dependencies.now(),
                    )
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            generatedFile: generatedFile,
                            generationJob: completedJob,
                        ),
                    ))

                case let .queueBatch(
                id: id,
                profileName: profileName,
                items: items,
            ):
                    let generatedFiles = try await handleQueueSpeechBatchGeneration(
                        requestID: id,
                        op: request.opName,
                        profileName: profileName,
                        items: items,
                    )
                    let completedJob = try generationJobStore.markCompleted(
                        id: id,
                        artifacts: generatedFiles.map { generatedFile in
                            SpeakSwiftly.GenerationArtifact(
                                artifactID: generatedFile.artifactID,
                                kind: .audioWAV,
                                createdAt: generatedFile.createdAt,
                                filePath: generatedFile.filePath,
                                sampleRate: generatedFile.sampleRate,
                                profileName: generatedFile.profileName,
                                textProfileName: generatedFile.textProfileName,
                            )
                        },
                        completedAt: dependencies.now(),
                    )
                    disposition = try .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            generatedBatch: loadGeneratedBatch(from: completedJob),
                            generationJob: completedJob,
                        ),
                    ))

                case let .switchSpeechBackend(id: id, speechBackend: requestedSpeechBackend):
                    let status = try await performOrderedSpeechBackendSwitch(to: requestedSpeechBackend)
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            status: status,
                            speechBackend: speechBackend,
                        ),
                    ))

                case let .reloadModels(id: id):
                    let status = try await performOrderedModelReload()
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            status: status,
                            speechBackend: speechBackend,
                        ),
                    ))

                case let .unloadModels(id: id):
                    let status = await performOrderedModelUnload()
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            status: status,
                            speechBackend: speechBackend,
                        ),
                    ))

                case let .createProfile(id, profileName, text, vibe, voiceDescription, outputPath, cwd):
                    let storedProfile = try await handleCreateProfile(
                        id: id,
                        profileName: profileName,
                        text: text,
                        vibe: vibe,
                        voiceDescription: voiceDescription,
                        outputPath: outputPath,
                        cwd: cwd,
                    )
                    invalidateQwenConditioningCache()
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            profileName: storedProfile.manifest.profileName,
                            profilePath: storedProfile.directoryURL.path,
                        ),
                    ))

                case let .createClone(id, profileName, referenceAudioPath, vibe, transcript, cwd):
                    let storedProfile = try await handleCreateClone(
                        id: id,
                        profileName: profileName,
                        referenceAudioPath: referenceAudioPath,
                        vibe: vibe,
                        transcript: transcript,
                        cwd: cwd,
                    )
                    invalidateQwenConditioningCache()
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            profileName: storedProfile.manifest.profileName,
                            profilePath: storedProfile.directoryURL.path,
                        ),
                    ))

                case let .listProfiles(id):
                    let listStartedAt = dependencies.now()
                    let profiles = try profileStore.listProfiles()
                    await logRequestEvent(
                        "profiles_listed",
                        requestID: id,
                        op: request.opName,
                        details: [
                            "profile_root": .string(profileStore.rootURL.path),
                            "count": .int(profiles.count),
                            "duration_ms": .int(elapsedMS(since: listStartedAt)),
                        ],
                    )
                    disposition = .requestCompleted(.success(WorkerSuccessPayload(id: id, profiles: profiles)))

                case let .renameProfile(id, profileName, newProfileName):
                    await emitProgress(id: id, stage: .writingProfileAssets)
                    let renameStartedAt = dependencies.now()
                    let storedProfile = try profileStore.renameProfile(named: profileName, to: newProfileName)
                    invalidateQwenConditioningCache()
                    await logRequestEvent(
                        "profile_renamed",
                        requestID: id,
                        op: request.opName,
                        profileName: storedProfile.manifest.profileName,
                        details: [
                            "old_profile_name": .string(profileName),
                            "new_profile_name": .string(newProfileName),
                            "path": .string(storedProfile.directoryURL.path),
                            "duration_ms": .int(elapsedMS(since: renameStartedAt)),
                        ],
                    )
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            profileName: storedProfile.manifest.profileName,
                            profilePath: storedProfile.directoryURL.path,
                        ),
                    ))

                case let .rerollProfile(id, profileName):
                    let storedProfile = try await handleRerollProfile(id: id, profileName: profileName)
                    invalidateQwenConditioningCache()
                    disposition = .requestCompleted(.success(
                        WorkerSuccessPayload(
                            id: id,
                            profileName: storedProfile.manifest.profileName,
                            profilePath: storedProfile.directoryURL.path,
                        ),
                    ))

                case let .removeProfile(id, profileName):
                    await emitProgress(id: id, stage: .removingProfile)
                    let removeStartedAt = dependencies.now()
                    try profileStore.removeProfile(named: profileName)
                    invalidateQwenConditioningCache()
                    await logRequestEvent(
                        "profile_removed",
                        requestID: id,
                        op: request.opName,
                        profileName: profileName,
                        details: [
                            "path": .string(profileStore.profileDirectoryURL(for: profileName).path),
                            "duration_ms": .int(elapsedMS(since: removeStartedAt)),
                        ],
                    )
                    disposition = .requestCompleted(.success(WorkerSuccessPayload(id: id, profileName: profileName)))

                case .generatedFile,
                     .generatedFiles,
                     .generatedBatch,
                     .generatedBatches,
                     .expireGenerationJob,
                     .generationJob,
                     .generationJobs,
                     .textProfileActive,
                     .textProfile,
                     .textProfiles,
                     .textProfileStyle,
                     .textProfileEffective,
                     .textProfilePersistence,
                     .loadTextProfiles,
                     .saveTextProfiles,
                     .setTextProfileStyle,
                     .createTextProfile,
                     .storeTextProfile,
                     .useTextProfile,
                     .removeTextProfile,
                     .resetTextProfile,
                     .textReplacements,
                     .addTextReplacement,
                     .replaceTextReplacement,
                     .removeTextReplacement,
                     .clearTextReplacements,
                     .listQueue,
                     .status,
                     .overview,
                     .playback,
                     .clearQueue,
                     .cancelRequest:
                    disposition = .requestCompleted(.failure(
                        WorkerError(
                            code: .internalError,
                            message: "Control request '\(request.id)' was routed through the serialized work queue unexpectedly. This indicates a runtime bug in SpeakSwiftly.",
                        ),
                    ))
            }
        } catch is CancellationError {
            disposition = .requestCompleted(.failure(cancellationError(for: request.id)))
        } catch let workerError as WorkerError {
            disposition = .requestCompleted(.failure(workerError))
        } catch {
            disposition = .requestCompleted(.failure(WorkerError(
                code: .internalError,
                message: "Request '\(request.id)' failed due to an unexpected internal error. \(error.localizedDescription)",
            )))
        }

        await finishActiveGeneration(token: token, request: request, disposition: disposition)
    }

    private func handleQueueSpeechLiveGeneration(id: String, op: String, text: String, profileName: String) async throws {
        guard let playbackState = await playbackController.playbackState(for: id) else {
            throw WorkerError(
                code: .internalError,
                message: "Request '\(id)' started generation without a matching live speech job state. This indicates a SpeakSwiftly runtime bug.",
            )
        }

        let residentInputs = try await loadResidentSpeechInputs(
            requestID: id,
            op: op,
            profileName: profileName,
        )
        let residentModel = residentInputs.model
        playbackState.execution.sampleRate = Double(residentModel.sampleRate)
        await playbackController.startNextIfPossible()
        try? await startNextGenerationIfPossible()

        await emitProgress(id: id, stage: .startingPlayback)
        let stream = residentGenerationStream(
            requestID: id,
            text: playbackState.request.normalizedText,
            inputs: residentInputs,
            generationParameters: GenerationPolicy.residentParameters(for: playbackState.request.normalizedText),
            streamingInterval: playbackState.request.residentStreamingInterval,
        )

        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                playbackState.execution.continuation.yield(chunk)
            }
            playbackState.execution.continuation.finish()
        } catch {
            playbackState.execution.continuation.finish(throwing: error)
            if let workerError = error as? WorkerError {
                throw workerError
            }
            if error is CancellationError {
                throw CancellationError()
            }
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Live speech generation failed while streaming audio for request '\(id)'. \(error.localizedDescription)",
            )
        }
    }

    private func handleQueueSpeechBatchGeneration(
        requestID id: String,
        op: String,
        profileName: String,
        items: [SpeakSwiftly.GenerationJobItem],
    ) async throws -> [SpeakSwiftly.GeneratedFile] {
        var generatedFiles = [SpeakSwiftly.GeneratedFile]()
        generatedFiles.reserveCapacity(items.count)

        for item in items {
            try Task.checkCancellation()
            try await generatedFiles.append(
                handleQueueSpeechFileGeneration(
                    requestID: id,
                    op: op,
                    artifactID: item.artifactID,
                    text: item.text,
                    profileName: profileName,
                    textProfileName: item.textProfileName,
                    textContext: item.textContext,
                    sourceFormat: item.sourceFormat,
                ),
            )
        }

        return generatedFiles
    }
}
