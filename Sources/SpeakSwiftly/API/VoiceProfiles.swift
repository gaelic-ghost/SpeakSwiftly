import Foundation

// MARK: - Voice Profile API

public extension SpeakSwiftly {
    struct Voices: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    nonisolated var voices: SpeakSwiftly.Voices {
        SpeakSwiftly.Voices(runtime: self)
    }
}

public extension SpeakSwiftly.Voices {
    func create(
        design named: SpeakSwiftly.Name,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voice voiceDescription: String,
        outputPath: String? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createProfile(
                id: id,
                profileName: named,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: FileManager.default.currentDirectoryPath
            )
        )
    }

    func create(
        clone named: SpeakSwiftly.Name,
        from referenceAudioURL: URL,
        vibe: SpeakSwiftly.Vibe,
        transcript: String? = nil,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createClone(
                id: id,
                profileName: named,
                referenceAudioPath: referenceAudioURL.path,
                vibe: vibe,
                transcript: transcript,
                cwd: FileManager.default.currentDirectoryPath
            )
        )
    }

    func list(id: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listProfiles(id: id))
    }

    func delete(
        named profileName: SpeakSwiftly.Name,
        id: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.removeProfile(id: id, profileName: profileName))
    }
}
