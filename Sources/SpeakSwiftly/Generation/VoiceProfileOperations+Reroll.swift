import Foundation

// MARK: - Voice Profile Reroll Logic

extension SpeakSwiftly.Runtime {
    func rerollGeneratedProfile(
        id: String,
        op: String,
        storedProfile: StoredProfile,
    ) async throws -> StoredProfile {
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
        let audio = try await profileModel.generate(
            text: storedProfile.manifest.sourceText,
            voice: storedProfile.manifest.voiceDescription,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: GenerationPolicy.profileModelParameters(for: storedProfile.manifest.sourceText),
        )
        await logRequestEvent(
            "profile_audio_rerolled",
            requestID: id,
            op: op,
            profileName: storedProfile.manifest.profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
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
            try profileStore.replaceProfile(
                named: storedProfile.manifest.profileName,
                vibe: storedProfile.manifest.vibe,
                modelRepo: storedProfile.manifest.modelRepo,
                voiceDescription: storedProfile.manifest.voiceDescription,
                sourceText: storedProfile.manifest.sourceText,
                transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                sampleRate: profileModel.sampleRate,
                canonicalAudioData: audioData,
                createdAt: storedProfile.manifest.createdAt,
            )
        }
        await logRequestEvent(
            "profile_rerolled",
            requestID: id,
            op: op,
            profileName: storedProfile.manifest.profileName,
            details: [
                "path": .string(rerolledProfile.directoryURL.path),
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
    ) async throws -> StoredProfile {
        let canonicalAudioData = try await runBlockingFilesystemOperation {
            try Data(contentsOf: storedProfile.referenceAudioURL)
        }
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let replaceStartedAt = dependencies.now()
        let profileStore = profileStore
        var rerolledProfile = try await runBlockingFilesystemOperation {
            try profileStore.replaceProfile(
                named: storedProfile.manifest.profileName,
                vibe: storedProfile.manifest.vibe,
                modelRepo: storedProfile.manifest.modelRepo,
                voiceDescription: storedProfile.manifest.voiceDescription,
                sourceText: storedProfile.manifest.sourceText,
                transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                sampleRate: storedProfile.manifest.sampleRate,
                canonicalAudioData: canonicalAudioData,
                createdAt: storedProfile.manifest.createdAt,
            )
        }
        await logRequestEvent(
            "clone_profile_rerolled",
            requestID: id,
            op: op,
            profileName: storedProfile.manifest.profileName,
            details: [
                "path": .string(rerolledProfile.directoryURL.path),
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
