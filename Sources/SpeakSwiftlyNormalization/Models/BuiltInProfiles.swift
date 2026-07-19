public extension SpeakSwiftlyNormalization.Profile {
    /// The always-on shipped semantic layer composed from the semantic-role
    /// fragments in `Models/BuiltInProfiles/`.
    static let semanticCore = SpeakSwiftlyNormalization.Profile(
        id: "semantic-core",
        name: "Semantic Core",
        replacements:
        scalarPronunciationReplacements
            + extensionAliasReplacements
            + semanticTokenTransformReplacements,
    )

    static func builtInStyle(_ style: SpeakSwiftlyNormalization.BuiltInProfileStyle) -> SpeakSwiftlyNormalization.Profile {
        switch style {
            case .balanced:
                balancedBuiltInStyle
            case .compact:
                compactBuiltInStyle
            case .explicit:
                explicitBuiltInStyle
        }
    }

    static func builtInBase(
        style: SpeakSwiftlyNormalization.BuiltInProfileStyle,
    ) -> SpeakSwiftlyNormalization.Profile {
        semanticCore.merged(with: builtInStyle(style))
    }

    /// The default built-in base, equivalent to `builtInBase(style: .balanced)`.
    static let base = builtInBase(style: .balanced)
    static let `default` = SpeakSwiftlyNormalization.Profile()
}
