import Foundation

// MARK: - Voice Profile Creation

extension SpeakSwiftly.Runtime {
    struct ResolvedCloneTranscript: Equatable {
        let text: String
        let provenance: TranscriptProvenance
    }

    func handleCreateProfile(
        id: String,
        profileName: String,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        author: SpeakSwiftly.ProfileAuthor = .user,
        seed: SpeakSwiftly.ProfileSeed? = nil,
        outputPath: String?,
        cwd: String?,
        profileStore targetProfileStore: ProfileStore? = nil,
    ) async throws -> StoredProfile {
        let profileStore = targetProfileStore ?? profileStore
        let op = WorkerRequest.createProfile(
            id: id,
            profileName: profileName,
            text: text,
            vibe: vibe,
            voiceDescription: voiceDescription,
            author: author,
            seed: seed,
            outputPath: outputPath,
            cwd: cwd,
        )
        .opName
        try profileStore.validateProfileName(profileName)
        let generatedAudio = try await generateProfileReferenceAudio(
            requestID: id,
            op: op,
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            modelLoadedEventName: "profile_model_loaded",
            audioGeneratedEventName: "profile_audio_generated",
        )
        let audioMaterialization = generatedAudio.materialization

        await emitProgress(id: id, stage: .writingProfileAssets)
        let profileWriteStartedAt = dependencies.now()
        let upsertedAt = dependencies.now()
        var storedProfile = try await runBlockingFilesystemOperation {
            switch author {
                case .system:
                    try profileStore.upsertSystemProfile(
                        named: profileName,
                        vibe: vibe,
                        modelRepo: ModelFactory.profileModelRepo,
                        voiceDescription: voiceDescription,
                        sourceText: text,
                        seed: seed,
                        sampleRate: audioMaterialization.sampleRate,
                        canonicalAudioData: audioMaterialization.canonicalAudioData,
                        createdAt: upsertedAt,
                    )
                case .user:
                    try profileStore.createProfile(
                        profileName: profileName,
                        vibe: vibe,
                        modelRepo: ModelFactory.profileModelRepo,
                        voiceDescription: voiceDescription,
                        sourceText: text,
                        author: author,
                        seed: seed,
                        sampleRate: audioMaterialization.sampleRate,
                        canonicalAudioData: audioMaterialization.canonicalAudioData,
                    )
            }
        }
        await logRequestEvent(
            "profile_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(storedProfile.directoryURL.path),
                "backend_materialization_count": .int(storedProfile.manifest.backendMaterializations.count),
                "duration_ms": .int(elapsedMS(since: profileWriteStartedAt)),
            ],
        )
        try Task.checkCancellation()
        storedProfile = try await prepareInitialQwenConditioningIfNeeded(
            requestID: id,
            op: op,
            profile: storedProfile,
            profileStore: profileStore,
        )

        if let outputPath {
            try Task.checkCancellation()
            await emitProgress(id: id, stage: .exportingProfileAudio)
            let exportStartedAt = dependencies.now()
            let resolvedOutputURL = try resolveFilesystemURL(
                outputPath,
                cwd: cwd,
                requestID: id,
                fieldName: "output_path",
                purpose: "profile export audio",
            )
            let profileForExport = storedProfile
            try await runBlockingFilesystemOperation {
                try profileStore.exportCanonicalAudio(for: profileForExport, to: resolvedOutputURL)
            }
            try Task.checkCancellation()
            await logRequestEvent(
                "profile_exported",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "path": .string(resolvedOutputURL.path),
                    "duration_ms": .int(elapsedMS(since: exportStartedAt)),
                ],
            )
        }

        return storedProfile
    }

    func handleCreateClone(
        id: String,
        profileName: String,
        referenceAudioPath: String,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        cwd: String?,
    ) async throws -> StoredProfile {
        let op = WorkerRequest.createClone(
            id: id,
            profileName: profileName,
            referenceAudioPath: referenceAudioPath,
            vibe: vibe,
            transcript: transcript,
            cwd: cwd,
        )
        .opName
        try profileStore.validateProfileName(profileName)
        let referenceAudioURL = try resolveCloneReferenceAudioURL(
            referenceAudioPath,
            cwd: cwd,
            requestID: id,
        )

        let sourceAudioLoadStartedAt = dependencies.now()
        let rawCanonicalAudio = try requireLoadedCloneAudio(
            from: referenceAudioURL,
            sampleRate: ModelFactory.canonicalProfileSampleRate,
            requestID: id,
            pathLabel: "clone source audio",
            op: op,
        )
        let audioMaterialization = try await materializeProfileReferenceAudio(
            from: rawCanonicalAudio,
            sampleRate: ModelFactory.canonicalProfileSampleRate,
        )
        await logRequestEvent(
            "clone_source_audio_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(referenceAudioURL.path),
                "sample_rate": .int(ModelFactory.canonicalProfileSampleRate),
                "duration_ms": .int(elapsedMS(since: sourceAudioLoadStartedAt)),
            ],
        )
        try Task.checkCancellation()

        let resolvedTranscript = try await resolvedCloneTranscript(
            requestID: id,
            op: op,
            profileName: profileName,
            referenceAudioURL: referenceAudioURL,
            transcript: transcript,
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let profileWriteStartedAt = dependencies.now()
        let profileStore = profileStore
        var storedProfile = try await runBlockingFilesystemOperation {
            try profileStore.createProfile(
                profileName: profileName,
                vibe: vibe,
                modelRepo: ModelFactory.importedCloneModelRepo,
                voiceDescription: ModelFactory.importedCloneVoiceDescription,
                sourceText: resolvedTranscript.text,
                transcriptProvenance: resolvedTranscript.provenance,
                author: .user,
                seed: nil,
                sampleRate: audioMaterialization.sampleRate,
                canonicalAudioData: audioMaterialization.canonicalAudioData,
            )
        }
        await logRequestEvent(
            "clone_profile_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(storedProfile.directoryURL.path),
                "backend_materialization_count": .int(storedProfile.manifest.backendMaterializations.count),
                "duration_ms": .int(elapsedMS(since: profileWriteStartedAt)),
            ],
        )
        try Task.checkCancellation()
        storedProfile = try await prepareInitialQwenConditioningIfNeeded(
            requestID: id,
            op: op,
            profile: storedProfile,
            profileStore: profileStore,
        )

        return storedProfile
    }

    func prepareInitialQwenConditioningIfNeeded(
        requestID id: String,
        op: String,
        profile: StoredProfile,
        profileStore: ProfileStore,
    ) async throws -> StoredProfile {
        guard speechBackend.isQwenFamily, qwenConditioningStrategy == .preparedConditioning else {
            return profile
        }

        if case .unloaded = residentState {
            await logRequestEvent(
                "qwen_initial_conditioning_skipped",
                requestID: id,
                op: op,
                profileName: profile.manifest.profileName,
                details: [
                    "speech_backend": .string(speechBackend.rawValue),
                    "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                    "reason": .string("resident_models_unloaded"),
                ],
            )
            return profile
        }

        if case .warming = residentState {
            await preloadTask?.value
        }

        let model = try residentQwenModelOrThrow()
        _ = try await loadPreparedQwenConditioning(
            requestID: id,
            op: op,
            profile: profile,
            profileStore: profileStore,
            backend: speechBackend,
            model: model,
        )
        try Task.checkCancellation()

        let updatedProfile = try profileStore.loadProfile(named: profile.manifest.profileName)
        await logRequestEvent(
            "qwen_initial_conditioning_ready",
            requestID: id,
            op: op,
            profileName: profile.manifest.profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                "model_repo": .string(ModelFactory.residentModelRepo(for: speechBackend)),
                "qwen_conditioning_artifact_count": .int(updatedProfile.manifest.qwenConditioningArtifacts.count),
            ],
        )

        return updatedProfile
    }

    func prepareQwenConditioningAfterRerollIfNeeded(
        requestID id: String,
        op: String,
        sourceProfile: StoredProfile,
        rerolledProfile: StoredProfile,
    ) async throws -> StoredProfile {
        guard qwenConditioningStrategy == .preparedConditioning else {
            return rerolledProfile
        }

        let backends = qwenConditioningBackendsToPrepareAfterRerolling(sourceProfile)
        guard !backends.isEmpty else {
            return rerolledProfile
        }

        if speechBackend.isQwenFamily, case .warming = residentState {
            await preloadTask?.value
        }

        for backend in backends {
            let model = try await qwenModelForConditioningPreparation(backend: backend)
            _ = try await loadPreparedQwenConditioning(
                requestID: id,
                op: op,
                profile: rerolledProfile,
                backend: backend,
                model: model,
            )
            try Task.checkCancellation()
        }

        let updatedProfile = try profileStore.loadProfile(named: rerolledProfile.manifest.profileName)
        await logRequestEvent(
            "qwen_reroll_conditioning_ready",
            requestID: id,
            op: op,
            profileName: rerolledProfile.manifest.profileName,
            details: [
                "speech_backend": .string(speechBackend.rawValue),
                "conditioning_strategy": .string(qwenConditioningStrategy.rawValue),
                "prepared_backend_count": .int(backends.count),
                "qwen_conditioning_artifact_count": .int(updatedProfile.manifest.qwenConditioningArtifacts.count),
            ],
        )

        return updatedProfile
    }

    private func qwenConditioningBackendsToPrepareAfterRerolling(
        _ sourceProfile: StoredProfile,
    ) -> [SpeakSwiftly.SpeechBackend] {
        var backends = [SpeakSwiftly.SpeechBackend]()
        var seenModelRepos = Set<String>()

        func append(_ backend: SpeakSwiftly.SpeechBackend) {
            guard backend.isQwenFamily else { return }

            let modelRepo = ModelFactory.residentModelRepo(for: backend)
            guard seenModelRepos.insert(modelRepo).inserted else { return }

            backends.append(backend)
        }

        append(speechBackend)

        for artifact in sourceProfile.manifest.qwenConditioningArtifacts {
            if artifact.backend.isQwenFamily {
                append(artifact.backend)
            } else if let backend = SpeakSwiftly.SpeechBackend.qwenBackend(forResidentModelRepo: artifact.modelRepo) {
                append(backend)
            }
        }

        return backends
    }

    private func qwenModelForConditioningPreparation(
        backend: SpeakSwiftly.SpeechBackend,
    ) async throws -> AnySpeechModel {
        if backend == speechBackend {
            return try residentQwenModelOrThrow()
        }

        let models = try await dependencies.loadResidentModels(backend)
        guard case let .qwen3(model) = models else {
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly loaded resident models for the '\(backend.rawValue)' backend while preparing rerolled Qwen conditioning, but the loaded model set did not contain a Qwen model. This indicates a backend-routing bug.",
            )
        }

        return model
    }

    func handleRerollProfile(
        id: String,
        profileName: String,
    ) async throws -> StoredProfile {
        let op = WorkerRequest.rerollProfile(
            id: id,
            profileName: profileName,
        )
        .opName
        let profileStore = profileStore

        await emitProgress(id: id, stage: .loadingProfile)
        let loadStartedAt = dependencies.now()
        let storedProfile = try await runBlockingFilesystemOperation {
            try profileStore.loadProfile(named: profileName)
        }
        await logRequestEvent(
            "profile_loaded_for_reroll",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "source_kind": .string(storedProfile.manifest.sourceKind.rawValue),
                "path": .string(storedProfile.directoryURL.path),
                "duration_ms": .int(elapsedMS(since: loadStartedAt)),
            ],
        )
        try Task.checkCancellation()

        let targetProfileName: String?
        if storedProfile.manifest.author == .system {
            targetProfileName = try await runBlockingFilesystemOperation {
                try profileStore.availableUserCopyName(for: storedProfile.manifest)
            }
            await logRequestEvent(
                "system_profile_reroll_redirected_to_user_copy",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "target_profile_name": .string(targetProfileName ?? profileName),
                ],
            )
        } else {
            targetProfileName = nil
        }

        switch storedProfile.manifest.sourceKind {
            case .generated:
                return try await rerollGeneratedProfile(
                    id: id,
                    op: op,
                    storedProfile: storedProfile,
                    targetProfileName: targetProfileName,
                )

            case .importedClone:
                return try await rerollImportedCloneProfile(
                    id: id,
                    op: op,
                    storedProfile: storedProfile,
                    targetProfileName: targetProfileName,
                )
        }
    }
}
