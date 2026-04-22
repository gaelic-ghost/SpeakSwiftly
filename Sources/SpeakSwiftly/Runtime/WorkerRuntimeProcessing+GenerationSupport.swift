import Foundation
import TextForSpeech

// MARK: - Worker Runtime Generation Support

extension SpeakSwiftly.Runtime {
    func loadGeneratedBatch(id batchID: String) throws -> SpeakSwiftly.GeneratedBatch {
        try loadGeneratedBatch(from: generationJobStore.loadGenerationJob(id: batchID))
    }

    func listGeneratedBatches() throws -> [SpeakSwiftly.GeneratedBatch] {
        try generationJobStore.listGenerationJobs()
            .filter { $0.jobKind == .batch }
            .map(loadGeneratedBatch(from:))
    }

    func expireGenerationJob(id jobID: String) throws -> SpeakSwiftly.GenerationJob {
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

    func createQueuedGenerationJobIfNeeded(
        for request: WorkerRequest,
    ) throws -> SpeakSwiftly.GenerationJob? {
        switch request {
            case .queueSpeech(
            id: let id,
            text: let text,
            profileName: let profileName,
            textProfileID: let textProfileID,
            jobType: .file,
            textContext: let textContext,
            sourceFormat: let sourceFormat,
        ):
                try generationJobStore.createFileJob(
                    jobID: id,
                    profileName: profileName,
                    textProfileID: textProfileID,
                    speechBackend: speechBackend,
                    item: SpeakSwiftly.GenerationJobItem(
                        artifactID: fileArtifactID(for: request),
                        text: text,
                        textProfileID: textProfileID,
                        textContext: textContext,
                        sourceFormat: sourceFormat,
                    ),
                    createdAt: dependencies.now(),
                )
            case let .queueBatch(id: id, profileName: profileName, items: items):
                try generationJobStore.createBatchJob(
                    jobID: id,
                    profileName: profileName,
                    textProfileID: request.textProfileID,
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
            textProfileID: _,
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

    func markGenerationJobFailedIfNeeded(
        for request: WorkerRequest,
        error: WorkerError,
    ) {
        switch request {
            case .queueSpeech(
            id: let id,
            text: _,
            profileName: _,
            textProfileID: _,
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

    func makeSpeechJobState(for request: WorkerRequest) async -> LiveSpeechRequestState {
        let text = switch request {
            case .queueSpeech(id: _, text: let text, profileName: _, textProfileID: _, jobType: _, textContext: _, sourceFormat: _):
                text
            default:
                ""
        }
        let textProfileID = request.textProfileID
        let textContext = request.textContext
        let sourceFormat = request.sourceFormat
        let textProfileStyle = await normalizerRef.style.getActive()
        let textProfile: TextForSpeech.Profile
        if let textProfileID,
           let details = try? await normalizerRef.profiles.get(id: textProfileID) {
            textProfile = TextForSpeech.Profile(
                id: details.profileID,
                name: details.summary.name,
                replacements: details.replacements,
            )
        } else {
            let details = await normalizerRef.profiles.getActive()
            textProfile = TextForSpeech.Profile(
                id: details.profileID,
                name: details.summary.name,
                replacements: details.replacements,
            )
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
        let existingPlaybackJobCount = await playbackController.jobCount()
        let playbackTuningProfile: PlaybackTuningProfile =
            if speechBackend == .marvis {
                .firstDrainedLiveMarvis
            } else {
                .standard
            }
        let residentStreamingCadenceProfile = PlaybackConfiguration.residentStreamingCadenceProfile(
            speechBackend: speechBackend,
            existingPlaybackJobCount: existingPlaybackJobCount,
        )
        let residentStreamingInterval = PlaybackConfiguration.residentStreamingInterval(
            for: speechBackend,
            cadenceProfile: residentStreamingCadenceProfile,
        )
        return LiveSpeechRequestState(
            request: request,
            normalizedText: normalizedText,
            textFeatures: textFeatures,
            textSections: textSections,
            playbackTuningProfile: playbackTuningProfile,
            residentStreamingCadenceProfile: residentStreamingCadenceProfile,
            residentStreamingInterval: residentStreamingInterval,
        )
    }

    func fileArtifactID(for request: WorkerRequest) -> String {
        switch request {
            case .queueSpeech(id: let id, text: _, profileName: _, textProfileID: _, jobType: .file, textContext: _, sourceFormat: _):
                "\(id)-artifact-1"
            default:
                request.id
        }
    }

    func finishActiveGeneration(
        token: UUID,
        request: WorkerRequest,
        disposition: GenerationCompletionDisposition,
    ) async {
        guard let activeGeneration = activeGenerations[token] else { return }

        activeGenerations.removeValue(forKey: token)
        await generationController.finishActive(token: token)
        await logMarvisGenerationLaneReleasedIfNeeded(
            for: activeGeneration.request,
            activeJobs: generationController.activeJobsOrdered(),
            disposition: disposition,
        )
        let finalDisposition: GenerationCompletionDisposition = if isShuttingDown {
            switch disposition {
                case .requestCompleted(.success):
                    .requestCompleted(.failure(cancellationError(for: request.id)))
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

    func loadGeneratedBatch(
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
            textProfileID: job.textProfileID,
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
                    textProfileID: _,
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
                                textProfileID: generatedFile.textProfileID,
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
                                    textProfileID: generatedFile.textProfileID,
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
}
