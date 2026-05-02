import Foundation

// MARK: - Voice Profile Reroll Logic

extension SpeakSwiftly.Runtime {
    func rerollGeneratedProfile(
        id: String,
        op: String,
        storedProfile: StoredProfile,
        targetProfileName: String? = nil,
    ) async throws -> StoredProfile {
        let targetProfileName = targetProfileName ?? storedProfile.manifest.profileName
        await emitProgress(id: id, stage: .loadingProfileModel)
        let modelLoadStartedAt = dependencies.now()
        let profileModel = try await dependencies.loadProfileModel()
        await logRequestEvent(
            "profile_model_loaded_for_reroll",
            requestID: id,
            op: op,
            profileName: storedProfile.manifest.profileName,
            details: [
                "model_repo": .string(ModelFactory.profileModelRepo),
                "duration_ms": .int(elapsedMS(since: modelLoadStartedAt)),
            ],
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .generatingProfileAudio)
        let generationStartedAt = dependencies.now()
        let rawAudio = try await profileModel.generate(
            text: storedProfile.manifest.sourceText,
            voice: storedProfile.manifest.voiceDescription,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: GenerationPolicy.profileModelParameters(for: storedProfile.manifest.sourceText),
        )
        let audio = gainNormalizedProfileReferenceAudio(rawAudio)
        await logRequestEvent(
            "profile_audio_rerolled",
            requestID: id,
            op: op,
            profileName: storedProfile.manifest.profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(rawAudio.count),
            ],
        )
        try Task.checkCancellation()

        let audioData = try await canonicalAudioData(
            from: audio,
            sampleRate: profileModel.sampleRate,
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let replaceStartedAt = dependencies.now()
        let profileStore = profileStore
        var rerolledProfile = try await runBlockingFilesystemOperation {
            if targetProfileName == storedProfile.manifest.profileName {
                return try profileStore.replaceProfile(
                    named: storedProfile.manifest.profileName,
                    vibe: storedProfile.manifest.vibe,
                    modelRepo: storedProfile.manifest.modelRepo,
                    voiceDescription: storedProfile.manifest.voiceDescription,
                    sourceText: storedProfile.manifest.sourceText,
                    transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                    author: storedProfile.manifest.author,
                    seed: storedProfile.manifest.seed,
                    sampleRate: profileModel.sampleRate,
                    canonicalAudioData: audioData,
                    createdAt: storedProfile.manifest.createdAt,
                )
            }

            return try profileStore.createProfile(
                profileName: targetProfileName,
                vibe: storedProfile.manifest.vibe,
                modelRepo: storedProfile.manifest.modelRepo,
                voiceDescription: storedProfile.manifest.voiceDescription,
                sourceText: storedProfile.manifest.sourceText,
                transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                author: .user,
                seed: nil,
                sampleRate: profileModel.sampleRate,
                canonicalAudioData: audioData,
            )
        }
        await logRequestEvent(
            "profile_rerolled",
            requestID: id,
            op: op,
            profileName: targetProfileName,
            details: [
                "path": .string(rerolledProfile.directoryURL.path),
                "source_profile_name": .string(storedProfile.manifest.profileName),
                "source_kind": .string(storedProfile.manifest.sourceKind.rawValue),
                "duration_ms": .int(elapsedMS(since: replaceStartedAt)),
            ],
        )
        try Task.checkCancellation()
        rerolledProfile = try await prepareInitialQwenConditioningIfNeeded(
            requestID: id,
            op: op,
            profile: rerolledProfile,
        )
        return rerolledProfile
    }

    func rerollImportedCloneProfile(
        id: String,
        op: String,
        storedProfile: StoredProfile,
        targetProfileName: String? = nil,
    ) async throws -> StoredProfile {
        let targetProfileName = targetProfileName ?? storedProfile.manifest.profileName
        let canonicalAudioData = try await runBlockingFilesystemOperation {
            try Data(contentsOf: storedProfile.referenceAudioURL)
        }
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let replaceStartedAt = dependencies.now()
        let profileStore = profileStore
        var rerolledProfile = try await runBlockingFilesystemOperation {
            if targetProfileName == storedProfile.manifest.profileName {
                return try profileStore.replaceProfile(
                    named: storedProfile.manifest.profileName,
                    vibe: storedProfile.manifest.vibe,
                    modelRepo: storedProfile.manifest.modelRepo,
                    voiceDescription: storedProfile.manifest.voiceDescription,
                    sourceText: storedProfile.manifest.sourceText,
                    transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                    author: storedProfile.manifest.author,
                    seed: storedProfile.manifest.seed,
                    sampleRate: storedProfile.manifest.sampleRate,
                    canonicalAudioData: canonicalAudioData,
                    createdAt: storedProfile.manifest.createdAt,
                )
            }

            return try profileStore.createProfile(
                profileName: targetProfileName,
                vibe: storedProfile.manifest.vibe,
                modelRepo: storedProfile.manifest.modelRepo,
                voiceDescription: storedProfile.manifest.voiceDescription,
                sourceText: storedProfile.manifest.sourceText,
                transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                author: .user,
                seed: nil,
                sampleRate: storedProfile.manifest.sampleRate,
                canonicalAudioData: canonicalAudioData,
            )
        }
        await logRequestEvent(
            "clone_profile_rerolled",
            requestID: id,
            op: op,
            profileName: targetProfileName,
            details: [
                "path": .string(rerolledProfile.directoryURL.path),
                "source_profile_name": .string(storedProfile.manifest.profileName),
                "source_kind": .string(storedProfile.manifest.sourceKind.rawValue),
                "duration_ms": .int(elapsedMS(since: replaceStartedAt)),
            ],
        )
        try Task.checkCancellation()
        rerolledProfile = try await prepareInitialQwenConditioningIfNeeded(
            requestID: id,
            op: op,
            profile: rerolledProfile,
        )
        return rerolledProfile
    }
}
