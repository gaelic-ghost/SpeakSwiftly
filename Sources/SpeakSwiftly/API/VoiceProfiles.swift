import Foundation

// MARK: - Voice Profile API

public extension SpeakSwiftly.Runtime {
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
}
