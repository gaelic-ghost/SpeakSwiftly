import Foundation

// MARK: - Voice Profile API

public extension SpeakSwiftly.Runtime {
    func createProfile(
        named profileName: String,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voice voiceDescription: String,
        outputPath: String? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(
            .createProfile(
                id: id,
                profileName: profileName,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: FileManager.default.currentDirectoryPath
            )
        )
    }

    func createClone(
        named profileName: String,
        from referenceAudioURL: URL,
        vibe: SpeakSwiftly.Vibe,
        transcript: String? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(
            .createClone(
                id: id,
                profileName: profileName,
                referenceAudioPath: referenceAudioURL.path,
                vibe: vibe,
                transcript: transcript,
                cwd: FileManager.default.currentDirectoryPath
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
}
