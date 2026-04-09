import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

extension SpeakSwiftly.Normalizer {
    fileprivate func activeProfile() -> TextForSpeech.Profile {
        textRuntime.profiles.active()
    }

    fileprivate func storedProfile(id: String) -> TextForSpeech.Profile? {
        textRuntime.profiles.stored(id: id)
    }

    fileprivate func storedProfiles() -> [TextForSpeech.Profile] {
        textRuntime.profiles.list()
    }

    fileprivate func effectiveProfile(id: String? = nil) -> TextForSpeech.Profile? {
        if let id {
            return textRuntime.profiles.effective(id: id)
        }

        return textRuntime.profiles.effective()
    }

    fileprivate func storeProfile(_ profile: TextForSpeech.Profile) throws {
        try textRuntime.profiles.store(profile)
    }

    fileprivate func useProfile(_ profile: TextForSpeech.Profile) throws {
        try textRuntime.profiles.store(profile)
        try textRuntime.profiles.activate(id: profile.id)
    }

    fileprivate func createProfile(
        id: String,
        name: String,
        replacements: [TextForSpeech.Replacement] = []
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.create(
            id: id,
            name: name,
            replacements: replacements
        )
    }

    fileprivate func deleteProfile(id: String) throws {
        try textRuntime.profiles.delete(id: id)
    }

    fileprivate func resetProfiles() throws {
        try textRuntime.profiles.reset()
    }

    fileprivate func addReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement)
    }

    fileprivate func addReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID id: String
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement, toProfileID: id)
    }

    fileprivate func replaceReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement)
    }

    fileprivate func replaceReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileID id: String
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement, inProfileID: id)
    }

    fileprivate func removeReplacement(
        id replacementID: String
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(id: replacementID)
    }

    fileprivate func removeReplacement(
        id replacementID: String,
        fromStoredProfileID profileID: String
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(
            id: replacementID,
            fromProfileID: profileID
        )
    }

    fileprivate func persistenceURL() -> URL? {
        textRuntime.persistenceURL
    }

    fileprivate func persistenceState() -> TextForSpeech.PersistedState {
        textRuntime.persistence.state
    }

    fileprivate func restorePersistence(
        _ state: TextForSpeech.PersistedState
    ) throws {
        try textRuntime.persistence.restore(state)
    }

    fileprivate func loadPersistence() throws {
        try textRuntime.persistence.load()
    }

    fileprivate func loadPersistence(from url: URL) throws {
        try textRuntime.persistence.load(from: url)
    }

    fileprivate func savePersistence() throws {
        try textRuntime.persistence.save()
    }

    fileprivate func savePersistence(to url: URL) throws {
        try textRuntime.persistence.save(to: url)
    }
}

public extension SpeakSwiftly.Normalizer.Profiles {
    func active(id: String? = nil) async -> TextForSpeech.Profile? {
        if let id {
            return await normalizer.storedProfile(id: id)
        }

        return await normalizer.activeProfile()
    }

    func stored(id: String) async -> TextForSpeech.Profile? {
        await normalizer.storedProfile(id: id)
    }

    func list() async -> [TextForSpeech.Profile] {
        await normalizer.storedProfiles()
    }

    func effective(id: String? = nil) async -> TextForSpeech.Profile? {
        await normalizer.effectiveProfile(id: id)
    }

    @discardableResult
    func create(
        id: String,
        name: String,
        replacements: [TextForSpeech.Replacement] = []
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.createProfile(
            id: id,
            name: name,
            replacements: replacements
        )
    }

    func store(_ profile: TextForSpeech.Profile) async throws {
        try await normalizer.storeProfile(profile)
    }

    func use(_ profile: TextForSpeech.Profile) async throws {
        try await normalizer.useProfile(profile)
    }

    func delete(id: String) async throws {
        try await normalizer.deleteProfile(id: id)
    }

    func reset() async throws {
        try await normalizer.resetProfiles()
    }

    @discardableResult
    func add(
        _ replacement: TextForSpeech.Replacement
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.addReplacement(replacement)
    }

    @discardableResult
    func add(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID id: String
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.addReplacement(
            replacement,
            toStoredProfileID: id
        )
    }

    @discardableResult
    func replace(
        _ replacement: TextForSpeech.Replacement
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.replaceReplacement(replacement)
    }

    @discardableResult
    func replace(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileID id: String
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.replaceReplacement(
            replacement,
            inStoredProfileID: id
        )
    }

    @discardableResult
    func removeReplacement(
        id replacementID: String
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.removeReplacement(id: replacementID)
    }

    @discardableResult
    func removeReplacement(
        id replacementID: String,
        fromStoredProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await normalizer.removeReplacement(
            id: replacementID,
            fromStoredProfileID: profileID
        )
    }
}

public extension SpeakSwiftly.Normalizer.Persistence {
    func url() async -> URL? {
        await normalizer.persistenceURL()
    }

    func state() async -> TextForSpeech.PersistedState {
        await normalizer.persistenceState()
    }

    func restore(_ state: TextForSpeech.PersistedState) async throws {
        try await normalizer.restorePersistence(state)
    }

    func load() async throws {
        try await normalizer.loadPersistence()
    }

    func load(from url: URL) async throws {
        try await normalizer.loadPersistence(from: url)
    }

    func save() async throws {
        try await normalizer.savePersistence()
    }

    func save(to url: URL) async throws {
        try await normalizer.savePersistence(to: url)
    }
}
