import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

private extension SpeakSwiftly.Normalizer {
    func builtInStyle() -> TextForSpeech.BuiltInProfileStyle {
        textRuntime.profiles.builtInStyle
    }

    func activeProfile() -> TextForSpeech.Profile {
        textRuntime.profiles.active()
    }

    func storedProfile(id: String) -> TextForSpeech.Profile? {
        textRuntime.profiles.stored(id: id)
    }

    func storedProfiles() -> [TextForSpeech.Profile] {
        textRuntime.profiles.list()
    }

    func effectiveProfile(id: String? = nil) -> TextForSpeech.Profile? {
        if let id {
            return textRuntime.profiles.effective(id: id)
        }

        return textRuntime.profiles.effective()
    }

    func activeReplacements() -> [TextForSpeech.Replacement] {
        textRuntime.profiles.active().replacements
    }

    func storedReplacements(id: String) -> [TextForSpeech.Replacement]? {
        textRuntime.profiles.stored(id: id)?.replacements
    }

    func setBuiltInStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) throws {
        try textRuntime.profiles.setBuiltInStyle(style)
    }

    func storeProfile(_ profile: TextForSpeech.Profile) throws {
        try textRuntime.profiles.store(profile)
    }

    func useProfile(_ profile: TextForSpeech.Profile) throws {
        try textRuntime.profiles.store(profile)
        try textRuntime.profiles.activate(id: profile.id)
    }

    func createProfile(
        id: String,
        name: String,
        replacements: [TextForSpeech.Replacement] = [],
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.create(
            id: id,
            name: name,
            replacements: replacements,
        )
    }

    func deleteProfile(id: String) throws {
        try textRuntime.profiles.delete(id: id)
    }

    func resetProfiles() throws {
        try textRuntime.profiles.reset()
    }

    func addReplacement(
        _ replacement: TextForSpeech.Replacement,
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement)
    }

    func addReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID id: String,
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement, toProfileID: id)
    }

    func replaceReplacement(
        _ replacement: TextForSpeech.Replacement,
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement)
    }

    func replaceReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileID id: String,
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement, inProfileID: id)
    }

    func removeReplacement(
        id replacementID: String,
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(id: replacementID)
    }

    func removeReplacement(
        id replacementID: String,
        fromStoredProfileID profileID: String,
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(
            id: replacementID,
            fromProfileID: profileID,
        )
    }

    func clearReplacements() throws -> TextForSpeech.Profile {
        var profile = textRuntime.profiles.active()
        for replacement in profile.replacements {
            profile = try textRuntime.profiles.removeReplacement(id: replacement.id)
        }
        return profile
    }

    func clearReplacements(
        fromStoredProfileID profileID: String,
    ) throws -> TextForSpeech.Profile {
        guard var profile = textRuntime.profiles.stored(id: profileID) else {
            throw TextForSpeech.RuntimeError.profileNotFound(profileID)
        }

        for replacement in profile.replacements {
            profile = try textRuntime.profiles.removeReplacement(
                id: replacement.id,
                fromProfileID: profileID,
            )
        }
        return profile
    }

    func persistenceURL() -> URL? {
        configuredPersistenceURL
    }

    func persistenceState() -> TextForSpeech.PersistedState {
        textRuntime.persistence.state
    }

    func restorePersistence(
        _ state: TextForSpeech.PersistedState,
    ) throws {
        try textRuntime.persistence.restore(state)
    }

    func loadPersistence() throws {
        try textRuntime.persistence.load()
    }

    func loadPersistence(from url: URL) throws {
        try textRuntime.persistence.load(from: url)
    }

    func savePersistence() throws {
        try textRuntime.persistence.save()
    }

    func savePersistence(to url: URL) throws {
        try textRuntime.persistence.save(to: url)
    }
}

public extension SpeakSwiftly.Normalizer.Profiles {
    /// Returns the built-in profile style currently applied before custom replacements.
    func builtInStyle() async -> TextForSpeech.BuiltInProfileStyle {
        await normalizer.builtInStyle()
    }

    /// Returns the active custom profile, or one stored profile by identifier.
    ///
    /// - Parameter id: An optional stored profile identifier to fetch directly.
    /// - Returns: The active profile when `id` is `nil`, otherwise the matching stored profile.
    func active(id: String? = nil) async -> TextForSpeech.Profile? {
        if let id {
            return await normalizer.storedProfile(id: id)
        }

        return await normalizer.activeProfile()
    }

    /// Returns one stored text profile by identifier.
    func stored(id: String) async -> TextForSpeech.Profile? {
        await normalizer.storedProfile(id: id)
    }

    /// Lists all stored text profiles known to the normalizer.
    func list() async -> [TextForSpeech.Profile] {
        await normalizer.storedProfiles()
    }

    /// Returns the effective profile after the built-in style and custom profile are merged.
    ///
    /// - Parameter id: An optional stored profile identifier to resolve instead of the active profile.
    func effective(id: String? = nil) async -> TextForSpeech.Profile? {
        await normalizer.effectiveProfile(id: id)
    }

    /// Returns the replacement rules on the active text profile.
    func replacements() async -> [TextForSpeech.Replacement] {
        await normalizer.activeReplacements()
    }

    /// Returns the replacement rules on one stored text profile.
    func replacements(
        inStoredProfileID id: String,
    ) async -> [TextForSpeech.Replacement]? {
        await normalizer.storedReplacements(id: id)
    }

    /// Changes the built-in style that shapes effective normalization output.
    func setBuiltInStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) async throws {
        try await normalizer.setBuiltInStyle(style)
    }

    /// Creates one stored text profile.
    ///
    /// - Parameters:
    ///   - id: The stable profile identifier.
    ///   - name: The human-readable profile name.
    ///   - replacements: Optional initial replacement rules.
    /// - Returns: The created profile.
    @discardableResult
    func create(
        id: String,
        name: String,
        replacements: [TextForSpeech.Replacement] = [],
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.createProfile(
            id: id,
            name: name,
            replacements: replacements,
        )
    }

    /// Stores a complete text profile without activating it.
    func store(_ profile: TextForSpeech.Profile) async throws {
        try await normalizer.storeProfile(profile)
    }

    /// Stores a complete text profile and makes it the active custom profile.
    func use(_ profile: TextForSpeech.Profile) async throws {
        try await normalizer.useProfile(profile)
    }

    /// Deletes one stored text profile.
    func delete(id: String) async throws {
        try await normalizer.deleteProfile(id: id)
    }

    /// Resets all text-profile state back to the runtime defaults.
    func reset() async throws {
        try await normalizer.resetProfiles()
    }

    /// Adds one replacement rule to the active text profile.
    @discardableResult
    func add(
        _ replacement: TextForSpeech.Replacement,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.addReplacement(replacement)
    }

    /// Adds one replacement rule to a stored text profile.
    @discardableResult
    func add(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID id: String,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.addReplacement(
            replacement,
            toStoredProfileID: id,
        )
    }

    /// Replaces one existing replacement rule on the active text profile.
    @discardableResult
    func replace(
        _ replacement: TextForSpeech.Replacement,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.replaceReplacement(replacement)
    }

    /// Replaces one existing replacement rule on a stored text profile.
    @discardableResult
    func replace(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileID id: String,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.replaceReplacement(
            replacement,
            inStoredProfileID: id,
        )
    }

    /// Removes one replacement rule from the active text profile.
    @discardableResult
    func removeReplacement(
        id replacementID: String,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.removeReplacement(id: replacementID)
    }

    /// Removes one replacement rule from a stored text profile.
    @discardableResult
    func removeReplacement(
        id replacementID: String,
        fromStoredProfileID profileID: String,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.removeReplacement(
            id: replacementID,
            fromStoredProfileID: profileID,
        )
    }

    /// Removes every replacement rule from the active text profile.
    @discardableResult
    func clearReplacements() async throws -> TextForSpeech.Profile {
        try await normalizer.clearReplacements()
    }

    /// Removes every replacement rule from a stored text profile.
    @discardableResult
    func clearReplacements(
        fromStoredProfileID profileID: String,
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.clearReplacements(
            fromStoredProfileID: profileID,
        )
    }
}

public extension SpeakSwiftly.Normalizer.Persistence {
    /// Returns the configured persistence URL used by this normalizer.
    func url() async -> URL? {
        await normalizer.persistenceURL()
    }

    /// Returns the full persisted-state snapshot currently held in memory.
    func state() async -> TextForSpeech.PersistedState {
        await normalizer.persistenceState()
    }

    /// Replaces the in-memory persistence state with a full provided snapshot.
    func restore(_ state: TextForSpeech.PersistedState) async throws {
        try await normalizer.restorePersistence(state)
    }

    /// Loads persisted text-profile state from the configured persistence location.
    func load() async throws {
        try await normalizer.loadPersistence()
    }

    /// Loads persisted text-profile state from a specific URL.
    func load(from url: URL) async throws {
        try await normalizer.loadPersistence(from: url)
    }

    /// Saves the current text-profile state to the configured persistence location.
    func save() async throws {
        try await normalizer.savePersistence()
    }

    /// Saves the current text-profile state to a specific URL.
    func save(to url: URL) async throws {
        try await normalizer.savePersistence(to: url)
    }
}
