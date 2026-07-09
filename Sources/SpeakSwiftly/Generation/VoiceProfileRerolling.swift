import Foundation

// MARK: - Voice Profile Rerolling

extension SpeakSwiftly.Runtime {
    func rerollGeneratedProfile(
        id: String,
        op: String,
        storedProfile: StoredProfile,
        targetProfileName: String? = nil,
    ) async throws -> StoredProfile {
        let targetProfileName = targetProfileName ?? storedProfile.manifest.profileName
        let generatedAudio = try await generateProfileReferenceAudio(
            requestID: id,
            op: op,
            profileName: storedProfile.manifest.profileName,
            text: storedProfile.manifest.sourceText,
            voiceDescription: storedProfile.manifest.voiceDescription,
            modelLoadedEventName: "profile_model_loaded_for_reroll",
            audioGeneratedEventName: "profile_audio_rerolled",
        )
        let audioMaterialization = generatedAudio.materialization

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
                    sampleRate: audioMaterialization.sampleRate,
                    canonicalAudioData: audioMaterialization.canonicalAudioData,
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
                sampleRate: audioMaterialization.sampleRate,
                canonicalAudioData: audioMaterialization.canonicalAudioData,
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
        rerolledProfile = try await prepareQwenConditioningAfterRerollIfNeeded(
            requestID: id,
            op: op,
            sourceProfile: storedProfile,
            rerolledProfile: rerolledProfile,
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
        rerolledProfile = try await prepareQwenConditioningAfterRerollIfNeeded(
            requestID: id,
            op: op,
            sourceProfile: storedProfile,
            rerolledProfile: rerolledProfile,
        )
        return rerolledProfile
    }
}
