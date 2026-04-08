import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

public extension SpeakSwiftly.Normalizer {
    // MARK: Profile Inspection

    func activeProfile() -> TextForSpeech.Profile {
        textRuntime.customProfile
    }

    func baseProfile() -> TextForSpeech.Profile {
        textRuntime.baseProfile
    }

    func profile(id: String) -> TextForSpeech.Profile? {
        textRuntime.profile(named: id)
    }

    func profiles() -> [TextForSpeech.Profile] {
        textRuntime.storedProfiles()
    }

    func effectiveProfile(id: String? = nil) -> TextForSpeech.Profile {
        textRuntime.snapshot(named: id)
    }

    package func persistenceURL() -> URL? {
        textRuntime.persistenceURL
    }

    // MARK: Persistence

    func loadProfiles() throws {
        try textRuntime.load()
    }

    func saveProfiles() throws {
        try textRuntime.save()
    }

    // MARK: Profile Mutation

    func createProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement] = []
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.createProfile(
            id: id,
            named: name,
            replacements: replacements
        )
        try textRuntime.save()
        return profile
    }

    func storeProfile(_ profile: TextForSpeech.Profile) throws {
        textRuntime.store(profile)
        try textRuntime.save()
    }

    func useProfile(_ profile: TextForSpeech.Profile) throws {
        textRuntime.use(profile)
        try textRuntime.save()
    }

    func removeProfile(id: String) throws {
        textRuntime.removeProfile(named: id)
        try textRuntime.save()
    }

    func reset() throws {
        textRuntime.reset()
        try textRuntime.save()
    }

    // MARK: Replacement Mutation

    func addReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = textRuntime.addReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func addReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileID profileID: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.addReplacement(replacement, toStoredProfileNamed: profileID)
        try textRuntime.save()
        return profile
    }

    func replaceReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func replaceReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileID profileID: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement, inStoredProfileNamed: profileID)
        try textRuntime.save()
        return profile
    }

    func removeReplacement(
        id replacementID: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.removeReplacement(id: replacementID)
        try textRuntime.save()
        return profile
    }

    func removeReplacement(
        id replacementID: String,
        fromStoredProfileID profileID: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.removeReplacement(
            id: replacementID,
            fromStoredProfileNamed: profileID
        )
        try textRuntime.save()
        return profile
    }
}
