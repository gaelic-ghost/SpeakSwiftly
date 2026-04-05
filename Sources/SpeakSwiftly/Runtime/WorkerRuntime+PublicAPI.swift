import Foundation
import TextForSpeech

// MARK: - Runtime Public API

public extension SpeakSwiftly.Runtime {
    func speak(
        text: String,
        with profileName: String,
        as job: SpeakSwiftly.Job,
        textProfileName: String? = nil,
        textContext: TextForSpeech.Context? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(
            .queueSpeech(
                id: id,
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                jobType: job,
                textContext: textContext
            )
        )
    }

    func activeTextProfile() -> TextForSpeech.Profile {
        textRuntime.customProfile
    }

    func baseTextProfile() -> TextForSpeech.Profile {
        textRuntime.baseProfile
    }

    func textProfile(named name: String) -> TextForSpeech.Profile? {
        textRuntime.profile(named: name)
    }

    func textProfiles() -> [TextForSpeech.Profile] {
        textRuntime.storedProfiles()
    }

    func effectiveTextProfile(named name: String? = nil) -> TextForSpeech.Profile {
        textRuntime.snapshot(named: name)
    }

    func textProfilePersistenceURL() -> URL? {
        textRuntime.persistenceURL
    }

    func loadTextProfiles() throws {
        try textRuntime.load()
    }

    func saveTextProfiles() throws {
        try textRuntime.save()
    }

    func createTextProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement] = []
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.createProfile(
            id: id,
            named: name,
            replacements: replacements
        )
        try textRuntime.save()
        return profile
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) throws {
        textRuntime.store(profile)
        try textRuntime.save()
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) throws {
        textRuntime.use(profile)
        try textRuntime.save()
    }

    func removeTextProfile(named name: String) throws {
        textRuntime.removeProfile(named: name)
        try textRuntime.save()
    }

    func resetTextProfile() throws {
        textRuntime.reset()
        try textRuntime.save()
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = textRuntime.addReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.addReplacement(replacement, toStoredProfileNamed: name)
        try textRuntime.save()
        return profile
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement, inStoredProfileNamed: name)
        try textRuntime.save()
        return profile
    }

    func removeTextReplacement(
        id replacementID: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.removeReplacement(id: replacementID)
        try textRuntime.save()
        return profile
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.removeReplacement(
            id: replacementID,
            fromStoredProfileNamed: name
        )
        try textRuntime.save()
        return profile
    }

    func createProfile(
        named profileName: String,
        from text: String,
        voice voiceDescription: String,
        outputPath: String? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(
            .createProfile(
                id: id,
                profileName: profileName,
                text: text,
                voiceDescription: voiceDescription,
                outputPath: outputPath
            )
        )
    }

    func createClone(
        named profileName: String,
        from referenceAudioURL: URL,
        transcript: String? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(
            .createClone(
                id: id,
                profileName: profileName,
                referenceAudioPath: referenceAudioURL.path,
                transcript: transcript
            )
        )
    }

    func profiles(id: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await submit(.listProfiles(id: id))
    }

    func removeProfile(
        named profileName: String,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.removeProfile(id: id, profileName: profileName))
    }

    func queue(
        _ queueType: SpeakSwiftly.Queue,
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.listQueue(id: requestID, queueType: queueType))
    }

    func playback(
        _ action: SpeakSwiftly.PlaybackAction,
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.playback(id: requestID, action: action))
    }

    func clearQueue(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await submit(.clearQueue(id: requestID))
    }

    func cancelRequest(
        _ id: String,
        requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.cancelRequest(id: requestID, requestID: id))
    }

    func shutdown() async {
        guard !isShuttingDown else { return }

        isShuttingDown = true
        preloadTask?.cancel()

        let cancellationError = WorkerError(
            code: .requestCancelled,
            message: "The request was cancelled because the SpeakSwiftly worker is shutting down."
        )

        if let activeGeneration {
            self.activeGeneration = nil
            activeGeneration.task.cancel()
            failRequestStream(for: activeGeneration.request.id, error: cancellationError)
            requestAcceptedAt.removeValue(forKey: activeGeneration.request.id)
            await emitFailure(id: activeGeneration.request.id, error: cancellationError)
        }

        if let activePlayback {
            self.activePlayback = nil
            activePlayback.task.cancel()
        }

        await failQueuedRequests(with: cancellationError)
        await failWaitingPlaybackRequests(with: cancellationError)
        await playbackController.stop()
        await logEvent("worker_shutdown_completed", details: ["queue_depth": .int(await generationQueueDepth())])
    }
}
