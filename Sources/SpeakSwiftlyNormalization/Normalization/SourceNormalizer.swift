import Foundation

enum SourceNormalizer {
    // MARK: Public Routing

    static func normalize(
        _ source: String,
        as format: SpeakSwiftlyNormalization.SourceFormat,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .default,
        style: SpeakSwiftlyNormalization.BuiltInProfileStyle = .balanced,
    ) -> String {
        TextNormalizer.normalizeSource(
            source,
            requestContext: requestContext,
            profile: SpeakSwiftlyNormalization.Profile.builtInBase(style: style).merged(with: profile),
            format: format,
        )
    }

    // MARK: Embedded Routing

    static func normalizeEmbedded(
        _ source: String,
        as format: SpeakSwiftlyNormalization.SourceFormat,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        profile: SpeakSwiftlyNormalization.Profile = .base,
    ) -> String {
        TextNormalizer.normalizeSource(
            source,
            requestContext: requestContext,
            profile: profile,
            format: format,
        )
    }
}
