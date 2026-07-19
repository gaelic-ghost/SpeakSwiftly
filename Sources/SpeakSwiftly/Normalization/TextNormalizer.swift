import Foundation
import SpeakSwiftlyNormalization

// MARK: - State

private extension SpeakSwiftly.Normalizer {
    var activeCustomProfile: SpeakSwiftly.TextProfile {
        storedCustomProfilesByID[activeCustomProfileID] ?? .default
    }

    var effectiveProfile: SpeakSwiftly.TextProfile {
        SpeakSwiftly.TextProfile.builtInBase(style: builtInStyle).merged(with: activeCustomProfile)
    }

    func storedProfile(id: SpeakSwiftly.TextProfileID) throws -> SpeakSwiftly.TextProfile {
        guard let profile = storedCustomProfilesByID[id] else {
            throw SpeakSwiftly.TextProfileError.profileNotFound(id)
        }

        return profile
    }

    func profileDetails(id: SpeakSwiftly.TextProfileID) throws -> SpeakSwiftly.TextProfileDetails {
        try SpeakSwiftly.TextProfileDetails(profile: storedProfile(id: id))
    }

    func profileSummaries() -> [SpeakSwiftly.TextProfileSummary] {
        storedCustomProfilesByID.values
            .sorted { lhs, rhs in
                if lhs.name == rhs.name { return lhs.id < rhs.id }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map(SpeakSwiftly.TextProfileSummary.init(profile:))
    }

    func makeProfileID(from name: String) -> SpeakSwiftly.TextProfileID {
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let base = collapsed.isEmpty ? "profile" : collapsed

        guard storedCustomProfilesByID[base] != nil else { return base }

        var suffix = 2
        while storedCustomProfilesByID["\(base)-\(suffix)"] != nil {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    func persistMutation() throws {
        try savePersistence()
    }
}

// MARK: - Style

public extension SpeakSwiftly.Normalizer.Style {
    /// Returns the active built-in text style.
    func getActive() async -> SpeakSwiftly.TextProfileStyle {
        await normalizer.builtInStyle
    }

    /// Lists the built-in text styles available for activation.
    func list() async -> [SpeakSwiftly.TextProfileStyleOption] {
        SpeakSwiftly.TextProfileStyle.allCases.map { style in
            let summary = switch style {
                case .balanced: "Balanced spoken-code defaults for everyday developer text."
                case .compact: "Keeps source-like text more visual and less expanded."
                case .explicit: "Uses more verbose code narration for maximum clarity."
            }
            return SpeakSwiftly.TextProfileStyleOption(
                style: style,
                summary: summary,
            )
        }
    }

    /// Activates one built-in text style.
    func setActive(to style: SpeakSwiftly.TextProfileStyle) async throws {
        try await normalizer.setActiveStyle(style)
    }
}

private extension SpeakSwiftly.Normalizer {
    func setActiveStyle(_ style: SpeakSwiftly.TextProfileStyle) throws {
        builtInStyle = style
        try persistMutation()
    }
}

// MARK: - Summarization

public extension SpeakSwiftly.Normalizer.Summarization {
    /// Returns the active summarization provider.
    func get() async -> SpeakSwiftly.SummarizationProvider {
        await normalizer.activeSummarizationProvider
    }

    /// Lists the summarization providers available for selection.
    func list() async -> [SpeakSwiftly.SummarizationProviderOption] {
        SpeakSwiftly.SummarizationProvider.allCases.map { provider in
            let summary = switch provider {
                case .codexExec: "Runs summarization through the local Codex CLI with codex exec."
                case .openAIResponses: "Calls the OpenAI Responses API with OPENAI_API_KEY from the process environment."
                case .foundationModels: "Uses Apple's on-device Foundation Models framework when available on this device."
                case .test: "Returns the input unchanged for deterministic tests."
            }
            return SpeakSwiftly.SummarizationProviderOption(
                provider: provider,
                summary: summary,
            )
        }
    }

    /// Selects the summarization provider used by future summarized requests.
    func set(_ provider: SpeakSwiftly.SummarizationProvider) async throws {
        try await normalizer.setSummarizationProvider(provider)
    }
}

extension SpeakSwiftly.Normalizer {
    func setSummarizationProvider(_ provider: SpeakSwiftly.SummarizationProvider) throws {
        activeSummarizationProvider = provider
        try persistMutation()
    }
}

// MARK: - Profiles

public extension SpeakSwiftly.Normalizer.Profiles {
    /// Returns the active custom text profile details.
    func getActive() async -> SpeakSwiftly.TextProfileDetails {
        await SpeakSwiftly.TextProfileDetails(profile: normalizer.activeCustomProfile)
    }

    /// Returns one stored custom text profile by stable identifier.
    func get(id: SpeakSwiftly.TextProfileID) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.profileDetails(id: id)
    }

    /// Lists the stored custom text profiles.
    func list() async -> [SpeakSwiftly.TextProfileSummary] {
        await normalizer.profileSummaries()
    }

    /// Returns the active profile merged over the built-in style.
    func getEffective() async -> SpeakSwiftly.TextProfileDetails {
        await SpeakSwiftly.TextProfileDetails(profile: normalizer.effectiveProfile)
    }

    /// Creates one stored custom text profile from a display name.
    @discardableResult
    func create(name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.createProfile(name: name)
    }

    /// Renames one stored custom text profile without changing its identifier.
    @discardableResult
    func rename(profile id: SpeakSwiftly.TextProfileID, to name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.renameProfile(id: id, to: name)
    }

    /// Makes one stored custom text profile active.
    func setActive(id: SpeakSwiftly.TextProfileID) async throws {
        try await normalizer.setActiveProfile(id: id)
    }

    /// Deletes one stored custom text profile.
    func delete(id: SpeakSwiftly.TextProfileID) async throws {
        try await normalizer.deleteProfile(id: id)
    }

    /// Resets the complete text-profile store to package defaults.
    func factoryReset() async throws {
        try await normalizer.factoryResetProfiles()
    }

    /// Removes every custom replacement from one stored profile.
    func reset(id: SpeakSwiftly.TextProfileID) async throws {
        try await normalizer.resetProfile(id: id)
    }

    /// Adds one replacement to the active custom profile.
    @discardableResult
    func addReplacement(_ replacement: SpeakSwiftly.TextReplacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.addReplacement(replacement, toProfile: nil)
    }

    /// Adds one replacement to a selected custom profile.
    @discardableResult
    func addReplacement(
        _ replacement: SpeakSwiftly.TextReplacement,
        toProfile id: SpeakSwiftly.TextProfileID,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.addReplacement(replacement, toProfile: id)
    }

    /// Replaces one rule in the active custom profile.
    @discardableResult
    func patchReplacement(_ replacement: SpeakSwiftly.TextReplacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.patchReplacement(replacement, inProfile: nil)
    }

    /// Replaces one rule in a selected custom profile.
    @discardableResult
    func patchReplacement(
        _ replacement: SpeakSwiftly.TextReplacement,
        inProfile id: SpeakSwiftly.TextProfileID,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.patchReplacement(replacement, inProfile: id)
    }

    /// Removes one rule from the active custom profile.
    @discardableResult
    func removeReplacement(id replacementID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.removeReplacement(id: replacementID, fromProfile: nil)
    }

    /// Removes one rule from a selected custom profile.
    @discardableResult
    func removeReplacement(
        id replacementID: String,
        fromProfile profileID: SpeakSwiftly.TextProfileID,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await normalizer.removeReplacement(id: replacementID, fromProfile: profileID)
    }
}

extension SpeakSwiftly.Normalizer {
    func createProfile(name: String) throws -> SpeakSwiftly.TextProfileDetails {
        let id = makeProfileID(from: name)
        guard storedCustomProfilesByID[id] == nil else {
            throw SpeakSwiftly.TextProfileError.profileAlreadyExists(id)
        }

        let profile = SpeakSwiftly.TextProfile(id: id, name: name)
        storedCustomProfilesByID[id] = profile
        try persistMutation()
        return SpeakSwiftly.TextProfileDetails(profile: profile)
    }

    func renameProfile(id: SpeakSwiftly.TextProfileID, to name: String) throws -> SpeakSwiftly.TextProfileDetails {
        let profile = try storedProfile(id: id).named(name)
        storedCustomProfilesByID[id] = profile
        try persistMutation()
        return SpeakSwiftly.TextProfileDetails(profile: profile)
    }

    func setActiveProfile(id: SpeakSwiftly.TextProfileID) throws {
        _ = try storedProfile(id: id)
        activeCustomProfileID = id
        try persistMutation()
    }

    func deleteProfile(id: SpeakSwiftly.TextProfileID) throws {
        storedCustomProfilesByID.removeValue(forKey: id)
        repairProfileState()
        try persistMutation()
    }

    func factoryResetProfiles() throws {
        activeCustomProfileID = SpeakSwiftly.TextProfile.default.id
        storedCustomProfilesByID = [SpeakSwiftly.TextProfile.default.id: .default]
        try persistMutation()
    }

    func resetProfile(id: SpeakSwiftly.TextProfileID) throws {
        let stored = try storedProfile(id: id)
        storedCustomProfilesByID[id] = SpeakSwiftly.TextProfile(id: stored.id, name: stored.name)
        try persistMutation()
    }

    func addReplacement(
        _ replacement: SpeakSwiftly.TextReplacement,
        toProfile profileID: SpeakSwiftly.TextProfileID?,
    ) throws -> SpeakSwiftly.TextProfileDetails {
        let id = profileID ?? activeCustomProfileID
        let profile = try storedProfile(id: id).adding(replacement)
        storedCustomProfilesByID[id] = profile
        try persistMutation()
        return SpeakSwiftly.TextProfileDetails(profile: profile)
    }

    func patchReplacement(
        _ replacement: SpeakSwiftly.TextReplacement,
        inProfile profileID: SpeakSwiftly.TextProfileID?,
    ) throws -> SpeakSwiftly.TextProfileDetails {
        let id = profileID ?? activeCustomProfileID
        let profile = try storedProfile(id: id).replacing(replacement)
        storedCustomProfilesByID[id] = profile
        try persistMutation()
        return SpeakSwiftly.TextProfileDetails(profile: profile)
    }

    func removeReplacement(
        id replacementID: String,
        fromProfile profileID: SpeakSwiftly.TextProfileID?,
    ) throws -> SpeakSwiftly.TextProfileDetails {
        let id = profileID ?? activeCustomProfileID
        let profile = try storedProfile(id: id).removingReplacement(id: replacementID)
        storedCustomProfilesByID[id] = profile
        try persistMutation()
        return SpeakSwiftly.TextProfileDetails(profile: profile)
    }

    func repairProfileState() {
        let repaired = Self.repairedProfileState(
            activeProfileID: activeCustomProfileID,
            profiles: storedCustomProfilesByID,
        )
        activeCustomProfileID = repaired.activeProfileID
        storedCustomProfilesByID = repaired.profiles
    }
}

extension SpeakSwiftly.Normalizer {
    static func repairedProfileState(
        activeProfileID: SpeakSwiftly.TextProfileID,
        profiles: [SpeakSwiftly.TextProfileID: SpeakSwiftly.TextProfile],
    ) -> (activeProfileID: SpeakSwiftly.TextProfileID, profiles: [SpeakSwiftly.TextProfileID: SpeakSwiftly.TextProfile]) {
        var repairedProfiles = profiles
        if repairedProfiles[SpeakSwiftly.TextProfile.default.id] == nil {
            repairedProfiles[SpeakSwiftly.TextProfile.default.id] = .default
        }
        let repairedActiveID = repairedProfiles[activeProfileID] == nil
            ? SpeakSwiftly.TextProfile.default.id
            : activeProfileID
        return (repairedActiveID, repairedProfiles)
    }
}

// MARK: - Normalization

public extension SpeakSwiftly.Normalizer {
    /// Normalizes ordinary text for speech using the selected profile and provider.
    func speechText(
        _ text: String,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        textProfileID: SpeakSwiftly.TextProfileID? = nil,
        summarize: Bool = false,
    ) async throws -> String {
        let profile = if let textProfileID {
            try storedProfile(id: textProfileID)
        } else {
            activeCustomProfile
        }
        return try await SpeakSwiftlyNormalization.Normalize.process(
            .init(
                input: .text(text),
                requestContext: requestContext,
                customProfile: profile,
                style: builtInStyle,
                summarizationProvider: activeSummarizationProvider,
                summarize: summarize,
            ),
        )
    }

    /// Normalizes whole source code for speech using an explicit language family.
    func speechSource(
        _ source: String,
        as format: SpeakSwiftly.SourceFormat,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        textProfileID: SpeakSwiftly.TextProfileID? = nil,
        summarize: Bool = false,
    ) async throws -> String {
        let profile = if let textProfileID {
            try storedProfile(id: textProfileID)
        } else {
            activeCustomProfile
        }
        return try await SpeakSwiftlyNormalization.Normalize.process(
            .init(
                input: .source(source, as: format),
                requestContext: requestContext,
                customProfile: profile,
                style: builtInStyle,
                summarizationProvider: activeSummarizationProvider,
                summarize: summarize,
            ),
        )
    }

    /// Detects the text family selected by the normalizer's structure heuristics.
    nonisolated static func detectTextFormat(in text: String) -> SpeakSwiftly.TextFormat {
        SpeakSwiftlyNormalization.Normalize.detectTextFormat(in: text)
    }
}
