import Foundation
import TextForSpeech

private extension SpeakSwiftly.Normalizer {
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
