import Foundation

// MARK: - Voice Profile Generation Logic

extension SpeakSwiftly.Runtime {
    func handleCreateProfile(
        id: String,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?
    ) async throws -> StoredProfile {
        let op = WorkerRequest.createProfile(
            id: id,
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath
        ).opName
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
            ]
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .generatingProfileAudio)
        let generationStartedAt = dependencies.now()
        let audio = try await profileModel.generate(
            text: text,
            voice: voiceDescription,
            refAudio: nil,
            refText: nil,
            language: "English",
            generationParameters: GenerationPolicy.profileParameters(for: text)
        )
        await logRequestEvent(
            "profile_audio_generated",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: generationStartedAt)),
                "sample_count": .int(audio.count),
            ]
        )
        try Task.checkCancellation()

        let tempDirectory = dependencies.fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        try dependencies.writeWAV(audio, profileModel.sampleRate, tempWavURL)
        let canonicalAudioData = try Data(contentsOf: tempWavURL)
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let profileWriteStartedAt = dependencies.now()
        let storedProfile = try profileStore.createProfile(
            profileName: profileName,
            modelRepo: ModelFactory.profileModelRepo,
            voiceDescription: voiceDescription,
            sourceText: text,
            sampleRate: profileModel.sampleRate,
            canonicalAudioData: canonicalAudioData
        )
        await logRequestEvent(
            "profile_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(storedProfile.directoryURL.path),
                "backend_materialization_count": .int(storedProfile.manifest.backendMaterializations.count),
                "duration_ms": .int(elapsedMS(since: profileWriteStartedAt)),
            ]
        )

        if let outputPath {
            await emitProgress(id: id, stage: .exportingProfileAudio)
            let exportStartedAt = dependencies.now()
            try profileStore.exportCanonicalAudio(for: storedProfile, to: outputPath)
            await logRequestEvent(
                "profile_exported",
                requestID: id,
                op: op,
                profileName: profileName,
                details: [
                    "path": .string(profileStore.resolveOutputURL(outputPath).path),
                    "duration_ms": .int(elapsedMS(since: exportStartedAt)),
                ]
            )
        }

        return storedProfile
    }

    func handleCreateClone(
        id: String,
        profileName: String,
        referenceAudioPath: String,
        transcript: String?
    ) async throws -> StoredProfile {
        let op = WorkerRequest.createClone(
            id: id,
            profileName: profileName,
            referenceAudioPath: referenceAudioPath,
            transcript: transcript
        ).opName
        try profileStore.validateProfileName(profileName)
        let referenceAudioURL = try resolveCloneReferenceAudioURL(referenceAudioPath, requestID: id)

        let sourceAudioLoadStartedAt = dependencies.now()
        let canonicalAudio = try requireLoadedCloneAudio(
            from: referenceAudioURL,
            sampleRate: ModelFactory.canonicalProfileSampleRate,
            requestID: id,
            pathLabel: "clone source audio",
            op: op
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
            ]
        )
        try Task.checkCancellation()

        let resolvedTranscript = try await resolvedCloneTranscript(
            requestID: id,
            op: op,
            profileName: profileName,
            referenceAudioURL: referenceAudioURL,
            transcript: transcript
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let tempDirectory = dependencies.fileManager.temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        try dependencies.writeWAV(canonicalAudio, ModelFactory.canonicalProfileSampleRate, tempWavURL)
        let canonicalAudioData = try Data(contentsOf: tempWavURL)

        let profileWriteStartedAt = dependencies.now()
        let storedProfile = try profileStore.createProfile(
            profileName: profileName,
            modelRepo: ModelFactory.importedCloneModelRepo,
            voiceDescription: ModelFactory.importedCloneVoiceDescription,
            sourceText: resolvedTranscript,
            sampleRate: ModelFactory.canonicalProfileSampleRate,
            canonicalAudioData: canonicalAudioData
        )
        await logRequestEvent(
            "clone_profile_written",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(storedProfile.directoryURL.path),
                "backend_materialization_count": .int(storedProfile.manifest.backendMaterializations.count),
                "duration_ms": .int(elapsedMS(since: profileWriteStartedAt)),
            ]
        )

        return storedProfile
    }

    func resolvedCloneTranscript(
        requestID id: String,
        op: String,
        profileName: String,
        referenceAudioURL: URL,
        transcript: String?
    ) async throws -> String {
        if let transcript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty {
            return transcript
        }

        await emitProgress(id: id, stage: .loadingCloneTranscriptionModel)
        let modelLoadStartedAt = dependencies.now()
        var cloneTranscriptionModel: AnyCloneTranscriptionModel? = try await dependencies.loadCloneTranscriptionModel()
        await logRequestEvent(
            "clone_transcription_model_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "model_repo": .string(ModelFactory.cloneTranscriptionModelRepo),
                "duration_ms": .int(elapsedMS(since: modelLoadStartedAt)),
            ]
        )
        defer {
            cloneTranscriptionModel = nil
        }
        try Task.checkCancellation()

        guard let cloneTranscriptionModel else {
            throw WorkerError(
                code: .internalError,
                message: "Clone request '\(id)' lost its transcription model before transcription started. This indicates a SpeakSwiftly runtime bug."
            )
        }

        let transcriptionAudioLoadStartedAt = dependencies.now()
        let transcriptionAudio = try requireLoadedCloneAudio(
            from: referenceAudioURL,
            sampleRate: cloneTranscriptionModel.sampleRate,
            requestID: id,
            pathLabel: "clone transcription audio",
            op: op
        )
        await logRequestEvent(
            "clone_transcription_audio_loaded",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "path": .string(referenceAudioURL.path),
                "sample_rate": .int(cloneTranscriptionModel.sampleRate),
                "duration_ms": .int(elapsedMS(since: transcriptionAudioLoadStartedAt)),
            ]
        )

        await emitProgress(id: id, stage: .transcribingCloneAudio)
        let transcriptionStartedAt = dependencies.now()
        let inferredTranscript = cloneTranscriptionModel
            .transcribe(
                audio: transcriptionAudio,
                generationParameters: GenerationPolicy.cloneTranscriptionParameters()
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        await logRequestEvent(
            "clone_audio_transcribed",
            requestID: id,
            op: op,
            profileName: profileName,
            details: [
                "duration_ms": .int(elapsedMS(since: transcriptionStartedAt)),
                "character_count": .int(inferredTranscript.count),
            ]
        )

        guard !inferredTranscript.isEmpty else {
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Clone request '\(id)' could not infer a transcript from '\(referenceAudioURL.path)'. Provide 'transcript' explicitly or retry with clearer speech audio."
            )
        }

        return inferredTranscript
    }

    func resolveCloneReferenceAudioURL(_ referenceAudioPath: String, requestID: String) throws -> URL {
        let resolvedURL = profileStore.resolveOutputURL(referenceAudioPath)

        guard resolvedURL.isFileURL else {
            throw WorkerError(
                code: .invalidRequest,
                message: "Clone request '\(requestID)' must reference local audio via a file URL or filesystem path. Received '\(referenceAudioPath)'."
            )
        }

        guard dependencies.fileManager.fileExists(atPath: resolvedURL.path) else {
            throw WorkerError(
                code: .filesystemError,
                message: "Clone request '\(requestID)' could not find reference audio at '\(resolvedURL.path)'."
            )
        }

        return resolvedURL
    }

    func requireLoadedCloneAudio(
        from url: URL,
        sampleRate: Int,
        requestID: String,
        pathLabel: String,
        op: String
    ) throws -> [Float] {
        let audio = try dependencies.loadAudioFloats(url, sampleRate)

        guard !audio.isEmpty else {
            throw WorkerError(
                code: .filesystemError,
                message: "Request '\(requestID)' could not load \(pathLabel) from '\(url.path)' at sample rate \(sampleRate) for operation '\(op)'. The file may be unreadable, unsupported, or empty."
            )
        }

        return audio
    }
}
