import Foundation

extension SpeakSwiftly.Normalizer {
    static func validate(_ state: SpeakSwiftly.TextNormalizationState) throws {
        guard state.version == Versioning.currentPersistedStateVersion else {
            throw SpeakSwiftly.TextNormalizationPersistenceError.unsupportedPersistedStateVersion(state.version)
        }
    }

    static func loadState(from url: URL) throws -> SpeakSwiftly.TextNormalizationState {
        let fileURL = url.standardizedFileURL
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SpeakSwiftly.TextNormalizationPersistenceError.couldNotRead(
                fileURL,
                error.localizedDescription,
            )
        }

        do {
            return try JSONDecoder().decode(SpeakSwiftly.TextNormalizationState.self, from: data)
        } catch {
            throw SpeakSwiftly.TextNormalizationPersistenceError.couldNotDecode(
                fileURL,
                error.localizedDescription,
            )
        }
    }

    static func writeState(
        _ state: SpeakSwiftly.TextNormalizationState,
        to url: URL,
        fileManager: FileManager,
    ) throws {
        let fileURL = url.standardizedFileURL
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw SpeakSwiftly.TextNormalizationPersistenceError.couldNotCreateDirectory(
                directoryURL,
                error.localizedDescription,
            )
        }

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(state)
        } catch {
            throw SpeakSwiftly.TextNormalizationPersistenceError.couldNotWrite(
                fileURL,
                "SpeakSwiftly could not encode text-normalization state before writing it. \(error.localizedDescription)",
            )
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SpeakSwiftly.TextNormalizationPersistenceError.couldNotWrite(
                fileURL,
                error.localizedDescription,
            )
        }
    }

    func persistenceState() -> SpeakSwiftly.TextNormalizationState {
        SpeakSwiftly.TextNormalizationState(
            version: Self.Versioning.currentPersistedStateVersion,
            builtInStyle: builtInStyle,
            summarizationProvider: activeSummarizationProvider,
            activeCustomProfileID: activeCustomProfileID,
            profiles: storedCustomProfilesByID,
        )
    }

    func restorePersistence(_ state: SpeakSwiftly.TextNormalizationState) throws {
        try Self.validate(state)
        builtInStyle = state.builtInStyle
        activeSummarizationProvider = state.summarizationProvider
        activeCustomProfileID = state.activeCustomProfileID
        storedCustomProfilesByID = state.profiles
        repairProfileState()
    }

    func loadPersistence(from url: URL? = nil) throws {
        let fileURL = (url ?? configuredPersistenceURL).standardizedFileURL
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        try restorePersistence(Self.loadState(from: fileURL))
    }

    func savePersistence(to url: URL? = nil) throws {
        try Self.writeState(
            persistenceState(),
            to: url ?? configuredPersistenceURL,
            fileManager: fileManager,
        )
    }
}

public extension SpeakSwiftly.Normalizer.Persistence {
    /// Returns the configured persistence URL used by this normalizer.
    func url() async -> URL? { normalizer.configuredPersistenceURL }

    /// Returns the complete persisted-state snapshot currently held in memory.
    func state() async -> SpeakSwiftly.TextNormalizationState {
        await normalizer.persistenceState()
    }

    /// Replaces in-memory text-normalization state with a validated snapshot.
    func restore(_ state: SpeakSwiftly.TextNormalizationState) async throws {
        try await normalizer.restorePersistence(state)
    }

    /// Loads text-normalization state from the configured location.
    func load() async throws { try await normalizer.loadPersistence() }

    /// Loads text-normalization state from a selected location.
    func load(from url: URL) async throws { try await normalizer.loadPersistence(from: url) }

    /// Saves text-normalization state to the configured location.
    func save() async throws { try await normalizer.savePersistence() }

    /// Saves text-normalization state to a selected location.
    func save(to url: URL) async throws { try await normalizer.savePersistence(to: url) }
}
