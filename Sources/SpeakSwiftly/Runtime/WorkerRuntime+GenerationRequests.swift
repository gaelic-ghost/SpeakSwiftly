import Foundation
import TextForSpeech

// MARK: - Runtime Generation Requests

extension SpeakSwiftly.Runtime {
    func processGeneration(_ request: WorkerRequest, token: UUID) async {
        let disposition: GenerationCompletionDisposition

        do {
            switch request {
                case .queueSpeech(id: let id, text: let text, profileName: let profileName, textProfileID: _, jobType: .live, requestContext: _, qwenPreModelTextChunking: _):
                    try await handleQueueSpeechLiveGeneration(id: id, op: request.opName, text: text, profileName: profileName)
                    disposition = .requestStillPendingPlayback

                case .queueSpeech(
                id: let id,
                text: let text,
                profileName: let profileName,
                textProfileID: let textProfileID,
                jobType: .file,
                requestContext: let requestContext,
                qwenPreModelTextChunking: _,
            ):
                    let generatedFile = try await handleQueueSpeechFileGeneration(
                        requestID: id,
                        op: request.opName,
                        artifactID: fileArtifactID(for: request),
                        text: text,
                        voiceProfile: profileName,
                        textProfile: textProfileID,
                        requestContext: requestContext,
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
                                voiceProfile: generatedFile.voiceProfile,
                                textProfile: generatedFile.textProfile,
                                sourceFormat: generatedFile.sourceFormat,
                                requestContext: generatedFile.requestContext,
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
                                voiceProfile: generatedFile.voiceProfile,
                                textProfile: generatedFile.textProfile,
                                sourceFormat: generatedFile.sourceFormat,
                                requestContext: generatedFile.requestContext,
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

                case let .createProfile(id, profileName, text, vibe, voiceDescription, author, seed, outputPath, cwd):
                    let targetProfileStore = try profileStore(forProfileCreationAuthor: author)
                    let storedProfile = try await handleCreateProfile(
                        id: id,
                        profileName: profileName,
                        text: text,
                        vibe: vibe,
                        voiceDescription: voiceDescription,
                        author: author,
                        seed: seed,
                        outputPath: outputPath,
                        cwd: cwd,
                        profileStore: targetProfileStore,
                    )
                    if author == .user {
                        invalidateQwenConditioningCache()
                    }
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
                     .activeTextProfileStyle,
                     .textProfileStyleOptions,
                     .textProfileEffective,
                     .textProfilePersistence,
                     .loadTextProfiles,
                     .saveTextProfiles,
                     .setActiveTextProfileStyle,
                     .createTextProfile,
                     .renameTextProfile,
                     .setActiveTextProfile,
                     .deleteTextProfile,
                     .factoryResetTextProfiles,
                     .resetTextProfile,
                     .addTextReplacement,
                     .replaceTextReplacement,
                     .removeTextReplacement,
                     .listQueue,
                     .status,
                     .overview,
                     .defaultVoiceProfile,
                     .setDefaultVoiceProfile,
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
        guard let playbackState = await playbackQueue.playbackState(for: id) else {
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
        await playbackQueue.startNextIfPossible()
        try? await startNextGenerationIfPossible()
        if speechBackend.isQwenFamily {
            await logQwenLiveChunkPlan(for: playbackState.request)
        }

        await emitProgress(id: id, stage: .startingPlayback)
        let sampleStream = residentLiveGenerationStream(
            requestID: id,
            op: op,
            profileName: profileName,
            text: playbackState.request.normalizedText,
            plannedTextChunks: playbackState.request.normalizedLiveChunks,
            inputs: residentInputs,
            generationParameters: GenerationPolicy.residentParameters(
                for: speechBackend,
                text: playbackState.request.normalizedText,
            ),
            streamingInterval: playbackState.request.residentStreamingInterval,
        )
        do {
            switch audioOutputDestination {
                case .localPlayback:
                    for try await samples in sampleStream {
                        try Task.checkCancellation()
                        playbackState.execution.continuation.yield(samples)
                    }
                    playbackState.execution.continuation.finish()
                case .httpStream:
                    playbackState.execution.continuation.finish()
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Request '\(id)' selected HTTP audio streaming, but the worker runtime does not yet expose an HTTP response stream for JSONL live-speech requests. Use the SpeakSwiftlyHTTPAudioOutput module to frame generated chunks at an HTTP server boundary.",
                    )
                case let .networkStream(host, port):
                    playbackState.execution.continuation.finish()
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Request '\(id)' selected LAN audio streaming to '\(host):\(port)', but the worker runtime does not yet own a Network.framework connection for JSONL live-speech requests. Use the SpeakSwiftlyNetworkAudioOutput module to encode chunks at a LAN transport boundary.",
                    )
            }
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
                    voiceProfile: profileName,
                    textProfile: item.textProfile,
                    requestContext: item.requestContext,
                ),
            )
        }

        return generatedFiles
    }

    private func profileStore(forProfileCreationAuthor author: SpeakSwiftly.ProfileAuthor) throws -> ProfileStore {
        switch author {
            case .user:
                profileStore
            case .system:
                if let systemProfileResourceStore {
                    systemProfileResourceStore
                } else {
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "System voice profiles must be authored into bundled profile resources. Start SpeakSwiftlyTool with --system-profile-resource-root PATH and point PATH at the package resource directory that should contain the generated system profile resources.",
                    )
                }
        }
    }
}
