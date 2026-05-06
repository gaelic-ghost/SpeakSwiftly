import Foundation
import TextForSpeech

public extension SpeakSwiftly {
    /// Staging API used by the bundled JSONL executable while it moves onto
    /// the same typed runtime surface as ordinary Swift package consumers.
    struct Tool: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Tool Adapter Accessor

    /// Returns the request-ID-preserving adapter surface for `SpeakSwiftlyTool`.
    nonisolated var tool: SpeakSwiftly.Tool {
        SpeakSwiftly.Tool(runtime: self)
    }
}

public extension SpeakSwiftly.Tool {
    // MARK: Generation

    /// Queues live speech playback using a caller-provided request identifier.
    func speech(
        requestID: String,
        text: String,
        voiceProfile: SpeakSwiftly.Name? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
    ) async -> SpeakSwiftly.RequestHandle {
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueSpeech(
                id: requestID,
                text: text,
                profileName: resolvedVoiceProfile,
                textProfileID: textProfile,
                jobType: .live,
                sourceFormat: sourceFormat,
                requestContext: requestContext,
                qwenPreModelTextChunking: qwenPreModelTextChunking,
            ),
        )
    }

    /// Queues retained audio-file generation using a caller-provided request identifier.
    func audio(
        requestID: String,
        text: String,
        voiceProfile: SpeakSwiftly.Name? = nil,
        textProfile: SpeakSwiftly.TextProfileID? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueSpeech(
                id: requestID,
                text: text,
                profileName: resolvedVoiceProfile,
                textProfileID: textProfile,
                jobType: .file,
                sourceFormat: sourceFormat,
                requestContext: requestContext,
                qwenPreModelTextChunking: nil,
            ),
        )
    }

    /// Queues retained batch generation using a caller-provided request identifier.
    func batch(
        requestID: String,
        _ items: [SpeakSwiftly.BatchItem],
        voiceProfile: SpeakSwiftly.Name? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        let resolvedVoiceProfile = await runtime.resolveGenerationVoiceProfile(voiceProfile)
        return await runtime.submit(
            .queueBatch(
                id: requestID,
                profileName: resolvedVoiceProfile,
                items: SpeakSwiftly.Runtime.resolveBatchItems(items, batchID: requestID),
            ),
        )
    }

    // MARK: Artifacts and Jobs

    /// Retrieves one retained generated artifact using a caller-provided request identifier.
    func artifact(
        requestID: String,
        artifactID: String,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFile(id: requestID, artifactID: artifactID))
    }

    /// Lists retained generated artifacts using a caller-provided request identifier.
    func artifacts(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedFiles(id: requestID))
    }

    /// Retrieves one retained batch-generation job using a caller-provided request identifier.
    func generatedBatch(
        requestID: String,
        batchID: String,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedBatch(id: requestID, batchID: batchID))
    }

    /// Lists retained batch-generation jobs using a caller-provided request identifier.
    func generatedBatches(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generatedBatches(id: requestID))
    }

    /// Expires a retained generation job using a caller-provided request identifier.
    func expireGenerationJob(
        requestID: String,
        jobID: String,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.expireGenerationJob(id: requestID, jobID: jobID))
    }

    /// Retrieves a retained generation job using a caller-provided request identifier.
    func generationJob(
        requestID: String,
        jobID: String,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generationJob(id: requestID, jobID: jobID))
    }

    /// Lists retained generation jobs using a caller-provided request identifier.
    func generationJobs(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.generationJobs(id: requestID))
    }

    /// Lists the generation queue using a caller-provided request identifier.
    func generationQueue(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: requestID, queueType: .generation))
    }

    // MARK: Voice Profiles

    /// Creates a voice-design profile using a caller-provided request identifier.
    func createVoiceProfile(
        requestID: String,
        design named: SpeakSwiftly.Name,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = FileManager.default.currentDirectoryPath,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createProfile(
                id: requestID,
                profileName: named,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                author: .user,
                seed: nil,
                outputPath: outputPath,
                cwd: cwd,
            ),
        )
    }

    /// Creates a built-in voice-design profile using a caller-provided request identifier.
    func createBuiltInVoiceProfile(
        requestID: String,
        design named: SpeakSwiftly.Name,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        seed: SpeakSwiftly.ProfileSeed,
        outputPath: String? = nil,
        cwd: String? = FileManager.default.currentDirectoryPath,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createProfile(
                id: requestID,
                profileName: named,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                author: .system,
                seed: seed,
                outputPath: outputPath,
                cwd: cwd,
            ),
        )
    }

    /// Creates a voice-clone profile using a caller-provided request identifier.
    func createVoiceProfile(
        requestID: String,
        clone named: SpeakSwiftly.Name,
        from referenceAudioURL: URL,
        vibe: SpeakSwiftly.Vibe,
        transcript: String? = nil,
        cwd: String? = FileManager.default.currentDirectoryPath,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createClone(
                id: requestID,
                profileName: named,
                referenceAudioPath: referenceAudioURL.path,
                vibe: vibe,
                transcript: transcript,
                cwd: cwd,
            ),
        )
    }

    /// Lists voice profiles using a caller-provided request identifier.
    func voiceProfiles(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listProfiles(id: requestID))
    }

    /// Renames a voice profile using a caller-provided request identifier.
    func renameVoiceProfile(
        requestID: String,
        _ profileName: SpeakSwiftly.Name,
        to newProfileName: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .renameProfile(
                id: requestID,
                profileName: profileName,
                newProfileName: newProfileName,
            ),
        )
    }

    /// Rerolls a voice profile using a caller-provided request identifier.
    func rerollVoiceProfile(
        requestID: String,
        _ profileName: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.rerollProfile(id: requestID, profileName: profileName))
    }

    /// Deletes a voice profile using a caller-provided request identifier.
    func deleteVoiceProfile(
        requestID: String,
        named profileName: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.removeProfile(id: requestID, profileName: profileName))
    }

    // MARK: Runtime and Queues

    /// Switches the active speech backend using a caller-provided request identifier.
    func switchSpeechBackend(
        requestID: String,
        to speechBackend: SpeakSwiftly.SpeechBackend,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.switchSpeechBackend(id: requestID, speechBackend: speechBackend))
    }

    /// Reloads resident speech models using a caller-provided request identifier.
    func reloadModels(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.reloadModels(id: requestID))
    }

    /// Unloads resident speech models using a caller-provided request identifier.
    func unloadModels(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.unloadModels(id: requestID))
    }

    /// Clears one or both queues using a caller-provided request identifier.
    func clearQueue(
        requestID: String,
        queueType: SpeakSwiftly.QueueType? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.clearQueue(id: requestID, queueType: queueType))
    }

    /// Cancels one request using a caller-provided request identifier.
    func cancelRequest(
        requestID: String,
        targetRequestID: String,
        queueType: SpeakSwiftly.QueueType? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .cancelRequest(
                id: requestID,
                requestID: targetRequestID,
                queueType: queueType,
            ),
        )
    }

    // MARK: Playback

    /// Pauses live playback using a caller-provided request identifier.
    func pausePlayback(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: requestID, action: .pause))
    }

    /// Resumes live playback using a caller-provided request identifier.
    func resumePlayback(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: requestID, action: .resume))
    }
}
