import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

public extension SpeakSwiftly.Normalizer {
    func activeProfile() -> TextForSpeech.Profile {
        textRuntime.customProfile
    }

    func baseProfile() -> TextForSpeech.Profile {
        textRuntime.baseProfile
    }

    func profile(named name: String) -> TextForSpeech.Profile? {
        textRuntime.profile(named: name)
    }

    func profiles() -> [TextForSpeech.Profile] {
        textRuntime.storedProfiles()
    }

    func effectiveProfile(named name: String? = nil) -> TextForSpeech.Profile {
        textRuntime.snapshot(named: name)
    }

    func persistenceURL() -> URL? {
        textRuntime.persistenceURL
    }

    func loadProfiles() throws {
        try textRuntime.load()
    }

    func saveProfiles() throws {
        try textRuntime.save()
    }

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

    func removeProfile(named name: String) throws {
        textRuntime.removeProfile(named: name)
        try textRuntime.save()
    }

    func reset() throws {
        textRuntime.reset()
        try textRuntime.save()
    }

    func addReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = textRuntime.addReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func addReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.addReplacement(replacement, toStoredProfileNamed: name)
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
        inStoredProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement, inStoredProfileNamed: name)
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
        fromStoredProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.removeReplacement(
            id: replacementID,
            fromStoredProfileNamed: name
        )
        try textRuntime.save()
        return profile
    }
}
