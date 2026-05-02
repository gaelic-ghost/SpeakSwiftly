import Foundation

public extension SpeakSwiftly {
    // MARK: Voices Handle

    /// Manages stored voice profiles.
    struct Voices: Sendable {
        let runtime: SpeakSwiftly.Runtime
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Accessors

    /// Returns the voice-profile management surface for this runtime.
    nonisolated var voices: SpeakSwiftly.Voices {
        SpeakSwiftly.Voices(runtime: self)
    }
}

public extension SpeakSwiftly.Voices {
    // MARK: Operations

    /// Creates a stored voice-design profile from source text and a voice description.
    ///
    /// - Parameters:
    ///   - named: The stable stored profile name to create.
    ///   - text: The source text used to condition the design request.
    ///   - vibe: The broad vocal presentation to request.
    ///   - voiceDescription: The descriptive prompt that shapes the generated voice.
    ///   - outputPath: An optional file path where SpeakSwiftly should export the
    ///     generated reference audio after storing the profile.
    /// - Returns: A request handle for the queued creation request.
    func create(
        design named: SpeakSwiftly.Name,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voice voiceDescription: String,
        outputPath: String? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createProfile(
                id: UUID().uuidString,
                profileName: named,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                author: .user,
                seed: nil,
                outputPath: outputPath,
                cwd: FileManager.default.currentDirectoryPath,
            ),
        )
    }

    /// Creates a package-owned voice-design profile from trusted seed metadata.
    ///
    /// - Parameters:
    ///   - named: The stored profile name to create.
    ///   - text: The source text used to condition the design request.
    ///   - vibe: The broad vocal presentation to request.
    ///   - voiceDescription: The descriptive prompt that shapes the generated voice.
    ///   - seed: Stable package seed metadata used for provenance and refresh decisions.
    ///   - outputPath: An optional file path where SpeakSwiftly should export the
    ///     generated reference audio after storing the profile.
    /// - Returns: A request handle for the queued creation request.
    func create(
        systemDesign named: SpeakSwiftly.Name,
        from text: String,
        vibe: SpeakSwiftly.Vibe,
        voice voiceDescription: String,
        seed: SpeakSwiftly.ProfileSeed,
        outputPath: String? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createProfile(
                id: UUID().uuidString,
                profileName: named,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                author: .system,
                seed: seed,
                outputPath: outputPath,
                cwd: FileManager.default.currentDirectoryPath,
            ),
        )
    }

    /// Creates a stored voice-clone profile from reference audio.
    ///
    /// - Parameters:
    ///   - named: The stable stored profile name to create.
    ///   - referenceAudioURL: The audio file to clone from.
    ///   - vibe: The broad vocal presentation to preserve or steer toward.
    ///   - transcript: Optional transcript text for the reference audio.
    /// - Returns: A request handle for the queued clone request.
    func create(
        clone named: SpeakSwiftly.Name,
        from referenceAudioURL: URL,
        vibe: SpeakSwiftly.Vibe,
        transcript: String? = nil,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .createClone(
                id: UUID().uuidString,
                profileName: named,
                referenceAudioPath: referenceAudioURL.path,
                vibe: vibe,
                transcript: transcript,
                cwd: FileManager.default.currentDirectoryPath,
            ),
        )
    }

    /// Lists the stored voice profiles known to the runtime.
    ///
    /// - Returns: A request handle whose terminal success payload includes stored profiles.
    func list() async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.listProfiles(id: UUID().uuidString))
    }

    /// Renames a stored voice profile.
    ///
    /// - Parameters:
    ///   - profileName: The existing stored profile name.
    ///   - newProfileName: The new stored profile name to assign.
    /// - Returns: A request handle for the rename request.
    func rename(
        _ profileName: SpeakSwiftly.Name,
        to newProfileName: SpeakSwiftly.Name,
    ) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .renameProfile(
                id: UUID().uuidString,
                profileName: profileName,
                newProfileName: newProfileName,
            ),
        )
    }

    /// Rebuilds a stored voice profile from its persisted source inputs.
    ///
    /// - Parameter profileName: The stored profile to rebuild.
    /// - Returns: A request handle for the reroll request.
    func reroll(_ profileName: SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(
            .rerollProfile(
                id: UUID().uuidString,
                profileName: profileName,
            ),
        )
    }

    /// Deletes a stored voice profile.
    ///
    /// - Parameter profileName: The stored profile name to remove.
    /// - Returns: A request handle for the delete request.
    func delete(named profileName: SpeakSwiftly.Name) async -> SpeakSwiftly.RequestHandle {
        await runtime.submit(.removeProfile(id: UUID().uuidString, profileName: profileName))
    }
}
