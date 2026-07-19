extension SpeakSwiftlyNormalization.Profile {
    /// Literal extension aliases for file suffixes whose raw token shapes are
    /// too acronym-dense or cluster-heavy to sound natural when spoken.
    static let extensionAliasReplacements: [SpeakSwiftlyNormalization.Replacement] = [
        spokenExtensionAlias(".xcodeproj", as: ".xcode-project", id: "base-xcodeproj-extension"),
        spokenExtensionAlias(".pbxproj", as: ".xcode-project-file", id: "base-pbxproj-extension"),
        spokenExtensionAlias(".xcworkspace", as: ".xcode-workspace", id: "base-xcworkspace-extension"),
        spokenExtensionAlias(".xcconfig", as: ".xcode-config", id: "base-xcconfig-extension"),
        spokenExtensionAlias(".xcscheme", as: ".xcode-scheme", id: "base-xcscheme-extension"),
        spokenExtensionAlias(".xctestplan", as: ".xcode-test-plan", id: "base-xctestplan-extension"),
        spokenExtensionAlias(".xcresult", as: ".xcode-result-bundle", id: "base-xcresult-extension"),
        spokenExtensionAlias(".xcassets", as: ".xcode-asset-catalog", id: "base-xcassets-extension"),
        spokenExtensionAlias(".xcstrings", as: ".xcode-string-catalog", id: "base-xcstrings-extension"),
        spokenExtensionAlias(".xcprivacy", as: ".privacy-manifest", id: "base-xcprivacy-extension"),
        spokenExtensionAlias(".entitlements", as: ".entitlements", id: "base-entitlements-extension"),
        spokenExtensionAlias(".dSYM", as: ".debug-symbols-bundle", id: "base-dsym-extension"),
        spokenExtensionAlias(".mdx", as: ".markdown-jsx", id: "base-mdx-extension"),
        spokenExtensionAlias(".tsx", as: ".typescript-jsx", id: "base-tsx-extension"),
        spokenExtensionAlias(".jsx", as: ".javascript-jsx", id: "base-jsx-extension"),
        spokenExtensionAlias(".jsonc", as: ".json-with-comments", id: "base-jsonc-extension"),
        spokenExtensionAlias(".toml", as: ".toml", id: "base-toml-extension"),
        spokenExtensionAlias(".yaml", as: ".yaml", id: "base-yaml-extension"),
        spokenExtensionAlias(".yml", as: ".yaml", id: "base-yml-extension"),
        spokenExtensionAlias(".ipynb", as: ".jupyter-notebook", id: "base-ipynb-extension"),
        spokenExtensionAlias(".wasm", as: ".web-assembly", id: "base-wasm-extension"),
        spokenExtensionAlias(".sqlite", as: ".sqlite-database", id: "base-sqlite-extension"),
        spokenExtensionAlias(".db", as: ".database", id: "base-db-extension"),
    ]

    private static func spokenExtensionAlias(
        _ extensionText: String,
        as spokenAlias: String,
        id: String,
    ) -> SpeakSwiftlyNormalization.Replacement {
        // Keep these aliases ahead of file-reference narration so rewritten
        // suffixes are already in place when path and file-line passes run.
        SpeakSwiftlyNormalization.Replacement(
            extensionText,
            with: spokenAlias,
            id: id,
            priority: 35,
        )
    }
}
