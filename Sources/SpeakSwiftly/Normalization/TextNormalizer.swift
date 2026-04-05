import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

extension SpeakSwiftly.Runtime {
    func normalizerActiveProfile() -> TextForSpeech.Profile {
        textRuntime.customProfile
    }

    func normalizerBaseProfile() -> TextForSpeech.Profile {
        textRuntime.baseProfile
    }

    func normalizerProfile(named name: String) -> TextForSpeech.Profile? {
        textRuntime.profile(named: name)
    }

    func normalizerProfiles() -> [TextForSpeech.Profile] {
        textRuntime.storedProfiles()
    }

    func normalizerEffectiveProfile(named name: String? = nil) -> TextForSpeech.Profile {
        textRuntime.snapshot(named: name)
    }

    func normalizerPersistenceURL() -> URL? {
        textRuntime.persistenceURL
    }

    func normalizerLoadProfiles() throws {
        try textRuntime.load()
    }

    func normalizerSaveProfiles() throws {
        try textRuntime.save()
    }

    func normalizerCreateProfile(
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

    func normalizerStoreProfile(_ profile: TextForSpeech.Profile) throws {
        textRuntime.store(profile)
        try textRuntime.save()
    }

    func normalizerUseProfile(_ profile: TextForSpeech.Profile) throws {
        textRuntime.use(profile)
        try textRuntime.save()
    }

    func normalizerRemoveProfile(named name: String) throws {
        textRuntime.removeProfile(named: name)
        try textRuntime.save()
    }

    func normalizerReset() throws {
        textRuntime.reset()
        try textRuntime.save()
    }

    func normalizerAddReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = textRuntime.addReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func normalizerAddReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.addReplacement(replacement, toStoredProfileNamed: name)
        try textRuntime.save()
        return profile
    }

    func normalizerReplaceReplacement(
        _ replacement: TextForSpeech.Replacement
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement)
        try textRuntime.save()
        return profile
    }

    func normalizerReplaceReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredProfileNamed name: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.replaceReplacement(replacement, inStoredProfileNamed: name)
        try textRuntime.save()
        return profile
    }

    func normalizerRemoveReplacement(
        id replacementID: String
    ) throws -> TextForSpeech.Profile {
        let profile = try textRuntime.removeReplacement(id: replacementID)
        try textRuntime.save()
        return profile
    }

    func normalizerRemoveReplacement(
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
