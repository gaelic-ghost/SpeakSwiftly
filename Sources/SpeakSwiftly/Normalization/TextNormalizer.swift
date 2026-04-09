import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

extension SpeakSwiftly.Normalizer {
    fileprivate func activeProfile(id: String? = nil) -> TextForSpeech.Profile? {
        textRuntime.profiles.active(id: id)
    }

    fileprivate func storedProfile(id: String) -> TextForSpeech.Profile? {
        textRuntime.profiles.stored(id: id)
    }

    fileprivate func storedProfiles() -> [TextForSpeech.Profile] {
        textRuntime.profiles.list()
    }

    fileprivate func effectiveProfile(id: String? = nil) -> TextForSpeech.Profile? {
        textRuntime.profiles.effective(id: id)
    }

    fileprivate func storeProfile(_ profile: TextForSpeech.Profile) {
        textRuntime.profiles.store(profile)
    }

    fileprivate func useProfile(_ profile: TextForSpeech.Profile) {
        textRuntime.profiles.use(profile)
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

    fileprivate func deleteProfile(id: String) {
        textRuntime.profiles.delete(id: id)
    }

    fileprivate func resetProfiles() {
        textRuntime.profiles.reset()
    }

    fileprivate func addReplacement(
        _ replacement: TextForSpeech.Replacement
    ) -> TextForSpeech.Profile {
        textRuntime.profiles.add(replacement)
    }

    fileprivate func addReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID id: String
    ) throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement, toStoredProfileID: id)
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
        try textRuntime.profiles.replace(replacement, inStoredProfileID: id)
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
            fromStoredProfileID: profileID
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
        await normalizer.activeProfile(id: id)
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
        let profile = try await normalizer.createProfile(
            id: id,
            name: name,
            replacements: replacements
        )
        try await normalizer.savePersistence()
        return profile
    }

    func store(_ profile: TextForSpeech.Profile) async throws {
        await normalizer.storeProfile(profile)
        try await normalizer.savePersistence()
    }

    func use(_ profile: TextForSpeech.Profile) async throws {
        await normalizer.useProfile(profile)
        try await normalizer.savePersistence()
    }

    func delete(id: String) async throws {
        await normalizer.deleteProfile(id: id)
        try await normalizer.savePersistence()
    }

    func reset() async throws {
        await normalizer.resetProfiles()
        try await normalizer.savePersistence()
    }

    @discardableResult
    func add(
        _ replacement: TextForSpeech.Replacement
    ) async throws -> TextForSpeech.Profile {
        let profile = await normalizer.addReplacement(replacement)
        try await normalizer.savePersistence()
        return profile
    }

    @discardableResult
    func add(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID id: String
    ) async throws -> TextForSpeech.Profile {
        let profile = try await normalizer.addReplacement(
            replacement,
            toStoredProfileID: id
        )
        try await normalizer.savePersistence()
        return profile
    }

    @discardableResult
    func replace(
        _ replacement: TextForSpeech.Replacement
    ) async throws -> TextForSpeech.Profile {
        let profile = try await normalizer.replaceReplacement(replacement)
        try await normalizer.savePersistence()
        return profile
    }

    @discardableResult
    func replace(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileID id: String
    ) async throws -> TextForSpeech.Profile {
        let profile = try await normalizer.replaceReplacement(
            replacement,
            inStoredProfileID: id
        )
        try await normalizer.savePersistence()
        return profile
    }

    @discardableResult
    func removeReplacement(
        id replacementID: String
    ) async throws -> TextForSpeech.Profile {
        let profile = try await normalizer.removeReplacement(id: replacementID)
        try await normalizer.savePersistence()
        return profile
    }

    @discardableResult
    func removeReplacement(
        id replacementID: String,
        fromStoredProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        let profile = try await normalizer.removeReplacement(
            id: replacementID,
            fromStoredProfileID: profileID
        )
        try await normalizer.savePersistence()
        return profile
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
