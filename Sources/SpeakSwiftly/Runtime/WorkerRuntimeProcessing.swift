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
                    disposition = .requestStillPendingPlayback(id)

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

    private func handleQueueSpeechLiveGeneration(id: String, op: String, text: String, profileName: String) async throws {
        guard let speechJob = await playbackController.job(for: id) else {
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
        speechJob.sampleRate = Double(residentModel.sampleRate)
        await playbackController.startNextIfPossible()
        try? await startNextGenerationIfPossible()

        await emitProgress(id: id, stage: .startingPlayback)
        let stream = residentGenerationStream(
            requestID: id,
            text: speechJob.normalizedText,
            inputs: residentInputs,
            generationParameters: GenerationPolicy.residentParameters(for: speechJob.normalizedText),
            streamingInterval: PlaybackConfiguration.residentStreamingInterval,
        )

        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                speechJob.continuation.yield(chunk)
            }
            speechJob.continuation.finish()
        } catch {
            speechJob.continuation.finish(throwing: error)
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

    private func fileArtifactID(for request: WorkerRequest) -> String {
        switch request {
            case .queueSpeech(id: let id, text: _, profileName: _, textProfileName: _, jobType: .file, textContext: _, sourceFormat: _):
                "\(id)-artifact-1"
            default:
                request.id
        }
    }

    private func loadGeneratedBatch(id batchID: String) throws -> SpeakSwiftly.GeneratedBatch {
        try loadGeneratedBatch(from: generationJobStore.loadGenerationJob(id: batchID))
    }

    private func listGeneratedBatches() throws -> [SpeakSwiftly.GeneratedBatch] {
        try generationJobStore.listGenerationJobs()
            .filter { $0.jobKind == .batch }
            .map(loadGeneratedBatch(from:))
    }

    private func loadGeneratedBatch(
        from job: SpeakSwiftly.GenerationJob,
    ) throws -> SpeakSwiftly.GeneratedBatch {
        guard job.jobKind == .batch else {
            throw WorkerError(
                code: .generatedBatchNotFound,
                message: "Generated batch '\(job.jobID)' was requested, but that id belongs to a file job rather than a batch job.",
            )
        }

        let artifacts: [SpeakSwiftly.GeneratedFile] = if job.state == .expired {
            []
        } else {
            try job.artifacts.map { artifact in
                try generatedFileStore.loadGeneratedFile(id: artifact.artifactID).summary
            }
        }

        return SpeakSwiftly.GeneratedBatch(
            batchID: job.jobID,
            profileName: job.profileName,
            textProfileName: job.textProfileName,
            speechBackend: job.speechBackend,
            state: job.state,
            items: job.items,
            artifacts: artifacts,
            failure: job.failure,
            createdAt: job.createdAt,
            updatedAt: job.updatedAt,
            startedAt: job.startedAt,
            completedAt: job.completedAt,
            failedAt: job.failedAt,
            expiresAt: job.expiresAt,
            retentionPolicy: job.retentionPolicy,
        )
    }

    private func expireGenerationJob(
        id jobID: String,
    ) throws -> SpeakSwiftly.GenerationJob {
        let job = try generationJobStore.loadGenerationJob(id: jobID)
        guard job.state != .queued, job.state != .running else {
            throw WorkerError(
                code: .generationJobNotExpirable,
                message: "Generation job '\(jobID)' is still \(job.state.rawValue) and cannot be expired until its generation work has finished.",
            )
        }

        for artifact in job.artifacts {
            _ = try generatedFileStore.removeGeneratedFile(id: artifact.artifactID)
        }

        return try generationJobStore.markExpired(id: jobID, expiredAt: dependencies.now())
    }

    func textFeatureDetails(_ features: SpeechTextDeepTraceFeatures) -> [String: LogValue] {
        [
            "original_character_count": .int(features.originalCharacterCount),
            "normalized_character_count": .int(features.normalizedCharacterCount),
            "normalized_character_delta": .int(features.normalizedCharacterDelta),
            "original_paragraph_count": .int(features.originalParagraphCount),
            "normalized_paragraph_count": .int(features.normalizedParagraphCount),
            "markdown_header_count": .int(features.markdownHeaderCount),
            "fenced_code_block_count": .int(features.fencedCodeBlockCount),
            "inline_code_span_count": .int(features.inlineCodeSpanCount),
            "markdown_link_count": .int(features.markdownLinkCount),
            "url_count": .int(features.urlCount),
            "file_path_count": .int(features.filePathCount),
            "dotted_identifier_count": .int(features.dottedIdentifierCount),
            "camel_case_token_count": .int(features.camelCaseTokenCount),
            "snake_case_token_count": .int(features.snakeCaseTokenCount),
            "objc_symbol_count": .int(features.objcSymbolCount),
            "repeated_letter_run_count": .int(features.repeatedLetterRunCount),
        ]
    }

    func textSectionDetails(_ section: SpeechTextDeepTraceSection) -> [String: LogValue] {
        [
            "section_index": .int(section.index),
            "section_title": .string(section.title),
            "section_kind": .string(section.kind.rawValue),
            "original_character_count": .int(section.originalCharacterCount),
            "normalized_character_count": .int(section.normalizedCharacterCount),
            "normalized_character_share": .double(section.normalizedCharacterShare),
        ]
    }

    func textSectionWindowDetails(_ window: SpeechTextDeepTraceSectionWindow) -> [String: LogValue] {
        textSectionDetails(window.section).merging(
            [
                "estimated_start_ms": .int(window.estimatedStartMS),
                "estimated_end_ms": .int(window.estimatedEndMS),
                "estimated_duration_ms": .int(window.estimatedDurationMS),
                "estimated_start_chunk": .int(window.estimatedStartChunk),
                "estimated_end_chunk": .int(window.estimatedEndChunk),
            ],
            uniquingKeysWith: { _, new in new },
        )
    }

    func preloadModelRepos(for speechBackend: SpeakSwiftly.SpeechBackend) -> [String] {
        switch speechBackend {
            case .qwen3, .qwen3CustomVoice:
                [ModelFactory.residentModelRepo(for: speechBackend)]
            case .marvis:
                [ModelFactory.marvisResidentModelRepo]
        }
    }

    func shouldApplyResidentPreloadResult(
        token: UUID,
        backend: SpeakSwiftly.SpeechBackend,
    ) -> Bool {
        residentPreloadToken == token && speechBackend == backend
    }

    func performOrderedSpeechBackendSwitch(
        to requestedSpeechBackend: SpeakSwiftly.SpeechBackend,
    ) async throws -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        invalidateQwenConditioningCache()
        speechBackend = requestedSpeechBackend
        residentState = .warming
        startResidentPreload()
        await preloadTask?.value

        switch residentState {
            case .ready, .warming:
                return currentStatusSnapshot()
            case .unloaded:
                return currentStatusSnapshot()
            case let .failed(error):
                throw error
        }
    }

    func performOrderedModelReload() async throws -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        invalidateQwenConditioningCache()
        residentState = .warming
        startResidentPreload()
        await preloadTask?.value

        switch residentState {
            case .ready, .warming, .unloaded:
                return currentStatusSnapshot()
            case let .failed(error):
                throw error
        }
    }

    func performOrderedModelUnload() async -> WorkerStatusEvent? {
        preloadTask?.cancel()
        preloadTask = nil
        residentPreloadToken = nil
        invalidateQwenConditioningCache()
        residentState = .unloaded
        await emitStatus(.residentModelsUnloaded)
        return currentStatusSnapshot()
    }

    func invalidateQwenConditioningCache() {
        qwenConditioningCache.removeAll(keepingCapacity: true)
    }

    func primaryResidentSampleRate(for models: ResidentSpeechModels) -> Int {
        switch models {
            case let .qwen3(model):
                model.sampleRate
            case let .marvis(models):
                models.conversationalA.sampleRate
        }
    }

    func residentQwenModelOrThrow() throws -> AnySpeechModel {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down.",
            )
        }

        switch residentState {
            case let .ready(.qwen3(model)):
                return model
            case .ready(.marvis):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Qwen model while the runtime is configured for the 'marvis' backend. This indicates a backend-routing bug.",
                )
            case .warming:
                throw WorkerError(code: .modelLoading, message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.")
            case .unloaded:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready.",
                )
            case let .failed(error):
                throw error
        }
    }

    func residentMarvisModelOrThrow(
        for vibe: SpeakSwiftly.Vibe,
    ) throws -> (model: AnySpeechModel, voice: MarvisResidentVoice) {
        if isShuttingDown {
            throw WorkerError(
                code: .workerShuttingDown,
                message: "The resident model cannot be used because the SpeakSwiftly worker is shutting down.",
            )
        }

        switch residentState {
            case let .ready(.marvis(models)):
                return models.model(for: vibe)
            case .ready(.qwen3):
                throw WorkerError(
                    code: .internalError,
                    message: "SpeakSwiftly attempted to use the resident Marvis model bundle while the runtime is configured for the '\(speechBackend.rawValue)' backend. This indicates a backend-routing bug.",
                )
            case .warming:
                throw WorkerError(code: .modelLoading, message: "The resident \(preloadModelRepos(for: speechBackend).joined(separator: ", ")) model set for the '\(speechBackend.rawValue)' backend is still loading.")
            case .unloaded:
                throw WorkerError(
                    code: .modelLoading,
                    message: "The resident models for the '\(speechBackend.rawValue)' backend are currently unloaded. Queue `reload_models` and retry this generation request after the runtime reports resident_model_ready.",
                )
            case let .failed(error):
                throw error
        }
    }

    func marvisGenerationLane(for request: WorkerRequest) throws -> MarvisResidentVoice? {
        guard speechBackend == .marvis else { return nil }

        let profileName: String? = switch request {
            case .queueSpeech(
            id: _,
            text: _,
            profileName: let profileName,
            textProfileName: _,
            jobType: _,
            textContext: _,
            sourceFormat: _,
        ):
                profileName
            case .queueBatch(id: _, profileName: let profileName, items: _):
                profileName
            default:
                nil
        }

        guard let profileName else { return nil }

        let profile = try profileStore.loadProfile(named: profileName)
        return MarvisResidentVoice.forVibe(profile.manifest.vibe)
    }

    private func finishActiveGeneration(token: UUID, request: WorkerRequest, disposition: GenerationCompletionDisposition) async {
        guard let activeGeneration = activeGenerations[token] else { return }

        activeGenerations.removeValue(forKey: token)
        await generationController.finishActive(token: token)
        await logMarvisGenerationLaneReleasedIfNeeded(
            for: activeGeneration.request,
            activeJobs: generationController.activeJobsOrdered(),
            disposition: disposition,
        )
        let finalDisposition = if isShuttingDown {
            switch disposition {
                case .requestCompleted(.success):
                    GenerationCompletionDisposition.requestCompleted(.failure(cancellationError(for: request.id)))
                default:
                    disposition
            }
        } else {
            disposition
        }

        recordGenerationDispositionIfNeeded(for: request, disposition: finalDisposition)
        switch finalDisposition {
            case let .requestCompleted(result):
                await completeRequest(request: request, result: result)
            case .requestStillPendingPlayback:
                break
        }

        guard !isShuttingDown else { return }

        try? await startNextGenerationIfPossible()
        await playbackController.startNextIfPossible()
    }

    private func finishImmediateRequest(request: WorkerRequest, result: Result<WorkerSuccessPayload, WorkerError>) async {
        await completeRequest(request: request, result: result)
    }

    func createQueuedGenerationJobIfNeeded(
        for request: WorkerRequest,
    ) throws -> SpeakSwiftly.GenerationJob? {
        switch request {
            case .queueSpeech(
            id: let id,
            text: let text,
            profileName: let profileName,
            textProfileName: let textProfileName,
            jobType: .file,
            textContext: let textContext,
            sourceFormat: let sourceFormat,
        ):
                try generationJobStore.createFileJob(
                    jobID: id,
                    profileName: profileName,
                    textProfileName: textProfileName,
                    speechBackend: speechBackend,
                    item: SpeakSwiftly.GenerationJobItem(
                        artifactID: fileArtifactID(for: request),
                        text: text,
                        textProfileName: textProfileName,
                        textContext: textContext,
                        sourceFormat: sourceFormat,
                    ),
                    createdAt: dependencies.now(),
                )
            case let .queueBatch(
            id: id,
            profileName: profileName,
            items: items,
        ):
                try generationJobStore.createBatchJob(
                    jobID: id,
                    profileName: profileName,
                    textProfileName: request.textProfileName,
                    speechBackend: speechBackend,
                    items: items,
                    createdAt: dependencies.now(),
                )
            default:
                nil
        }
    }

    func markGenerationJobRunningIfNeeded(for request: WorkerRequest) throws {
        switch request {
            case .queueSpeech(
            id: let id,
            text: _,
            profileName: _,
            textProfileName: _,
            jobType: .file,
            textContext: _,
            sourceFormat: _,
        ),
        .queueBatch(id: let id, profileName: _, items: _):
                _ = try generationJobStore.markRunning(
                    id: id,
                    speechBackend: speechBackend,
                    startedAt: dependencies.now(),
                )
            default:
                return
        }
    }

    private func recordGenerationDispositionIfNeeded(
        for request: WorkerRequest,
        disposition: GenerationCompletionDisposition,
    ) {
        switch disposition {
            case .requestStillPendingPlayback:
                return
            case let .requestCompleted(.success(payload)):
                switch request {
                    case .queueSpeech(
                    id: let id,
                    text: _,
                    profileName: _,
                    textProfileName: _,
                    jobType: .file,
                    textContext: _,
                    sourceFormat: _,
                ):
                        if payload.generationJob != nil {
                            return
                        }
                        if let generatedFile = payload.generatedFile {
                            let artifact = SpeakSwiftly.GenerationArtifact(
                                artifactID: generatedFile.artifactID,
                                kind: .audioWAV,
                                createdAt: generatedFile.createdAt,
                                filePath: generatedFile.filePath,
                                sampleRate: generatedFile.sampleRate,
                                profileName: generatedFile.profileName,
                                textProfileName: generatedFile.textProfileName,
                            )
                            _ = try? generationJobStore.markCompleted(
                                id: id,
                                artifacts: [artifact],
                                completedAt: dependencies.now(),
                            )
                        }
                    case .queueBatch(id: let id, profileName: _, items: _):
                        if payload.generationJob != nil {
                            return
                        }
                        if let generatedBatch = payload.generatedBatch {
                            let artifacts = generatedBatch.artifacts.map { generatedFile in
                                SpeakSwiftly.GenerationArtifact(
                                    artifactID: generatedFile.artifactID,
                                    kind: .audioWAV,
                                    createdAt: generatedFile.createdAt,
                                    filePath: generatedFile.filePath,
                                    sampleRate: generatedFile.sampleRate,
                                    profileName: generatedFile.profileName,
                                    textProfileName: generatedFile.textProfileName,
                                )
                            }
                            _ = try? generationJobStore.markCompleted(
                                id: id,
                                artifacts: artifacts,
                                completedAt: dependencies.now(),
                            )
                        }
                    default:
                        return
                }
            case let .requestCompleted(.failure(error)):
                markGenerationJobFailedIfNeeded(for: request, error: error)
        }
    }

    func markGenerationJobFailedIfNeeded(
        for request: WorkerRequest,
        error: WorkerError,
    ) {
        switch request {
            case .queueSpeech(
            id: let id,
            text: _,
            profileName: _,
            textProfileName: _,
            jobType: .file,
            textContext: _,
            sourceFormat: _,
        ),
        .queueBatch(id: let id, profileName: _, items: _):
                _ = try? generationJobStore.markFailed(
                    id: id,
                    error: error,
                    failedAt: dependencies.now(),
                )
            default:
                return
        }
    }

    func makeSpeechJobState(for request: WorkerRequest) async -> PlaybackJob {
        let requestID = request.id
        let op = request.opName
        let text = switch request {
            case .queueSpeech(id: _, text: let text, profileName: _, textProfileName: _, jobType: _, textContext: _, sourceFormat: _):
                text
            default:
                ""
        }
        let profileName = request.profileName ?? "unknown-profile"
        let textProfileName = request.textProfileName
        let textContext = request.textContext
        let sourceFormat = request.sourceFormat
        let textProfileStyle = await normalizerRef.profiles.builtInStyle()
        let textProfile = if let textProfileName {
            await normalizerRef.profiles.stored(id: textProfileName) ?? .default
        } else {
            await normalizerRef.profiles.active() ?? .default
        }
        let normalizedText = if let sourceFormat {
            TextForSpeech.Normalize.source(
                text,
                as: sourceFormat,
                context: textContext,
                customProfile: textProfile,
                style: textProfileStyle,
            )
        } else {
            TextForSpeech.Normalize.text(
                text,
                context: textContext,
                customProfile: textProfile,
                style: textProfileStyle,
            )
        }
        let textFeatures = SpeakSwiftly.DeepTrace.features(
            originalText: text,
            normalizedText: normalizedText,
        )
        let textSections = SpeakSwiftly.DeepTrace.sections(originalText: text)
        var continuation: AsyncThrowingStream<[Float], any Swift.Error>.Continuation?
        let stream = AsyncThrowingStream<[Float], any Swift.Error> { continuation = $0 }
        guard let continuation else {
            fatalError(
                "SpeakSwiftly could not create a playback stream continuation for request '\(requestID)'. AsyncThrowingStream did not provide its continuation during job creation.",
            )
        }

        return PlaybackJob(
            requestID: requestID,
            op: op,
            text: text,
            normalizedText: normalizedText,
            profileName: profileName,
            textProfileName: textProfileName,
            textContext: textContext,
            sourceFormat: sourceFormat,
            textFeatures: textFeatures,
            textSections: textSections,
            stream: stream,
            continuation: continuation,
        )
    }
}
