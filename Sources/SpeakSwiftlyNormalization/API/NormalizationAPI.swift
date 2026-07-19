import Foundation

public extension SpeakSwiftlyNormalization {
    enum Normalize {}

    struct NormalizationRequest: Sendable {
        public enum Input: Sendable {
            case text(String)
            case source(String, as: SourceFormat)
        }

        public let input: Input
        public let requestContext: RequestContext?
        public let customProfile: Profile
        public let style: BuiltInProfileStyle
        public let summarizationProvider: SummarizationProvider
        public let summarize: Bool

        public init(
            input: Input,
            requestContext: RequestContext? = nil,
            customProfile: Profile = .default,
            style: BuiltInProfileStyle = .balanced,
            summarizationProvider: SummarizationProvider = .foundationModels,
            summarize: Bool = false,
        ) {
            self.input = input
            self.requestContext = requestContext
            self.customProfile = customProfile
            self.style = style
            self.summarizationProvider = summarizationProvider
            self.summarize = summarize
        }
    }
}

public extension SpeakSwiftlyNormalization.Normalize {
    static func process(_ request: SpeakSwiftlyNormalization.NormalizationRequest) async throws -> String {
        switch request.input {
            case let .text(text):
                let preparedText = if request.summarize {
                    try await TextSummarizer.summarize(text, provider: request.summarizationProvider)
                } else {
                    text
                }
                let normalized = TextNormalizer.normalizeText(
                    preparedText,
                    requestContext: request.requestContext,
                    profile: SpeakSwiftlyNormalization.Profile.builtInBase(style: request.style)
                        .merged(with: request.customProfile),
                    format: nil,
                )
                return request.requestContext?.prefacing(normalized) ?? normalized

            case let .source(source, format):
                let normalizedSource = SourceNormalizer.normalize(
                    source,
                    as: format,
                    requestContext: request.requestContext,
                    profile: request.customProfile,
                    style: request.style,
                )
                guard request.summarize else {
                    return request.requestContext?.prefacing(normalizedSource) ?? normalizedSource
                }

                let summarizedSource = try await TextSummarizer.summarize(
                    normalizedSource,
                    provider: request.summarizationProvider,
                )
                let normalized = TextNormalizer.normalizeText(
                    summarizedSource,
                    requestContext: request.requestContext,
                    profile: SpeakSwiftlyNormalization.Profile.builtInBase(style: request.style)
                        .merged(with: request.customProfile),
                    format: .plain,
                )
                return request.requestContext?.prefacing(normalized) ?? normalized
        }
    }

    static func text(
        _ text: String,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        customProfile: SpeakSwiftlyNormalization.Profile = .default,
        style: SpeakSwiftlyNormalization.BuiltInProfileStyle = .balanced,
        summarizationProvider: SpeakSwiftlyNormalization.SummarizationProvider = .foundationModels,
        summarize: Bool = false,
    ) async throws -> String {
        try await process(
            .init(
                input: .text(text),
                requestContext: requestContext,
                customProfile: customProfile,
                style: style,
                summarizationProvider: summarizationProvider,
                summarize: summarize,
            ),
        )
    }

    static func source(
        _ source: String,
        as format: SpeakSwiftlyNormalization.SourceFormat,
        requestContext: SpeakSwiftlyNormalization.RequestContext? = nil,
        customProfile: SpeakSwiftlyNormalization.Profile = .default,
        style: SpeakSwiftlyNormalization.BuiltInProfileStyle = .balanced,
        summarizationProvider: SpeakSwiftlyNormalization.SummarizationProvider = .foundationModels,
        summarize: Bool = false,
    ) async throws -> String {
        try await process(
            .init(
                input: .source(source, as: format),
                requestContext: requestContext,
                customProfile: customProfile,
                style: style,
                summarizationProvider: summarizationProvider,
                summarize: summarize,
            ),
        )
    }

    static func detectTextFormat(in text: String) -> SpeakSwiftlyNormalization.TextFormat {
        TextNormalizer.detectTextFormat(in: text)
    }
}
