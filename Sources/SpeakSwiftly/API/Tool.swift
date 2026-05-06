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
    // MARK: Output

    package func outputEvents() async -> AsyncStream<SpeakSwiftly.WorkerOutputEvent> {
        await runtime.workerOutputEvents()
    }

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

    /// Lists the playback queue using a caller-provided request identifier.
    func playbackQueue(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listQueue(id: requestID, queueType: .playback))
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

    // MARK: Text Profiles

    /// Retrieves the active text profile using a caller-provided request identifier.
    func activeTextProfile(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.textProfileActive(id: requestID))
    }

    /// Retrieves one text profile using a caller-provided request identifier.
    func textProfile(
        requestID: String,
        profileID: SpeakSwiftly.TextProfileID,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.textProfile(id: requestID, profileID: profileID))
    }

    /// Lists text profiles using a caller-provided request identifier.
    func textProfiles(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.textProfiles(id: requestID))
    }

    /// Retrieves the active text-profile style using a caller-provided request identifier.
    func activeTextProfileStyle(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.activeTextProfileStyle(id: requestID))
    }

    /// Lists available text-profile styles using a caller-provided request identifier.
    func textProfileStyles(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.textProfileStyleOptions(id: requestID))
    }

    /// Retrieves the effective text profile using a caller-provided request identifier.
    func effectiveTextProfile(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.textProfileEffective(id: requestID))
    }

    /// Retrieves text-profile persistence details using a caller-provided request identifier.
    func textProfilePersistence(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.textProfilePersistence(id: requestID))
    }

    /// Loads text profiles from persistence using a caller-provided request identifier.
    func loadTextProfiles(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.loadTextProfiles(id: requestID))
    }

    /// Saves text profiles to persistence using a caller-provided request identifier.
    func saveTextProfiles(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.saveTextProfiles(id: requestID))
    }

    /// Sets the active text-profile style using a caller-provided request identifier.
    func setActiveTextProfileStyle(
        requestID: String,
        to style: TextForSpeech.BuiltInProfileStyle,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.setActiveTextProfileStyle(id: requestID, style: style))
    }

    /// Creates a text profile using a caller-provided request identifier.
    func createTextProfile(
        requestID: String,
        name profileName: String,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.createTextProfile(id: requestID, profileName: profileName))
    }

    /// Renames a text profile using a caller-provided request identifier.
    func renameTextProfile(
        requestID: String,
        profileID: SpeakSwiftly.TextProfileID,
        to profileName: String,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .renameTextProfile(
                id: requestID,
                profileID: profileID,
                profileName: profileName,
            ),
        )
    }

    /// Sets the active text profile using a caller-provided request identifier.
    func setActiveTextProfile(
        requestID: String,
        profileID: SpeakSwiftly.TextProfileID,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.setActiveTextProfile(id: requestID, profileID: profileID))
    }

    /// Deletes a text profile using a caller-provided request identifier.
    func deleteTextProfile(
        requestID: String,
        profileID: SpeakSwiftly.TextProfileID,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.deleteTextProfile(id: requestID, profileID: profileID))
    }

    /// Restores all text profiles to package defaults using a caller-provided request identifier.
    func factoryResetTextProfiles(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.factoryResetTextProfiles(id: requestID))
    }

    /// Resets one text profile using a caller-provided request identifier.
    func resetTextProfile(
        requestID: String,
        profileID: SpeakSwiftly.TextProfileID,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.resetTextProfile(id: requestID, profileID: profileID))
    }

    /// Adds a text replacement using a caller-provided request identifier.
    func addTextReplacement(
        requestID: String,
        _ replacement: TextForSpeech.Replacement,
        profileID: SpeakSwiftly.TextProfileID? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .addTextReplacement(
                id: requestID,
                replacement: replacement,
                profileID: profileID,
            ),
        )
    }

    /// Replaces a text replacement using a caller-provided request identifier.
    func replaceTextReplacement(
        requestID: String,
        _ replacement: TextForSpeech.Replacement,
        profileID: SpeakSwiftly.TextProfileID? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .replaceTextReplacement(
                id: requestID,
                replacement: replacement,
                profileID: profileID,
            ),
        )
    }

    /// Removes a text replacement using a caller-provided request identifier.
    func deleteTextReplacement(
        requestID: String,
        replacementID: String,
        profileID: SpeakSwiftly.TextProfileID? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .removeTextReplacement(
                id: requestID,
                replacementID: replacementID,
                profileID: profileID,
            ),
        )
    }

    // MARK: Runtime and Queues

    /// Retrieves the runtime status event using a caller-provided request identifier.
    func status(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.status(id: requestID))
    }

    /// Retrieves the runtime overview using a caller-provided request identifier.
    func overview(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.overview(id: requestID))
    }

    /// Retrieves the default voice profile using a caller-provided request identifier.
    func defaultVoiceProfile(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.defaultVoiceProfile(id: requestID))
    }

    /// Sets the default voice profile using a caller-provided request identifier.
    func setDefaultVoiceProfile(
        requestID: String,
        to profileName: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.setDefaultVoiceProfile(id: requestID, profileName: profileName))
    }

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

    /// Retrieves playback state using a caller-provided request identifier.
    func playbackState(requestID: String) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.playback(id: requestID, action: .state))
    }
}
