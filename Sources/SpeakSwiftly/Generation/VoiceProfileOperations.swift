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
            language: "English",
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

    private func runBlockingFilesystemOperation<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T,
    ) async throws -> T {
        try await Task.detached(operation: operation).value
    }

    private func rerollGeneratedProfile(
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
            language: "English",
            generationParameters: GenerationPolicy.profileParameters(for: storedProfile.manifest.sourceText),
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

        let canonicalAudioData = try await canonicalAudioData(
            from: audio,
            sampleRate: profileModel.sampleRate,
        )
        try Task.checkCancellation()

        await emitProgress(id: id, stage: .writingProfileAssets)
        let replaceStartedAt = dependencies.now()
        let profileStore = profileStore
        let rerolledProfile = try await runBlockingFilesystemOperation {
            try profileStore.replaceProfile(
                named: storedProfile.manifest.profileName,
                vibe: storedProfile.manifest.vibe,
                modelRepo: storedProfile.manifest.modelRepo,
                voiceDescription: storedProfile.manifest.voiceDescription,
                sourceText: storedProfile.manifest.sourceText,
                transcriptProvenance: storedProfile.manifest.transcriptProvenance,
                sampleRate: profileModel.sampleRate,
                canonicalAudioData: canonicalAudioData,
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
        return rerolledProfile
    }

    private func rerollImportedCloneProfile(
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
        let rerolledProfile = try await runBlockingFilesystemOperation {
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
        return rerolledProfile
    }

    private func canonicalAudioData(
        from audio: [Float],
        sampleRate: Int,
    ) async throws -> Data {
        let tempDirectory = dependencies.fileManager
            .temporaryDirectory
            .appendingPathComponent("SpeakSwiftly", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try dependencies.fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? dependencies.fileManager.removeItem(at: tempDirectory) }

        let tempWavURL = tempDirectory.appendingPathComponent(ProfileStore.audioFileName)
        let writeWAV = dependencies.writeWAV
        try await runBlockingFilesystemOperation {
            try writeWAV(audio, sampleRate, tempWavURL)
        }
        return try await runBlockingFilesystemOperation {
            try Data(contentsOf: tempWavURL)
        }
    }

    func resolvedCloneTranscript(
        requestID id: String,
        op: String,
        profileName: String,
        referenceAudioURL: URL,
        transcript: String?,
    ) async throws -> ResolvedCloneTranscript {
        if let transcript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty {
            return ResolvedCloneTranscript(
                text: transcript,
                provenance: TranscriptProvenance(
                    source: .provided,
                    createdAt: dependencies.now(),
                    transcriptionModelRepo: nil,
                ),
            )
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
            ],
        )
        defer {
            cloneTranscriptionModel = nil
        }
        try Task.checkCancellation()

        guard let cloneTranscriptionModel else {
            throw WorkerError(
                code: .internalError,
                message: "Clone request '\(id)' lost its transcription model before transcription started. This indicates a SpeakSwiftly runtime bug.",
            )
        }

        let transcriptionAudioLoadStartedAt = dependencies.now()
        let transcriptionAudio = try requireLoadedCloneAudio(
            from: referenceAudioURL,
            sampleRate: cloneTranscriptionModel.sampleRate,
            requestID: id,
            pathLabel: "clone transcription audio",
            op: op,
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
            ],
        )

        await emitProgress(id: id, stage: .transcribingCloneAudio)
        let transcriptionStartedAt = dependencies.now()
        let inferredTranscript = cloneTranscriptionModel
            .transcribe(
                audio: transcriptionAudio,
                generationParameters: GenerationPolicy.cloneTranscriptionParameters(),
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
            ],
        )

        guard !inferredTranscript.isEmpty else {
            throw WorkerError(
                code: .modelGenerationFailed,
                message: "Clone request '\(id)' could not infer a transcript from '\(referenceAudioURL.path)'. Provide 'transcript' explicitly or retry with clearer speech audio.",
            )
        }

        return ResolvedCloneTranscript(
            text: inferredTranscript,
            provenance: TranscriptProvenance(
                source: .inferred,
                createdAt: dependencies.now(),
                transcriptionModelRepo: ModelFactory.cloneTranscriptionModelRepo,
            ),
        )
    }

    func resolveCloneReferenceAudioURL(
        _ referenceAudioPath: String,
        cwd: String?,
        requestID: String,
    ) throws -> URL {
        let resolvedURL = try resolveFilesystemURL(
            referenceAudioPath,
            cwd: cwd,
            requestID: requestID,
            fieldName: "reference_audio_path",
            purpose: "clone reference audio",
        )

        guard dependencies.fileManager.fileExists(atPath: resolvedURL.path) else {
            throw WorkerError(
                code: .filesystemError,
                message: "Clone request '\(requestID)' could not find reference audio at '\(resolvedURL.path)'.",
            )
        }

        return resolvedURL
    }

    func resolveFilesystemURL(
        _ path: String,
        cwd: String?,
        requestID: String,
        fieldName: String,
        purpose: String,
    ) throws -> URL {
        if let explicitURL = URL(string: path), explicitURL.isFileURL {
            return explicitURL.standardizedFileURL
        }

        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        guard let cwd, !cwd.isEmpty else {
            throw WorkerError(
                code: .invalidRequest,
                message: "Request '\(requestID)' used relative '\(fieldName)' path '\(path)' for \(purpose), but did not provide 'cwd'. Send an absolute path or include the caller working directory so SpeakSwiftly can resolve the relative path explicitly.",
            )
        }

        let baseURL: URL
        if let explicitBaseURL = URL(string: cwd), explicitBaseURL.isFileURL {
            baseURL = explicitBaseURL.standardizedFileURL
        } else if cwd.hasPrefix("/") {
            baseURL = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        } else {
            throw WorkerError(
                code: .invalidRequest,
                message: "Request '\(requestID)' provided non-absolute 'cwd' value '\(cwd)' while resolving '\(fieldName)'. SpeakSwiftly requires 'cwd' to be an absolute filesystem path or file URL.",
            )
        }

        return baseURL.appendingPathComponent(path).standardizedFileURL
    }

    func requireLoadedCloneAudio(
        from url: URL,
        sampleRate: Int,
        requestID: String,
        pathLabel: String,
        op: String,
    ) throws -> [Float] {
        let audio = try dependencies.loadAudioFloats(url, sampleRate)

        guard !audio.isEmpty else {
            throw WorkerError(
                code: .filesystemError,
                message: "Request '\(requestID)' could not load \(pathLabel) from '\(url.path)' at sample rate \(sampleRate) for operation '\(op)'. The file may be unreadable, unsupported, or empty.",
            )
        }

        return audio
    }
}
