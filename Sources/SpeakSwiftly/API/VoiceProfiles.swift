import Foundation

// MARK: - Voice Profile API

public extension SpeakSwiftly {
    // MARK: Voices Handle

    struct Voices: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    nonisolated var voices: SpeakSwiftly.Voices {
        SpeakSwiftly.Voices(runtime: self)
    }
}

public extension SpeakSwiftly.Voices {
    // MARK: Operations

    func create(
        design named: SpeakSwiftly.Name,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voice voiceDescription: String,
        outputPath: String? = nil
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createProfile(
                id: UUID().uuidString,
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
        transcript: String? = nil
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createClone(
                id: UUID().uuidString,
                profileName: named,
                referenceAudioPath: referenceAudioURL.path,
                vibe: vibe,
                transcript: transcript,
                cwd: FileManager.default.currentDirectoryPath
            )
        )
    }

    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listProfiles(id: UUID().uuidString))
    }

    func delete(named profileName: SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.removeProfile(id: UUID().uuidString, profileName: profileName))
    }
}
