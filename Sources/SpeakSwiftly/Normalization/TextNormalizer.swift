import Foundation
import TextForSpeech

// MARK: - Text Normalization Logic

private extension SpeakSwiftly.Normalizer {
    func profile(from details: TextForSpeech.Runtime.Profiles.Details) -> TextForSpeech.Profile {
        TextForSpeech.Profile(
            id: details.id,
            name: details.summary.name,
            replacements: details.replacements,
        )
    }

    func activeTextProfileDetails() -> TextForSpeech.Runtime.Profiles.Details {
        textRuntime.profiles.getActive()
    }

    func effectiveTextProfileDetails() -> TextForSpeech.Runtime.Profiles.Details {
        textRuntime.profiles.getEffective()
    }

    func textProfileDetails(id: String) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.get(id: id)
    }

    func textProfileSummaries() -> [TextForSpeech.Runtime.Profiles.Summary] {
        textRuntime.profiles.list()
    }

    func activeTextProfile() -> TextForSpeech.Profile {
        profile(from: activeTextProfileDetails())
    }

    func storedTextProfile(id: String) throws -> TextForSpeech.Profile {
        try profile(from: textProfileDetails(id: id))
    }

    func activeTextProfileStyle() -> TextForSpeech.BuiltInProfileStyle {
        textRuntime.style.getActive()
    }

    func textProfileStyleOptions() -> [TextForSpeech.Runtime.Style.Option] {
        textRuntime.style.list()
    }

    func setActiveTextProfileStyle(
        to style: TextForSpeech.BuiltInProfileStyle,
    ) throws {
        try textRuntime.style.setActive(to: style)
    }

    func createTextProfile(
        name: String,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.create(name: name)
    }

    func renameTextProfile(
        id: String,
        to name: String,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.rename(profile: id, to: name)
    }

    func setActiveTextProfile(
        id: String,
    ) throws {
        try textRuntime.profiles.setActive(id: id)
    }

    func deleteTextProfile(
        id: String,
    ) throws {
        try textRuntime.profiles.delete(id: id)
    }

    func factoryResetTextProfiles() throws {
        try textRuntime.profiles.factoryReset()
    }

    func resetTextProfile(
        id: String,
    ) throws {
        try textRuntime.profiles.reset(id: id)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.addReplacement(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toProfile id: String,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.addReplacement(replacement, toProfile: id)
    }

    func patchTextReplacement(
        _ replacement: TextForSpeech.Replacement,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.patchReplacement(replacement)
    }

    func patchTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inProfile id: String,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.patchReplacement(replacement, inProfile: id)
    }

    func removeTextReplacement(
        id replacementID: String,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromProfile profileID: String,
    ) throws -> TextForSpeech.Runtime.Profiles.Details {
        try textRuntime.profiles.removeReplacement(id: replacementID, fromProfile: profileID)
    }

    func normalizeSpeechText(
        _ text: String,
        sourceFormat: TextForSpeech.SourceFormat?,
        context: TextForSpeech.InputContext?,
        textProfileID: SpeakSwiftly.TextProfileID?,
    ) async throws -> String {
        let textProfile = if let textProfileID,
                             let storedProfile = try? storedTextProfile(id: textProfileID) {
            storedProfile
        } else {
            activeTextProfile()
        }
        let style = textRuntime.builtInStyle
        let summarizationProvider = textRuntime.activeSummarizationProvider

        if let sourceFormat {
            return try await TextForSpeech.Normalize.source(
                text,
                as: sourceFormat,
                withContext: context,
                customProfile: textProfile,
                style: style,
                summarizationProvider: summarizationProvider,
            )
        }

        return try await TextForSpeech.Normalize.text(
            text,
            withContext: context,
            customProfile: textProfile,
            style: style,
            summarizationProvider: summarizationProvider,
        )
    }
}

public extension SpeakSwiftly.Normalizer.Style {
    /// Returns the active built-in text style.
    func getActive() async -> TextForSpeech.BuiltInProfileStyle {
        await normalizer.activeTextProfileStyle()
    }

    /// Lists the built-in text styles available for activation.
    func list() async -> [TextForSpeech.Runtime.Style.Option] {
        await normalizer.textProfileStyleOptions()
    }

    /// Activates one built-in text style.
    func setActive(
        to style: TextForSpeech.BuiltInProfileStyle,
    ) async throws {
        try await normalizer.setActiveTextProfileStyle(to: style)
    }
}

public extension SpeakSwiftly.Normalizer.Profiles {
    /// Returns the active custom text profile details.
    func getActive() async -> TextForSpeech.Runtime.Profiles.Details {
        await normalizer.activeTextProfileDetails()
    }

    /// Returns one stored custom text profile by stable identifier.
    func get(
        id: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.textProfileDetails(id: id)
    }

    /// Lists the stored custom text profiles.
    func list() async -> [TextForSpeech.Runtime.Profiles.Summary] {
        await normalizer.textProfileSummaries()
    }

    /// Returns the effective text profile after the built-in style and active custom profile are merged.
    func getEffective() async -> TextForSpeech.Runtime.Profiles.Details {
        await normalizer.effectiveTextProfileDetails()
    }

    /// Creates one stored custom text profile from a display name.
    @discardableResult
    func create(
        name: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.createTextProfile(name: name)
    }

    /// Renames one stored custom text profile without changing its stable identifier.
    @discardableResult
    func rename(
        profile id: String,
        to name: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.renameTextProfile(id: id, to: name)
    }

    /// Makes one stored custom text profile active.
    func setActive(
        id: String,
    ) async throws {
        try await normalizer.setActiveTextProfile(id: id)
    }

    /// Deletes one stored custom text profile.
    func delete(
        id: String,
    ) async throws {
        try await normalizer.deleteTextProfile(id: id)
    }

    /// Resets the whole text-profile store to the package defaults.
    func factoryReset() async throws {
        try await normalizer.factoryResetTextProfiles()
    }

    /// Resets one stored custom text profile back to an empty custom profile with the same identifier and name.
    func reset(
        id: String,
    ) async throws {
        try await normalizer.resetTextProfile(id: id)
    }

    /// Adds one replacement rule to the active custom text profile.
    @discardableResult
    func addReplacement(
        _ replacement: TextForSpeech.Replacement,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.addTextReplacement(replacement)
    }

    /// Adds one replacement rule to one stored custom text profile.
    @discardableResult
    func addReplacement(
        _ replacement: TextForSpeech.Replacement,
        toProfile id: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.addTextReplacement(replacement, toProfile: id)
    }

    /// Replaces one existing replacement rule on the active custom text profile.
    @discardableResult
    func patchReplacement(
        _ replacement: TextForSpeech.Replacement,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.patchTextReplacement(replacement)
    }

    /// Replaces one existing replacement rule on one stored custom text profile.
    @discardableResult
    func patchReplacement(
        _ replacement: TextForSpeech.Replacement,
        inProfile id: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.patchTextReplacement(replacement, inProfile: id)
    }

    /// Removes one replacement rule from the active custom text profile.
    @discardableResult
    func removeReplacement(
        id replacementID: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.removeTextReplacement(id: replacementID)
    }

    /// Removes one replacement rule from one stored custom text profile.
    @discardableResult
    func removeReplacement(
        id replacementID: String,
        fromProfile profileID: String,
    ) async throws -> TextForSpeech.Runtime.Profiles.Details {
        try await normalizer.removeTextReplacement(id: replacementID, fromProfile: profileID)
    }
}

public extension SpeakSwiftly.Normalizer {
    /// Normalizes generation text through the shared TextForSpeech runtime.
    func speechText(
        _ text: String,
        sourceFormat: TextForSpeech.SourceFormat? = nil,
        context: TextForSpeech.InputContext? = nil,
        textProfileID: SpeakSwiftly.TextProfileID? = nil,
    ) async throws -> String {
        try await normalizeSpeechText(
            text,
            sourceFormat: sourceFormat,
            context: context,
            textProfileID: textProfileID,
        )
    }
}
