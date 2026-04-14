import Foundation

// MARK: - Voice Profile Support Logic

extension SpeakSwiftly.Runtime {
    func runBlockingFilesystemOperation<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T,
    ) async throws -> T {
        try await Task.detached(operation: operation).value
    }

    func canonicalAudioData(
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
