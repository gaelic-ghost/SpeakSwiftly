import Foundation

// MARK: - Voice Profile Generation Logic

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
        outputPath: String?,
        cwd: String?,
    ) async throws -> StoredProfile {
        let op = WorkerRequest.createProfile(
            id: id,
            profileName: profileName,
            text: text,
            vibe: vibe,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            cwd: cwd,
        )
        .opName
        try profileStore.validateProfileName(profileName)
        await emitProgress(id: id, stage: .loadingProfileModel)
        let modelLoadStartedAt = dependencies.now()
        let profileModel = try await dependencies.loadProfileModel()
        await logRequestEvent(
            "profile_model_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "model_repo": .string(ModelFactory.profileModelRepo),
                "duration_ms": .int(elapsedMS(since: modelLoadStartedAt)),
            ],
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .generatingProfileAudio)
        let generationStartedAt = dependencies.now()
        let audio = try await profileModel.generate(
            text: text,
            voice: voiceDescription,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: GenerationPolicy.profileParameters(for: text),
        )
        await logRequestEvent(
            "profile_audio_generated",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
            ],
        )
        try Task.checkCancellation()

        let tempDirectory = dependencies.fileManager
            .temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        try Task.checkCancellation()
        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        let writeWAV = dependencies.writeWAV
        try await runBlockingFilesystemOperation {
            try writeWAV(audio, profileModel.sampleRate, tempWavURL)
        }
        try Task.checkCancellation()
        let canonicalAudioData = try await runBlockingFilesystemOperation {
            try Data(contentsOf: tempWavURL)
        }
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let profileWriteStartedAt = dependencies.now()
        let profileStore = profileStore
        let storedProfile = try await runBlockingFilesystemOperation {
            try profileStore.createProfile(
                profileName: profileName,
                vibe: vibe,
                modelRepo: ModelFactory.profileModelRepo,
                voiceDescription: voiceDescription,
                sourceText: text,
                sampleRate: profileModel.sampleRate,
                canonicalAudioData: canonicalAudioData,
            )
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
            try await runBlockingFilesystemOperation {
                try profileStore.exportCanonicalAudio(for: storedProfile, to: resolvedOutputURL)
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
        let canonicalAudio = try requireLoadedCloneAudio(
            from: referenceAudioURL,
            sampleRate: ModelFactory.canonicalProfileSampleRate,
            requestID: id,
            pathLabel: "clone source audio",
            op: op,
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
        let tempDirectory = dependencies.fileManager
            .temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        try Task.checkCancellation()
        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        let writeWAV = dependencies.writeWAV
        try await runBlockingFilesystemOperation {
            try writeWAV(canonicalAudio, ModelFactory.canonicalProfileSampleRate, tempWavURL)
        }
        try Task.checkCancellation()
        let canonicalAudioData = try await runBlockingFilesystemOperation {
            try Data(contentsOf: tempWavURL)
        }
        try Task.checkCancellation()

        let profileWriteStartedAt = dependencies.now()
        let profileStore = profileStore
        let storedProfile = try await runBlockingFilesystemOperation {
            try profileStore.createProfile(
                profileName: profileName,
                vibe: vibe,
                modelRepo: ModelFactory.importedCloneModelRepo,
                voiceDescription: ModelFactory.importedCloneVoiceDescription,
                sourceText: resolvedTranscript.text,
                transcriptProvenance: resolvedTranscript.provenance,
                sampleRate: ModelFactory.canonicalProfileSampleRate,
                canonicalAudioData: canonicalAudioData,
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

        return storedProfile
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

        switch storedProfile.manifest.sourceKind {
            case .generated:
                return try await rerollGeneratedProfile(
                    id: id,
                    op: op,
                    storedProfile: storedProfile,
                )

            case .importedClone:
                return try await rerollImportedCloneProfile(
                    id: id,
                    op: op,
                    storedProfile: storedProfile,
                )
        }
    }
}
