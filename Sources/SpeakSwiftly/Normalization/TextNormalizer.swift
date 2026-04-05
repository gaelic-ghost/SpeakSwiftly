import Foundation
import TextForSpeech

// MARK: - Public Normalizer

public extension SpeakSwiftly {
    struct Normalizer: Sendable {
        let runtime: SpeakSwiftly.Runtime

        init(runtime: SpeakSwiftly.Runtime) {
            self.runtime = runtime
        }

        public func activeProfile() async -> TextForSpeech.Profile {
            await runtime.normalizerActiveProfile()
        }

        public func baseProfile() async -> TextForSpeech.Profile {
            await runtime.normalizerBaseProfile()
        }

        public func profile(named name: String) async -> TextForSpeech.Profile? {
            await runtime.normalizerProfile(named: name)
        }

        public func profiles() async -> [TextForSpeech.Profile] {
            await runtime.normalizerProfiles()
        }

        public func effectiveProfile(named name: String? = nil) async -> TextForSpeech.Profile {
            await runtime.normalizerEffectiveProfile(named: name)
        }

        public func persistenceURL() async -> URL? {
            await runtime.normalizerPersistenceURL()
        }

        public func loadProfiles() async throws {
            try await runtime.normalizerLoadProfiles()
        }

        public func saveProfiles() async throws {
            try await runtime.normalizerSaveProfiles()
        }

        public func createProfile(
            id: String,
            named name: String,
            replacements: [TextForSpeech.Replacement] = []
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerCreateProfile(
                id: id,
                named: name,
                replacements: replacements
            )
        }

        public func storeProfile(_ profile: TextForSpeech.Profile) async throws {
            try await runtime.normalizerStoreProfile(profile)
        }

        public func useProfile(_ profile: TextForSpeech.Profile) async throws {
            try await runtime.normalizerUseProfile(profile)
        }

        public func removeProfile(named name: String) async throws {
            try await runtime.normalizerRemoveProfile(named: name)
        }

        public func reset() async throws {
            try await runtime.normalizerReset()
        }

        public func addReplacement(
            _ replacement: TextForSpeech.Replacement
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerAddReplacement(replacement)
        }

        public func addReplacement(
            _ replacement: TextForSpeech.Replacement,
            toStoredProfileNamed name: String
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerAddReplacement(
                replacement,
                toStoredProfileNamed: name
            )
        }

        public func replaceReplacement(
            _ replacement: TextForSpeech.Replacement
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerReplaceReplacement(replacement)
        }

        public func replaceReplacement(
            _ replacement: TextForSpeech.Replacement,
            inStoredProfileNamed name: String
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerReplaceReplacement(
                replacement,
                inStoredProfileNamed: name
            )
        }

        public func removeReplacement(
            id replacementID: String
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerRemoveReplacement(id: replacementID)
        }

        public func removeReplacement(
            id replacementID: String,
            fromStoredProfileNamed name: String
        ) async throws -> TextForSpeech.Profile {
            try await runtime.normalizerRemoveReplacement(
                id: replacementID,
                fromStoredProfileNamed: name
            )
        }
    }
}
